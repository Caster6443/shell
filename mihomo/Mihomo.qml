pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.mihomo

// 顶层实例：只负责注册 IPC（面板状态与数据都在 MihomoState 单例里）。
// 用法：caelestia shell mihomo <open|close|toggle|nodes|subs|select <节点名>|group <组名>>
Scope {
	id: root

	IpcHandler {
		target: "mihomo"

		function open(): void {
			MihomoState.openPanel();
		}

		function close(): void {
			MihomoState.closePanel();
		}

		function toggle(): void {
			MihomoState.togglePanel();
		}

		function nodes(): string {
			MihomoState.refresh();
			return JSON.stringify({
				group: MihomoState.group,
				groups: MihomoState.groups.map(g => g.name),
				nodes: MihomoState.nodes.map(n => `${n.delay >= 0 ? n.delay + "ms" : "超时"} ${n.name}`),
				now: MihomoState.groups.find(g => g.name === MihomoState.group)?.now ?? ""
			});
		}

		function test(): void {
			MihomoState.testDelay();
		}

		function subs(): string {
			return JSON.stringify({
				subs: MihomoState.subs.map(s => `${s.current ? "*" : ""}${s.name}(${s.count})`)
			});
		}

		function select(name: string): void {
			MihomoState.selectNode(name);
		}

		function group(name: string): void {
			MihomoState.setGroup(name);
		}

		function switchSub(id: string): void {
			MihomoState.switchSub(id);
		}
	}
}
