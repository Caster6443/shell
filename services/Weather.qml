pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.utils

Singleton {
    id: root

    property string city
    property string loc
    property var cc
    property list<var> forecast
    property list<var> hourlyForecast

    property bool ipApiRequestPending: false
    property double ipApiBlockedUntil: 0
    property bool citiesLoaded: false
    property string pendingCoords
    property string apiKey
    property string apiHost
    property string resolvedCityName
    property string pendingCityName
    property string sunriseTime
    property string sunsetTime
    property double lastWeatherFetchAt: 0
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`
    readonly property string icon: cc ? Icons.getWeatherIcon(cc.weatherCode) : "cloud_alert"
    readonly property string description: cc?.description || Tr.tr("No weather")
    readonly property string temp: formatTemp(cc?.tempC)
    readonly property string feelsLike: formatTemp(cc?.feelsLikeC)
    readonly property int humidity: cc?.humidity ?? 0
    readonly property real windSpeed: cc?.windSpeed ?? 0
    readonly property string sunrise: sunriseTime ? Qt.formatDateTime(new Date(sunriseTime), Units.twelveHourClock ? "h:mm A" : "h:mm") : "--:--"
    readonly property string sunset: sunsetTime ? Qt.formatDateTime(new Date(sunsetTime), Units.twelveHourClock ? "h:mm A" : "h:mm") : "--:--"

    readonly property var cachedCities: new Map()

    function formatTemp(temp: var, compact = false): string {
        const unit = GlobalConfig.services.weatherUnits;
        const value = temp !== undefined ? Math.round(Units.toTemperature(temp, unit)) : "--";
        return Units.formatTemp(value, unit, compact);
    }

    function reload(): void {
        if (!apiKey || !apiHost)
            return;

        const configLocation = GlobalConfig.services.weatherLocation;

        if (configLocation) {
            if (configLocation.indexOf(",") !== -1 && !isNaN(parseFloat(configLocation.split(",")[0]))) {
                const coords = normalizeCoordinates(configLocation);
                if (loc === coords)
                    fetchWeatherData();
                else
                    loc = coords;
                fetchCityFromCoords(configLocation);
            } else {
                if (resolvedCityName === configLocation && loc) {
                    fetchWeatherData();
                    return;
                }
                fetchCoordsFromCity(configLocation);
            }
            return;
        } else if ((!loc || timer.elapsed() > 900) && !ipApiRequestPending && Date.now() >= ipApiBlockedUntil) {
            ipApiRequestPending = true;

            Requests.get("http://ip-api.com/json?fields=status,message,city,lat,lon", (text, metadata) => {
                ipApiRequestPending = false;
                recordIpApiRateLimit(metadata);

                // Protect against stale responses overwriting the manually-set location,
                // in case the config was updated while this request was in-flight.
                if (GlobalConfig.services.weatherLocation)
                    return;

                let response;
                try {
                    response = JSON.parse(text);
                } catch (error) {
                    console.warn(lc, `Unable to parse response from ip-api: ${error}`);
                    return;
                }

                const lat = Number(response.lat);
                const lon = Number(response.lon);

                if (response.status !== "success" || !Number.isFinite(lat) || !Number.isFinite(lon)) {
                    console.warn(lc, `ip-api lookup failed: ${response.message ?? "invalid response"}`);
                    return;
                }

                city = fixCityName(response.city ?? "");
                timer.restart();
                loc = `${lat},${lon}`;
            }, (error, metadata) => {
                ipApiRequestPending = false;

                if (!recordIpApiRateLimit(metadata))
                    console.warn(lc, `ip-api request failed: ${error}`);
            });
        }
    }

    function recordIpApiRateLimit(metadata: var): bool {
        const remainingHeader = metadata?.headers?.["x-rl"];
        const exhausted = remainingHeader !== undefined && Number(remainingHeader) === 0;

        if (metadata?.statusCode !== 429 && !exhausted)
            return false;

        const ttlHeader = metadata?.headers?.["x-ttl"];
        const ttl = Number(ttlHeader);

        const delaySeconds = Number.isFinite(ttl) ? Math.max(1, Math.ceil(ttl) + 1) : 61;

        const delayMs = delaySeconds * 1000;
        ipApiBlockedUntil = Date.now() + delayMs;
        ipApiRetryTimer.interval = delayMs;
        ipApiRetryTimer.restart();

        return true;
    }

    function requestLanguage(): string {
        const language = Qt.locale().name.split(/[_.@-]/)[0].toLowerCase();
        return /^[a-z]{2,3}$/.test(language) && language !== "c" ? language : "en";
    }

    function fixCityName(cityName: string): string {
        if (!cityName)
            return "";
        const mapping = {
            // Polish
            "Poznan": "Poznań",
            "Wroclaw": "Wrocław",
            "Krakow": "Kraków",
            "Gdansk": "Gdańsk",
            "Lodz": "Łódź",
            "Rzeszow": "Rzeszów",
            "Torun": "Toruń",
            "Bialystok": "Białystok",
            "Czestochowa": "Częstochowa",
            "Plock": "Płock",
            "Ruda Slaska": "Ruda Śląska",
            "Dabrowa Gornicza": "Dąbrowa Górnicza",
            "Elblag": "Elbląg",
            "Gorzow Wielkopolski": "Gorzów Wielkopolski",
            "Zielona Gora": "Zielona Góra",
            "Slupsk": "Słupsk",

            // German
            "Munchen": "München",
            "Koln": "Köln",
            "Dusseldorf": "Düsseldorf",
            "Nurnberg": "Nürnberg",

            // French & Spanish & Portuguese
            "Sao Paulo": "São Paulo",
            "Montreal": "Montréal",
            "Quebec": "Québec",
            "Bogota": "Bogotá",
            "Medellin": "Medellín",
            "Cordoba": "Córdoba",

            // Turkish
            "Istanbul": "İstanbul",
            "Izmir": "İzmir",

            // Scandinavian & others
            "Malmo": "Malmö",
            "Goteborg": "Göteborg",
            "Zurich": "Zürich",
            "Geneve": "Genève"
        };
        return mapping[cityName] || cityName;
    }

    function cacheCity(coords: string, cityName: string): void {
        cachedCities.set(coords, cityName);
        citiesSaveTimer.restart();
    }

    function fetchCityFromCoords(coords: string): void {
        if (cachedCities.has(coords)) {
            city = cachedCities.get(coords);
            return;
        }

        // Defer until cache is loaded
        if (!citiesLoaded) {
            pendingCoords = coords;
            return;
        }

        const [lat, lon] = coords.split(",").map(s => s.trim());
        const lang = root.requestLanguage();

        const nominatimUrl = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=geocodejson&accept-language=${lang}`;
        const nominatimHeaders = {
            "User-Agent": `caelestia-shell/${CUtils.version} (+https://github.com/caelestia-dots/shell)`
        };

        Requests.get(nominatimUrl, text => {
            let geo;
            try {
                geo = JSON.parse(text).features?.[0]?.properties.geocoding;
            } catch (error) {
                console.warn(lc, `Unable to parse response from nominatim: ${error}`);
                city = Tr.trCtx("Unknown city", "weather location unavailable");
                return;
            }

            if (geo) {
                const geoCity = geo.type === "city" ? geo.name : geo.city;
                if (geoCity) {
                    city = fixCityName(geoCity);
                    cacheCity(coords, city);
                    return;
                }
            }

            console.warn(lc, "No locality in nominatim response");
            city = Tr.trCtx("Unknown city", "weather location unavailable");
        }, error => {
            console.warn(lc, `Nominatim request failed: ${error}`);
            city = Tr.trCtx("Unknown city", "weather location unavailable");
        }, nominatimHeaders);
    }

    function fetchCoordsFromCity(cityName: string): void {
        if (pendingCityName === cityName)
            return;

        pendingCityName = cityName;
        const lang = root.requestLanguage();
        const path = `/geo/v2/city/lookup?location=${encodeURIComponent(cityName)}&lang=${encodeURIComponent(lang)}`;
        requestQWeather(path, json => {
            root.pendingCityName = "";
            const result = json.location?.[0];
            if (!result || !Number.isFinite(Number(result.lat)) || !Number.isFinite(Number(result.lon))) {
                console.warn(lc, `QWeather city lookup returned no coordinates for ${cityName}`);
                return;
            }

            const coords = `${Number(result.lat).toFixed(2)},${Number(result.lon).toFixed(2)}`;
            root.city = fixCityName(result.name || cityName);
            root.resolvedCityName = cityName;
            console.info(lc, `QWeather city resolved: ${root.city} (${coords})`);
            if (root.loc === coords)
                root.fetchWeatherData();
            else
                root.loc = coords;
        }, `city lookup for ${cityName}`, () => root.pendingCityName = "");
    }

    function fetchWeatherData(): void {
        if (!apiKey || !apiHost || !loc || loc.indexOf(",") === -1)
            return;

        if (Date.now() - lastWeatherFetchAt < 900000)
            return;
        lastWeatherFetchAt = Date.now();

        const [lat, lon] = normalizeCoordinates(loc).split(",");
        const lang = root.requestLanguage();
        const query = `localTime=true&lang=${encodeURIComponent(lang)}`;

        requestQWeather(`/weather/v1/current/${lat}/${lon}?${query}`, json => {
            if (!json.condition || !json.temperature)
                return;

            root.cc = {
                weatherCode: root.qWeatherIconCode(json.condition.code),
                description: json.condition.text || root.getWeatherCondition(root.qWeatherIconCode(json.condition.code)),
                tempC: Number(json.temperature.value),
                feelsLikeC: Number(json.feelsLike?.value ?? json.temperature.value),
                humidity: Math.round(Number(json.humidity ?? 0) * 100),
                windSpeed: Number(json.wind?.speed?.value ?? 0) * 3.6,
                isDay: true
            };
            console.info(lc, "QWeather current conditions loaded");
        }, "current weather");

        requestQWeather(`/weather/v1/daily/${lat}/${lon}?days=7&${query}`, json => {
            if (!Array.isArray(json.days))
                return;

            const today = json.days[0];
            root.sunriseTime = today?.astro?.sunrise || "";
            root.sunsetTime = today?.astro?.sunset || "";
            root.forecast = json.days.map(day => {
                const code = root.qWeatherIconCode(day.daytime?.condition?.code ?? day.nighttime?.condition?.code);
                return {
                    date: day.forecastStartTime,
                    maxTempC: Number(day.temperatureMax?.value),
                    minTempC: Number(day.temperatureMin?.value),
                    weatherCode: code,
                    icon: Icons.getWeatherIcon(code)
                };
            });
            console.info(lc, `QWeather daily forecast loaded: ${root.forecast.length} days`);
        }, "daily forecast");

        requestQWeather(`/weather/v1/hourly/${lat}/${lon}?hours=24&${query}`, json => {
            if (!Array.isArray(json.hours))
                return;

            const now = new Date();
            root.hourlyForecast = json.hours.filter(hour => new Date(hour.forecastTime) >= now).map(hour => {
                const date = new Date(hour.forecastTime);
                const code = root.qWeatherIconCode(hour.condition?.code);
                return {
                    timestamp: hour.forecastTime,
                    hour: date.getHours(),
                    tempC: Math.round(Number(hour.temperature?.value)),
                    precipChance: Math.round(Number(hour.precipitation?.probability ?? 0) * 100),
                    weatherCode: code,
                    icon: Icons.getWeatherIcon(code)
                };
            });
            console.info(lc, `QWeather hourly forecast loaded: ${root.hourlyForecast.length} hours`);
        }, "hourly forecast");
    }

    function requestQWeather(path: string, onSuccess: var, label: string, onFailure = null): void {
        const host = apiHost.trim().replace(/^https?:\/\//, "").replace(/\/+$/, "");
        const headers = {
            "X-QW-Api-Key": apiKey
        };
        Requests.get(`https://${host}${path}`, text => {
            try {
                onSuccess(JSON.parse(text));
            } catch (error) {
                if (onFailure)
                    onFailure(error);
                console.warn(lc, `Unable to parse QWeather ${label} response: ${error}`);
            }
        }, error => {
            if (onFailure)
                onFailure(error);
            console.warn(lc, `QWeather ${label} request failed: ${error}`);
        }, headers);
    }

    function normalizeCoordinates(coords: string): string {
        const values = coords.split(",").map(value => Number(value.trim()));
        if (values.length !== 2 || !values.every(Number.isFinite))
            return "";
        return `${values[0].toFixed(2)},${values[1].toFixed(2)}`;
    }

    function qWeatherIconCode(code: var): string {
        const value = Number(code);
        if ([100, 150].includes(value))
            return "0";
        if ([102, 103, 152, 153].includes(value))
            return "2";
        if ([101, 104, 151].includes(value))
            return "3";
        if (value === 302 || value === 303)
            return "95";
        if (value === 304)
            return "96";
        if (value >= 300 && value < 400)
            return "61";
        if (value >= 400 && value < 500)
            return "71";
        if (value >= 500 && value <= 515)
            return "45";
        return String(code ?? "");
    }

    function getWeatherCondition(code: string): string {
        const conditions = {
            "0": Tr.tr("Clear"),
            "1": Tr.tr("Clear"),
            "2": Tr.tr("Partly cloudy"),
            "3": Tr.tr("Overcast"),
            "45": Tr.tr("Fog"),
            "48": Tr.tr("Fog"),
            "51": Tr.tr("Drizzle"),
            "53": Tr.tr("Drizzle"),
            "55": Tr.tr("Drizzle"),
            "56": Tr.tr("Freezing drizzle"),
            "57": Tr.tr("Freezing drizzle"),
            "61": Tr.tr("Light rain"),
            "63": Tr.tr("Rain"),
            "65": Tr.tr("Heavy rain"),
            "66": Tr.tr("Light rain"),
            "67": Tr.tr("Heavy rain"),
            "71": Tr.tr("Light snow"),
            "73": Tr.tr("Snow"),
            "75": Tr.tr("Heavy snow"),
            "77": Tr.tr("Snow"),
            "80": Tr.tr("Light rain"),
            "81": Tr.tr("Rain"),
            "82": Tr.tr("Heavy rain"),
            "85": Tr.tr("Light snow showers"),
            "86": Tr.tr("Heavy snow showers"),
            "95": Tr.tr("Thunderstorm"),
            "96": Tr.tr("Thunderstorm with hail"),
            "99": Tr.tr("Thunderstorm with hail")
        };
        return conditions[code] || Tr.trCtx("Unknown", "weather condition");
    }

    onLocChanged: {
        lastWeatherFetchAt = 0;
        fetchWeatherData();
    }
    onCitiesLoadedChanged: {
        if (!citiesLoaded || !pendingCoords)
            return;

        const coords = pendingCoords;
        pendingCoords = "";
        fetchCityFromCoords(coords);
    }

    Connections {
        function onWeatherLocationChanged(): void {
            root.reload();
        }

        target: GlobalConfig.services
    }

    Timer {
        interval: 3600000 // 1 hour
        running: true
        repeat: true
        onTriggered: fetchWeatherData()
    }

    Timer {
        id: ipApiRetryTimer

        repeat: false

        onTriggered: {
            const remaining = root.ipApiBlockedUntil - Date.now();

            if (remaining > 0) {
                interval = Math.ceil(remaining);
                restart();
            } else {
                root.reload();
            }
        }
    }

    Timer {
        id: citiesSaveTimer

        interval: 1000
        onTriggered: {
            if (!root.citiesLoaded)
                return;

            const data = {};
            root.cachedCities.forEach((cityName, coords) => data[coords] = cityName);
            citiesStorage.setText(JSON.stringify(data));
        }
    }

    ElapsedTimer {
        id: timer
    }

    FileView {
        id: qweatherKeyFile

        printErrors: false
        path: `${root.configDir}/caelestia/qweather-api-key`
        onLoaded: {
            root.apiKey = text().trim();
            root.reload();
        }
        onLoadFailed: err => console.warn(lc, `Unable to read local QWeather API key: ${err}`)
    }

    FileView {
        id: qweatherHostFile

        printErrors: false
        path: `${root.configDir}/caelestia/qweather-api-host`
        onLoaded: {
            root.apiHost = text().trim();
            root.reload();
        }
        onLoadFailed: err => console.warn(lc, `Unable to read local QWeather API host: ${err}`)
    }

    FileView {
        id: citiesStorage

        printErrors: false
        path: `${Paths.cache}/cities.json`
        onLoaded: {
            try {
                const data = JSON.parse(text());
                for (const [coords, cityName] of Object.entries(data))
                    if (!root.cachedCities.has(coords))
                        root.cachedCities.set(coords, cityName);
            } catch (error) {
                console.warn(lc, `Unable to parse cached cities: ${error}`);
            }

            root.citiesLoaded = true;
        }
        onLoadFailed: err => {
            root.citiesLoaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText("{}"));
            else
                console.warn(lc, `Unable to load cached cities: ${err}`);
        }
    }

    LoggingCategory {
        id: lc

        name: "caelestia.qml.services.weather"
        defaultLogLevel: LoggingCategory.Info
    }
}
