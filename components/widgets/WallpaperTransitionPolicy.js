.pragma library

// Discover compiled transitions rather than maintaining a second shader list.
function names(shaders) {
    return Object.keys(shaders).filter(function(name) {
        const value = shaders[name];
        return value && value.url !== undefined && value.duration !== undefined;
    });
}

function allowed(available, requested) {
    if (!requested || !requested.length) return available;
    const normalised = Array.from(requested).map(function(name) {
        return name ? name[0].toLowerCase() + name.slice(1) : "";
    });
    const valid = available.filter(function(name) { return normalised.indexOf(name) >= 0; });
    return valid.length ? valid : available;
}

function pick(configured, available, previous, sample, requested) {
    const key = configured ? configured[0].toLowerCase() + configured.slice(1) : "crossfade";
    if (key !== "random")
        return available.indexOf(key) >= 0 ? key : "crossfade";
    const pool = allowed(available, requested);
    const candidates = pool.filter(function(name) { return name !== previous; });
    if (!candidates.length)
        return pool.length ? pool[0] : "crossfade";
    return candidates[Math.floor(sample * candidates.length)];
}
