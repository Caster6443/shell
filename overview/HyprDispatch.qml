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

	// Dispatch with a legacy (non-Lua) and a Lua-aware variant; pick by session.
	function call(legacy: string, lua: string): void {
		Hyprland.dispatch(Hyprland.usingLua ? lua : legacy);
	}
}
