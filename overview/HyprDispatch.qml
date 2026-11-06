pragma Singleton

import Quickshell
import Quickshell.Hyprland

Singleton {
	// Normalize a hyprctl address ("0x…" or bare hex) to canonical 0x form.
	function addressArg(address: string): string {
		const a = String(address || "");
		if (a.startsWith("0x") || a.startsWith("0X"))
			return a;
		return "0x" + a;
	}

    // Scrolling fullscreen can occlude even the focused floating Console.
    // Pin it for this mapped lifetime; hiding destroys the native toplevel,
    // so the next opening returns to the ordinary unpinned window rules.
    function callKeepingConsoleFocus(legacy: string, lua: string): void {
        if (!Hyprland.usingLua) {
            HyprDispatch.call(legacy, lua);
            return;
        }
        const code = `local owner = hl.get_active_window()
if owner and owner.title == "caelestia-console" then
    local selector = "address:" .. owner.address
    local wasPinned = owner.pinned
    if not wasPinned then hl.dispatch(hl.dsp.window.pin({ window = selector, action = "set" })) end
    hl.dispatch(${lua})
    hl.dispatch(hl.dsp.focus({ window = selector }))
    hl.dispatch(hl.dsp.window.alter_zorder({ window = selector, mode = "top" }))
end`;
        Quickshell.execDetached(["hyprctl", "eval", code]);
    }

	// Dispatch with a legacy (non-Lua) and a Lua-aware variant; pick by session.
	function call(legacy: string, lua: string): void {
		Hyprland.dispatch(Hyprland.usingLua ? lua : legacy);
	}
}
