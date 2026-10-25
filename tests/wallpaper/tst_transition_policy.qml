import QtQuick
import QtTest
import Caelestia.Shaders
import "../../components/widgets/WallpaperTransitionPolicy.js" as Policy

Item {
    TestCase {
        name: "WallpaperTransitionPolicy"
        when: windowShown
        readonly property var available: Policy.names(Shaders)
        function test_discovers_compiled_shaders() {
            compare(available.length, 27);
            for (const name of available) verify(!!Shaders[name].url);
        }
        function test_fixed_effects_remain_fixed() {
            for (const name of available) {
                const configured = name[0].toUpperCase() + name.slice(1);
                compare(Policy.pick(configured, available, name, 0.8), name);
            }
            compare(Policy.pick("RandomSquares", available, "crossfade", 0.3), "randomSquares");
        }
        function test_random_never_repeats_previous() {
            let previous = "crossfade";
            const seen = {};
            for (let i = 0; i < 2700; ++i) {
                const next = Policy.pick("Random", available, previous, ((i * 7919) % 10000) / 10000);
                verify(available.indexOf(next) >= 0);
                verify(next !== previous);
                seen[next] = true;
                previous = next;
            }
            compare(Object.keys(seen).length, available.length);
        }
        function test_selected_random_range() {
            for (let i = 0; i < 100; ++i) {
                compare(Policy.pick("Random", available, "iris", i / 100, ["Iris", "Smoke", "Missing"]), "smoke");
                compare(Policy.pick("Random", available, "smoke", i / 100, ["iris", "smoke"]), "iris");
            }
            compare(Policy.pick("Random", available, "iris", 0.5, ["iris"]), "iris");
            compare(Policy.allowed(available, ["Missing"]).length, 27);
            compare(Policy.allowed(available, []).length, 27);
            compare(Policy.pick("Crossfade", available, "iris", 0, ["smoke"]), "crossfade");
        }
        function test_boundary_and_fallback() {
            compare(Policy.pick("Random", ["a", "b", "c"], "b", 0), "a");
            compare(Policy.pick("Random", ["a", "b", "c"], "b", 0.99999), "c");
            compare(Policy.pick("Random", [], "a", 0.5), "crossfade");
            compare(Policy.pick("Random", ["a"], "a", 0.5), "a");
            compare(Policy.pick("Missing", available, "iris", 0), "crossfade");
        }
    }
}
