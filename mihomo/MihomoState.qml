pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// 无头 mihomo（TUN）面板的数据层：走本机 RESTful API（127.0.0.1:9090）+ 本地订阅元数据。
// 密钥不写死在 QML 里，从 ~/.config/mihomo/api.json 读（由部署/同步脚本生成，600 权限）。
// 订阅切换交给 ~/.local/bin/mihomo-sub（把选中的 provider 文件同步成 main.yaml 后重启服务）。
Singleton {
	id: root

	readonly property string home: Quickshell.env("HOME") || "/home/caster"
	readonly property string apiHost: "127.0.0.1:9090"
	readonly property string groupTypes: "Selector,URLTest,Fallback,LoadBalance"

	property string secret: ""
	property bool ready: false
	property bool busy: false
	property bool testing: false
	property string message: ""

	// 面板状态：由 VPN 按钮右键打开
	property bool panelOpen: false
	property string tab: "nodes" // nodes | subs
	property string group: "Proxy"
	property var groups: [] // [{ name, type, now, count }]
	property var nodes: [] // [{ name, delay, active }]
	// 测速结果缓存：mihomo 的 /proxies history 更新有延迟（组测速后不一定立刻写回），
	// 用它兜底，避免刷新一次就把刚测出来的数字抹成“超时”。
	property var delayCache: ({})
	property var subs: [] // [{ id, name, count, current }]
	property double lastUpdate: 0

	function apiUrl(path: string): string {
		return `http://${root.apiHost}${path}`;
	}

	function authArgs(): var {
		return ["-H", `Authorization: Bearer ${root.secret}`];
	}

	function openPanel(): void {
		root.panelOpen = true;
		root.refresh();
	}

	function closePanel(): void {
		root.panelOpen = false;
	}

	function togglePanel(): void {
		root.panelOpen ? root.closePanel() : root.openPanel();
	}

	function setTab(t: string): void {
		root.tab = t;
		if (t === "nodes")
			root.refresh();
	}

	function setGroup(name: string): void {
		if (name === "" || name === root.group)
			return;
		root.group = name;
		root.applyGroupView();
	}

	function refresh(): void {
		if (root.secret.length === 0) {
			apiFile.reload();
			return;
		}
		if (proxiesProc.running)
			return;
		root.busy = true;
		proxiesProc.command = ["curl", "-s", "-m", "4", ...root.authArgs(), root.apiUrl("/proxies")];
		proxiesProc.running = true;
		subsFile.reload();
	}

	// 把 /proxies 的返回折成「策略组 + 当前组的节点」两份列表
	function applyProxies(text: string): void {
		root.busy = false;
		let data;
		try {
			data = JSON.parse(text).proxies;
		} catch (e) {
			root.message = "连不上 mihomo（服务没起来？）";
			return;
		}
		if (!data) {
			root.message = "mihomo API 返回异常";
			return;
		}
		const types = root.groupTypes.split(",");
		const gs = [];
		for (const name in data) {
			const v = data[name];
			if (name === "GLOBAL" || !types.includes(v.type))
				continue;
			gs.push({
				name: name,
				type: v.type,
				now: v.now ?? "",
				count: (v.all ?? []).length
			});
		}
		root.groups = gs;
		if (!gs.some(g => g.name === root.group))
			root.group = gs.length > 0 ? gs[0].name : "";
		root.proxies = data;
		root.applyGroupView();
		root.lastUpdate = Date.now();
		root.ready = true;
	}

	property var proxies: ({})

	function applyGroupView(): void {
		const g = root.proxies[root.group];
		if (!g) {
			root.nodes = [];
			return;
		}
		const out = [];
		for (const n of (g.all ?? [])) {
			const p = root.proxies[n];
			let delay = -1;
			if (p && p.history && p.history.length > 0) {
				const h = p.history[p.history.length - 1];
				delay = (h && typeof h.delay === "number") ? h.delay : -1;
			}
			if (delay < 0 && typeof root.delayCache[n] === "number")
				delay = root.delayCache[n];
			out.push({
				name: n,
				delay: delay,
				active: g.now === n
			});
		}
		root.nodes = out;
	}

	function selectNode(name: string): void {
		if (name === "" || selectProc.running)
			return;
		// 乐观更新，点完立刻有反馈
		root.nodes = root.nodes.map(n => ({
				name: n.name,
				delay: n.delay,
				active: n.name === name
			}));
		root.groups = root.groups.map(g => g.name === root.group ? ({
					name: g.name,
					type: g.type,
					now: name,
					count: g.count
				}) : g);
		root.message = `已切到 ${name}`;
		selectProc.command = [
			"curl", "-s", "-m", "5", "-X", "PUT",
			...root.authArgs(),
			"-H", "Content-Type: application/json",
			"-d", JSON.stringify({
				name: name
			}),
			root.apiUrl(`/proxies/${encodeURIComponent(root.group)}`)
		];
		selectProc.running = true;
	}

	// 测速：让 mihomo 对所有节点跑一次延迟测试（结果会进 /proxies 的 history）
	function testDelay(): void {
		if (root.group === "" || delayProc.running)
			return;
		root.message = "测速中…";
		root.testing = true;
		delayProc.command = [
			"curl", "-s", "-m", "20",
			...root.authArgs(),
			root.apiUrl(`/group/${encodeURIComponent(root.group)}/delay?url=https://cp.cloudflare.com&timeout=3000`)
		];
		delayProc.running = true;
	}

	// 组测速接口返回的是「节点名 → 延迟(ms)」整张表，直接铺到列表上，
	// 这样每个节点都有数字（超时/失败为 -1）。
	function applyDelays(text: string): void {
		root.testing = false;
		let map;
		try {
			map = JSON.parse(text);
		} catch (e) {
			root.message = "测速失败（服务没起来？）";
			return;
		}
		if (!map || typeof map !== "object") {
			root.message = "测速失败";
			return;
		}
		root.nodes = root.nodes.map(n => ({
				name: n.name,
				delay: typeof map[n.name] === "number" ? map[n.name] : -1,
				active: n.active
			}));
		const cache = Object.assign({}, root.delayCache);
		for (const k in map)
			if (typeof map[k] === "number")
				cache[k] = map[k];
		root.delayCache = cache;
		root.message = "测速完成";
		refreshTimer.restart();
	}

	function switchSub(id: string): void {
		if (id === "" || subProc.running)
			return;
		root.message = "切换订阅中…";
		subProc.command = [`${root.home}/.local/bin/mihomo-sub`, id];
		subProc.running = true;
	}

	function syncSubs(): void {
		if (subProc.running)
			return;
		root.message = "从 mihomo-party 缓存重新导入…";
		subProc.command = [`${root.home}/.local/bin/mihomo-sub`, "--sync"];
		subProc.running = true;
	}

	FileView {
		id: apiFile

		path: `${root.home}/.config/mihomo/api.json`
		watchChanges: true

		onFileChanged: reload()
		onLoaded: {
			try {
				root.secret = JSON.parse(text()).secret ?? "";
			} catch (e) {
				root.secret = "";
			}
			// 密钥一到就拉一次数据（面板还没开也没关系，打开时就有现成的）
			if (root.secret.length > 0)
				root.refresh();
		}
	}

	FileView {
		id: subsFile

		path: `${root.home}/.config/mihomo/subscriptions.json`
		watchChanges: true

		onFileChanged: reload()
		onLoaded: {
			try {
				const d = JSON.parse(text());
				const cur = d.current ?? "";
				root.subs = (d.items ?? []).map(i => ({
						id: i.id,
						name: i.name,
						count: i.count,
						current: i.id === cur
					}));
			} catch (e) {
				root.subs = [];
			}
		}
	}

	Process {
		id: proxiesProc

		stdout: StdioCollector {
			onStreamFinished: root.applyProxies(text)
		}
	}

	Process {
		id: selectProc

		onExited: code => {
			if (code !== 0) {
				root.message = "切换节点失败";
				refreshTimer.restart();
			}
		}
	}

	Process {
		id: delayProc

		stdout: StdioCollector {
			onStreamFinished: root.applyDelays(text)
		}
	}

	Process {
		id: subProc

		onExited: code => {
			root.message = code === 0 ? "订阅已切换，正在重连…" : "切换订阅失败";
			// 服务重启后 API 需要一两秒才回来
			subsFile.reload();
			subRefreshTimer.restart();
		}
	}

	Timer {
		id: refreshTimer

		interval: 600
		repeat: false
		onTriggered: root.refresh()
	}

	Timer {
		id: subRefreshTimer

		interval: 2500
		repeat: false
		onTriggered: root.refresh()
	}

	Component.onCompleted: {
		apiFile.reload();
		subsFile.reload();
	}
}
