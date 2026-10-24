// Execute the actual QML JavaScript functions with deterministic network/timers.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const {test} = require('node:test');
const source = fs.readFileSync(require('node:path').join(__dirname, '../../services/Weather.qml'), 'utf8');
const functions = [...source.matchAll(/^    function (\w+)\((.*?)\)(?:: \w+)? \{([\s\S]*?)^    }/gm)]
    .map(m => `function ${m[1]}(${m[2].replace(/:\s*\w+/g, '')}) {${m[3]}}`).join('\n');
function timer() { return {running:false, interval:0, start(){this.running=true}, restart(){this.running=true}, stop(){this.running=false}}; }
function setup() {
    const requests = [];
    const state = {
        loc:'',city:'',apiKey:'test',apiHost:'test.invalid', automaticLocationResolved:false,
        automaticLocationAttempts:0,locationRequestEpoch:0,locationState:'idle',
        ipApiRequestPending:false,ipApiBlockedUntil:0,citiesLoaded:true,cachedCities:new Map(),
        lastWeatherFetchAt:0, pendingCityName:'',resolvedCityName:'',
        GlobalConfig:{services:{weatherLocation:''}},
        Qt:{locale:()=>({name:'zh_CN'})},
        Requests:{get:(...args)=>requests.push(args)},
        locationTimeout:timer(),ipApiRetryTimer:timer(),weatherRetryTimer:timer(),
        console:{info(){},warn(){}},lc:{},Date,Number,Math,JSON,Set,Map,
    };
    state.root=state;
    vm.createContext(state);vm.runInContext(functions,state);
    state.weatherFetches=0;state.reverseLookups=0;
    state.fetchWeatherData=()=>state.weatherFetches++;
    state.fetchCityFromCoords=()=>state.reverseLookups++;
    return {s:state,requests};
}
const success = JSON.stringify({status:'success',city:'测试城市',lat:30.25,lon:120.17});
test('multiple startup callers share one lookup',()=>{
    const {s,requests}=setup();s.reload();s.reload();s.reload();assert.equal(requests.length,1);
});
test('successful startup lookup is reused by hourly/dashboard reloads',()=>{
    const {s,requests}=setup();s.reload();requests[0][1](success,{});
    for(let i=0;i<48;i++)s.reload();
    assert.equal(requests.length,1);assert.equal(s.weatherFetches,48);
    assert.equal(s.loc,'30.25,120.17');assert.equal(s.reverseLookups,1);
});
test('failed location retries at most three times including future hourly reloads',()=>{
    const {s,requests}=setup();
    for(let i=0;i<3;i++){
        s.ipApiRetryTimer.running=false;s.reload();requests[i][2]('offline',{});
    }
    s.reload();assert.equal(requests.length,3);assert.equal(s.locationState,'failed');assert.equal(s.ipApiRetryTimer.running,false);
});
test('watchdog invalidates late responses before the next retry',()=>{
    const {s,requests}=setup();s.reload();s.failAutomaticLocation(s.locationRequestEpoch);
    requests[0][1](success,{});assert.equal(s.loc,'');assert.equal(s.automaticLocationResolved,false);
});
test('late automatic result cannot overwrite manual location',()=>{
    const {s,requests}=setup();s.reload();s.GlobalConfig.services.weatherLocation='手动城市';
    requests[0][1](success,{});assert.equal(s.loc,'');
});
test('malformed JSON and out-of-range coordinates consume bounded attempts',()=>{
    for(const value of ['not json',JSON.stringify({status:'success',lat:91,lon:0}),JSON.stringify({status:'success'})]){
        const {s,requests}=setup();s.reload();requests[0][1](value,{});
        assert.equal(s.automaticLocationResolved,false);assert.equal(s.locationState,'retrying');
    }
});
test('retry wait prevents unrelated reloads from spamming endpoint',()=>{
    const {s,requests}=setup();s.reload();requests[0][2]('offline',{});
    s.reload();s.reload();assert.equal(requests.length,1);
});
test('429 TTL blocks retries without an extra request',()=>{
    const {s,requests}=setup();s.reload();requests[0][2]('rate limited',{statusCode:429,headers:{'x-ttl':'120'}});
    assert.ok(s.ipApiRetryTimer.interval>=120000);s.reload();assert.equal(requests.length,1);
});
test('explicit relocate resets successful result and performs exactly one new lookup',()=>{
    const {s,requests}=setup();s.reload();requests[0][1](success,{});s.refreshLocation();s.reload();
    assert.equal(requests.length,2);assert.equal(s.automaticLocationAttempts,1);assert.equal(s.loc,'');assert.equal(s.city,'');
});
test('manual coordinates bypass IP lookup and reject blank/out-of-range input',()=>{
    const {s,requests}=setup();s.GlobalConfig.services.weatherLocation='30.25,120.17';s.reload();
    assert.equal(requests.length,0);assert.equal(s.loc,'30.25,120.17');
    for(const value of [',','1,','91,0','0,181','NaN,0','0,0,0'])assert.equal(s.normalizeCoordinates(value),'');
    assert.equal(s.normalizeCoordinates('0,0'),'0.00,0.00');
});
test('district labels retain parent city and avoid duplicates',()=>{
    const {s}=setup();assert.equal(s.formatLocationName({adm2:'杭州市',name:'西湖区'}),'杭州市 · 西湖区');
    assert.equal(s.formatLocationName({adm2:'广州市',name:'广州市'}),'广州市');
});
test('reverse lookup passes longitude first and ignores stale location results',()=>{
    const {s}=setup();vm.runInContext(functions,s);s.loc='30.25,120.17';let path,cb;
    s.requestQWeather=(p,c)=>{path=p;cb=c};s.fetchCityFromCoords(s.loc);
    assert.ok(path.includes('location=120.17,30.25'));
    s.loc='31.00,121.00';cb({location:[{adm2:'旧城市',name:'旧区'}]});assert.equal(s.city,'');
});
test('old city-only cache entries do not hide district resolution',()=>{
    const {s}=setup();vm.runInContext(functions,s);s.loc='30.25,120.17';s.cachedCities.set(s.loc,'旧城市');let called=false;
    s.requestQWeather=()=>{called=true};s.fetchCityFromCoords(s.loc);assert.equal(called,true);
});
test('late weather data from old coordinates cannot populate current forecast',()=>{
    const {s,requests}=setup();vm.runInContext(functions,s);s.loc='30.25,120.17';let accepted=false;
    s.requestQWeather('/weather/v1/current/30.25/120.17',()=>{accepted=true},'test');
    s.loc='31.00,121.00';requests[0][1]('{}');assert.equal(accepted,false);
});
test('district search scopes duplicate names to the requested parent city',()=>{
    const {s}=setup();vm.runInContext(functions,s);let path,callback,result;
    s.requestQWeather=(p,cb,label,failed,retry)=>{path=p;callback=cb;assert.equal(retry,false)};
    s.searchLocations(' 武汉 ',' 汉阳 ',value=>result=value);
    assert.ok(path.includes('location='+encodeURIComponent('汉阳')));
    assert.ok(path.includes('adm='+encodeURIComponent('武汉')));
    callback({location:[{id:'101200105',name:'汉阳',adm2:'武汉',lat:'30.55',lon:'114.22'}]});
    assert.equal(result.locations[0].name,'汉阳');assert.equal(s.GlobalConfig.services.weatherLocation,'');
});
test('search results with missing IDs or invalid coordinates cannot be selected',()=>{
    const {s}=setup();vm.runInContext(functions,s);let callback,result;
    s.requestQWeather=(p,cb)=>callback=cb;s.searchLocations('武汉','汉阳',value=>result=value);
    callback({location:[{name:'汉阳',lat:30,lon:114},{id:'bad',name:'错误',lat:100,lon:114}]});
    assert.equal(result.locations.length,0);assert.equal(s.selectLocation({id:'bad',lat:100,lon:0}),false);
});
test('selecting a candidate persists its exact location ID',()=>{
    const {s}=setup();assert.equal(s.selectLocation({id:'101200105',name:'汉阳',lat:30.55,lon:114.22}),true);
    assert.equal(s.GlobalConfig.services.weatherLocation,'101200105');
});
test('reselecting an unchanged district bypasses weather cooldown immediately',()=>{
    const {s}=setup();s.GlobalConfig.services.weatherLocation='101200105';s.resolvedCityName='101200105';s.loc='30.55,114.22';s.lastWeatherFetchAt=Date.now();
    s.selectLocation({id:'101200105',lat:30.55,lon:114.22});assert.equal(s.lastWeatherFetchAt,0);assert.equal(s.weatherFetches,1);
});
test('district search network failures do not schedule unrelated weather retries',()=>{
    const {s,requests}=setup();vm.runInContext(functions,s);let result;
    s.searchLocations('武汉','汉阳',r=>result=r);requests[0][2]('offline');
    assert.equal(result.error,'network');assert.equal(s.weatherRetryTimer.running,false);
});
test('changing district runs the real config handler and immediately requests all three forecasts',()=>{
    const {s,requests}=setup();vm.runInContext(functions,s);
    const handler=source.match(/        function onWeatherLocationChanged\(\): void \{([\s\S]*?)^        }/m)[1];
    vm.runInContext(`function configChanged(){${handler}}`,s);
    let location='',configured='';
    Object.defineProperty(s,'loc',{get:()=>location,set:value=>{if(location!==value){location=value;s.lastWeatherFetchAt=0;s.fetchWeatherData()}}});
    Object.defineProperty(s.GlobalConfig.services,'weatherLocation',{get:()=>configured,set:value=>{configured=value;s.configChanged()}});
    s.selectLocation({id:'101200105',name:'汉阳',lat:30.55,lon:114.22});
    assert.equal(requests.length,1);assert.ok(requests[0][0].includes('location=101200105'));
    requests[0][1](JSON.stringify({location:[{id:'101200105',name:'汉阳',adm2:'武汉',lat:'30.55',lon:'114.22'}]}));
    assert.equal(requests.length,4);assert.equal(s.city,'武汉 · 汉阳');
    assert.ok(requests.some(r=>r[0].includes('/weather/v1/current/')));
    assert.ok(requests.some(r=>r[0].includes('/weather/v1/hourly/')));
    assert.ok(requests.some(r=>r[0].includes('/weather/v1/daily/')));
});
test('explicit shell language wins over a C process locale for district names',()=>{
    const {s}=setup();s.GlobalConfig.general={language:'zh_CN'};s.Qt.locale=()=>({name:'C'});
    assert.equal(s.requestLanguage(),'zh');
});
