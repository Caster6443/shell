pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// AI 对话（OpenAI 兼容 /chat/completions，SSE 流式）+ **工具调用（agent）**。
//
// 工具（移植自 end-4/dots-hyprland 的 Ai 服务，按本机环境改写）：
//   - run_shell_command：跑 bash 命令，**默认需要用户在面板里点"运行"**（和 end-4 的 functionPending 一致）
//   - get_shell_config / set_shell_config：读写 caelestia 的 ~/.config/caelestia/shell.json（CA 会热重载）
//
// 设置存 ${XDG_CONFIG_HOME}/caelestia/aichat.json（含 API key，保存后 chmod 600）；
// key 也可用环境变量 AICHAT_API_KEY。
// 输入法自动切换（autoSwitchIme / desiredIme）**默认关闭**（2026-09-10 用户明确要求）：
// 面板不主动动你的输入法，保持 fcitx5 给它初始化的状态（本机新窗口是 keyboard-us）。
// 背景：fcitx5 给"新建输入上下文"用输入法组里的第一个 IM，面板每次重开都会回到 keyboard-us；
// 曾经的做法是在面板取焦后 `fcitx5-remote -s rime` 补一刀，但用户不需要，故关掉。
// 想用回来：aichat.json 里设 "autoSwitchIme": true，重启 shell 生效。
Singleton {
	id: root

	readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`
	readonly property string configDir: `${Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`}/caelestia`
	readonly property string settingsPath: `${root.configDir}/aichat.json`
	readonly property string shellConfigPath: `${root.configDir}/shell.json`
	readonly property string envKey: Quickshell.env("AICHAT_API_KEY") ?? ""

	property string endpoint: "https://api.deepseek.com/v1/chat/completions"
	property string model: "deepseek-chat"
	property string apiKey: ""
	property string systemPrompt: "你是运行在用户 Linux 桌面（Hyprland + caelestia）上的助手。回答简洁、直接、用中文。需要用户桌面信息或执行命令时，用提供的工具。"
	property bool settingsOpen: false
	property int maxHistory: 24
	// 面板打开后是否自动把输入法切到 desiredIme。**默认关**（2026-09-10 用户要求）：
	// 面板不去动用户的输入法状态；需要时在 aichat.json 里设 true。
	property bool autoSwitchIme: false
	property string desiredIme: "rime"
	// 面板字号缩放（1.0 = 原始设计；面板里的像素字号都乘这个值）
	property real fontScale: 1.2

	// ---- 工具（agent）----
	property bool toolsEnabled: true
	property int maxToolRounds: 6
	property int toolRound: 0
	property var pendingToolCalls: []
	property var pendingToolCall: null
	property string pendingCommandOutput: ""

	// UI 消息：[{ role, content, error, kind, name, detail, pending, running, output }]
	property var messages: []
	// 发给模型的历史（OpenAI 格式，含 tool_calls / role:"tool"）
	property var apiHistory: []
	property bool streaming: false
	property string lastError: ""
	property string streamRaw: ""
	property string streamText: ""
	property var streamToolCalls: ({})
	property bool stoppedFlag: false
	property int lastHttpStatus: 0
	property string savedHint: ""

	readonly property string effectiveKey: root.apiKey.trim() !== "" ? root.apiKey.trim() : root.envKey

	readonly property var toolDefinitions: [
		{
			"type": "function",
			"function": {
				"name": "run_shell_command",
				"description": "Run a shell command in bash and return its output. Only for quick commands that need no interaction (for interactive ones, ask the user to run it manually). The user must approve it first.",
				"parameters": {
					"type": "object",
					"properties": {
						"command": {
							"type": "string",
							"description": "The bash command to run"
						}
					},
					"required": ["command"]
				}
			}
		},
		{
			"type": "function",
			"function": {
				"name": "get_shell_config",
				"description": "Get the desktop shell config file contents (a JSON string).",
				"parameters": {
					"type": "object",
					"properties": {}
				}
			}
		},
		{
			"type": "function",
			"function": {
				"name": "set_shell_config",
				"description": "Set a dotted key in the desktop shell config file. Call get_shell_config first and never guess keys.",
				"parameters": {
					"type": "object",
					"properties": {
						"key": {
							"type": "string",
							"description": "Dotted key, e.g. bar.borderless"
						},
						"value": {
							"type": "string",
							"description": "New value, e.g. true"
						}
					},
					"required": ["key", "value"]
				}
			}
		}
	]

	// 容错：用户可能只填域名或 /v1，这里给出候选请求地址（原样优先，失败再试常见变体）
	readonly property var endpointCandidates: {
		const url = root.endpoint.trim().replace(/\/+$/, "");
		if (url === "")
			return [];
		const out = [url];
		const push = u => {
			if (u !== "" && !out.includes(u))
				out.push(u);
		};
		const m = url.match(/^(https?:\/\/[^\/]+)(\/.*)?$/);
		if (m) {
			const host = m[1];
			const path = m[2] ?? "";
			if (!path.endsWith("/chat/completions")) {
				push(`${host}${path}/chat/completions`);
				push(`${host}${path}/v1/chat/completions`);
				push(`${host}/chat/completions`);
				push(`${host}/v1/chat/completions`);
			}
		}
		return out;
	}
	property int attemptIndex: 0
	readonly property string resolvedEndpoint: {
		const list = root.endpointCandidates;
		return list.length === 0 ? "" : list[Math.min(root.attemptIndex, list.length - 1)];
	}

	function shq(s: string): string {
		return "'" + String(s).replace(/'/g, "'\\''") + "'";
	}

	// ---------------- 设置 ----------------
	function load(): void {
		settingsFile.reload();
	}

	function save(): void {
		settingsFile.setText(JSON.stringify({
			endpoint: root.endpoint,
			model: root.model,
			apiKey: root.apiKey,
			systemPrompt: root.systemPrompt,
			fontScale: root.fontScale,
			autoSwitchIme: root.autoSwitchIme,
			desiredIme: root.desiredIme
		}, null, "\t"));
		Quickshell.execDetached(["bash", "-c", `mkdir -p ${root.shq(root.configDir)} && chmod 600 ${root.shq(root.settingsPath)} 2>/dev/null || true`]);
		root.savedHint = `已保存 ✓（实际请求 ${root.resolvedEndpoint}）`;
		console.info(`[aichat] 设置已保存：endpoint=${root.resolvedEndpoint} model=${root.model} key=${root.effectiveKey === "" ? "(空)" : "(已填)"}`);
		savedHintTimer.restart();
	}

	Timer {
		id: savedHintTimer

		interval: 4000
		onTriggered: root.savedHint = ""
	}

	// ---------------- 输入法 ----------------
	function ensureIme(): void {
		if (!root.autoSwitchIme || root.desiredIme === "")
			return;
		imeQueryProc.running = true;
	}

	Process {
		id: imeQueryProc

		command: ["fcitx5-remote", "-n"]
		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				const current = String(this.text).trim();
				if (current === "" || current === root.desiredIme)
					return;
				console.info(`[aichat] 输入法当前为 ${current}，切到 ${root.desiredIme}`);
				Quickshell.execDetached(["fcitx5-remote", "-s", root.desiredIme]);
			}
		}
	}

	// ---------------- 消息 ----------------
	function appendMessage(msg: var): void {
		root.messages = root.messages.concat([msg]);
	}

	function updateLast(patch: var): void {
		const arr = root.messages.slice();
		if (arr.length === 0)
			return;
		arr[arr.length - 1] = Object.assign({}, arr[arr.length - 1], patch);
		root.messages = arr;
	}

	function appendToLast(chunk: string, isError: bool): void {
		const arr = root.messages.slice();
		if (arr.length === 0)
			return;
		const last = Object.assign({}, arr[arr.length - 1]);
		last.content = String(last.content) + chunk;
		if (isError)
			last.error = true;
		arr[arr.length - 1] = last;
		root.messages = arr;
	}

	function clear(): void {
		if (root.streaming || root.pendingToolCall)
			root.stop();
		root.messages = [];
		root.apiHistory = [];
		root.toolRound = 0;
	}

	// ---------------- 会话（聊天记录）管理 ----------------
	// 移植自 end-4/dots-hyprland 的 services/Ai.qml（saveChat / loadChat / savedChats +
	// 每轮回复后自动存 lastSession 的做法），差异：
	//   - 存储目录换成 caelestia 的状态目录（end-4 用 state/user/ai/chats）；
	//   - 除了界面消息 messages，还把 apiHistory（含 assistant 的 tool_calls / role:"tool"）
	//     一起存盘，载入后发给模型的上下文与界面完全对得上；
	//   - 自动存档写回"当前会话"（默认 last-session），载入过的会话继续聊会更新它自己。
	readonly property string chatsDir: `${root.stateDir}/caelestia/aichat/chats`
	property bool chatsOpen: false
	property var savedChats: [] // [{ name, ts }]，按文件修改时间倒序
	property string currentChat: "last-session"
	property string chatHint: ""

	function chatPath(name: string): string {
		return `${root.chatsDir}/${name}.json`;
	}

	function refreshChats(): void {
		Quickshell.execDetached(["mkdir", "-p", root.chatsDir]);
		chatListProc.running = true;
	}

	function chatPayload(): var {
		return {
			version: 1,
			name: root.currentChat,
			savedAt: Date.now(),
			model: root.model,
			messages: root.messages,
			apiHistory: root.apiHistory
		};
	}

	// 会话名会变成文件名：去掉路径分隔符，避免写出目录
	function cleanChatName(name: string): string {
		return String(name ?? "").trim().replace(/[\/\\]/g, "-");
	}

	function saveChatTo(name: string, silent: bool): void {
		const clean = root.cleanChatName(name);
		if (clean === "")
			return;
		chatWriter.chatName = clean;
		chatWriter.setText(JSON.stringify(root.chatPayload(), null, "\t"));
		root.currentChat = clean;
		if (!silent) {
			root.chatHint = `已保存「${clean}」`;
			chatHintTimer.restart();
		}
		root.refreshChats();
	}

	function autoSaveSession(): void {
		root.saveChatTo(root.currentChat, true);
	}

	function loadChatFrom(name: string, silent: bool): void {
		const clean = root.cleanChatName(name);
		if (clean === "")
			return;
		chatLoader.chatName = clean;
		chatLoader.silent = silent === true;
		chatLoader.running = true;
	}

	function applyLoadedChat(raw: string, name: string): void {
		const data = JSON.parse(raw);
		root.messages = Array.isArray(data.messages) ? data.messages : [];
		root.apiHistory = Array.isArray(data.apiHistory) ? data.apiHistory : [];
		root.toolRound = 0;
		root.pendingToolCall = null;
		root.pendingToolCalls = [];
		root.streaming = false;
		root.currentChat = name;
		root.chatHint = `已载入「${name}」（${root.messages.length} 条）`;
		chatHintTimer.restart();
	}

	function deleteChat(name: string): void {
		const clean = root.cleanChatName(name);
		if (clean === "")
			return;
		chatDeleteProc.chatName = clean;
		chatDeleteProc.running = true;
	}

	function newChat(): void {
		root.clear();
		root.currentChat = "last-session";
		root.autoSaveSession();
		root.chatHint = "已新建会话（未命名的对话存在 last-session）";
		chatHintTimer.restart();
	}

	function restoreLastSession(): void {
		if (root.messages.length > 0)
			return;
		root.loadChatFrom("last-session", true);
	}

	Timer {
		id: chatHintTimer

		interval: 4000
		onTriggered: root.chatHint = ""
	}

	// 保存：写 JSON 到 chatsDir/<name>.json
	FileView {
		id: chatWriter

		property string chatName: ""

		path: chatWriter.chatName === "" ? "" : root.chatPath(chatWriter.chatName)
		blockLoading: true
		printErrors: false
	}

	// 列表：find -printf 拿到 mtime，按时间倒序
	Process {
		id: chatListProc

		running: false
		command: ["bash", "-c", `find "${root.chatsDir}" -maxdepth 1 -name '*.json' -printf '%T@\\t%f\\n' 2>/dev/null | sort -rn`]

		stdout: StdioCollector {
			onStreamFinished: {
				const out = String(this.text ?? "").trim();
				root.savedChats = out === "" ? [] : out.split("\n").map(line => {
					const tab = line.indexOf("\t");
					const ts = Number(line.slice(0, tab));
					return {
						name: line.slice(tab + 1).replace(/\.json$/, ""),
						ts: Number.isFinite(ts) ? ts : 0
					};
				});
			}
		}
	}

	// 载入：用 cat 读（FileView 的动态 path 读取是异步的，这里读同步结果更省心）
	Process {
		id: chatLoader

		property string chatName: ""
		property bool silent: false
		property string raw: ""

		running: false
		command: chatLoader.chatName === "" ? [] : ["cat", root.chatPath(chatLoader.chatName)]

		stdout: StdioCollector {
			onStreamFinished: chatLoader.raw = String(this.text ?? "")
		}

		onExited: (code, status) => {
			const raw = chatLoader.raw;
			chatLoader.raw = "";
			if (code === 0 && raw.trim() !== "") {
				try {
					root.applyLoadedChat(raw, chatLoader.chatName);
				} catch (e) {
					root.chatHint = `载入「${chatLoader.chatName}」失败：${e}`;
					chatHintTimer.restart();
				}
			} else if (!chatLoader.silent) {
				root.chatHint = `没有找到会话「${chatLoader.chatName}」`;
				chatHintTimer.restart();
			}
		}
	}

	Process {
		id: chatDeleteProc

		property string chatName: ""

		running: false
		command: chatDeleteProc.chatName === "" ? [] : ["rm", "-f", root.chatPath(chatDeleteProc.chatName)]

		onExited: (code, status) => {
			root.chatHint = `已删除「${chatDeleteProc.chatName}」`;
			chatHintTimer.restart();
			root.refreshChats();
		}
	}

	Component.onCompleted: {
		root.refreshChats();
		root.restoreLastSession();
	}

	// ---------------- 请求 ----------------
	function send(text: string): void {
		const content = String(text ?? "").trim();
		if (content === "" || root.streaming || root.pendingToolCall)
			return;
		root.lastError = "";
		root.attemptIndex = 0;
		root.lastHttpStatus = 0;
		root.toolRound = 0;
		root.appendMessage({ role: "user", content: content, error: false });
		root.apiHistory = root.apiHistory.concat([{ role: "user", content: content }]);
		if (root.effectiveKey === "") {
			root.lastError = `还没填 API key：点右上角 ⚙ 填一次（存在 ${root.settingsPath}），或设置环境变量 AICHAT_API_KEY。`;
			root.appendMessage({ role: "assistant", content: root.lastError, error: true });
			root.lastError = "";
			return;
		}
		root.startRequest();
	}

	function apiMessages(): var {
		const out = [{ role: "system", content: root.systemPrompt }];
		for (const m of root.apiHistory.slice(-root.maxHistory))
			out.push(m);
		return out;
	}

	function startRequest(): void {
		root.streaming = true;
		root.stoppedFlag = false;
		root.streamRaw = "";
		root.streamText = "";
		root.streamToolCalls = {};
		root.lastHttpStatus = 0;
		// 本轮先占一个空的助手气泡，流式内容往里写
		root.appendMessage({ role: "assistant", content: "", error: false });
		const payload = {
			model: root.model,
			stream: true,
			messages: root.apiMessages()
		};
		if (root.toolsEnabled) {
			payload.tools = root.toolDefinitions;
			payload.tool_choice = "auto";
		}
		chatProc.command = [
			"curl", "-sN", "--max-time", "300", "-X", "POST", root.resolvedEndpoint,
			"-w", "\n[aichat-http:%{http_code}]",
			"-H", "Content-Type: application/json",
			"-H", `Authorization: Bearer ${root.effectiveKey}`,
			"-d", JSON.stringify(payload)
		];
		console.info(`[aichat] 请求 endpoint=${root.resolvedEndpoint} model=${root.model} 消息=${payload.messages.length} 工具=${root.toolsEnabled ? root.toolDefinitions.length : 0} 轮次=${root.toolRound}`);
		chatProc.running = true;
	}

	function onStreamLine(line: string): void {
		const text = String(line);
		const httpTag = /\[aichat-http:(\d+)\]/.exec(text);
		if (httpTag) {
			root.lastHttpStatus = parseInt(httpTag[1]);
			return;
		}
		root.streamRaw += text + "\n";
		const trimmed = text.trim();
		if (trimmed === "" || !trimmed.startsWith("data:"))
			return;
		const data = trimmed.slice(5).trim();
		if (data === "[DONE]")
			return;
		let obj = null;
		try {
			obj = JSON.parse(data);
		} catch (e) {
			return;
		}
		const delta = obj.choices?.[0]?.delta;
		if (!delta)
			return;
		if (typeof delta.content === "string" && delta.content !== "") {
			root.streamText += delta.content;
			root.appendToLast(delta.content, false);
		}
		for (const tc of delta.tool_calls ?? []) {
			const idx = tc.index ?? 0;
			const acc = root.streamToolCalls[idx] ?? { id: "", name: "", args: "" };
			if (tc.id)
				acc.id = tc.id;
			if (tc.function?.name)
				acc.name = tc.function.name;
			if (tc.function?.arguments)
				acc.args += tc.function.arguments;
			root.streamToolCalls[idx] = acc;
		}
	}

	// 一次请求结束：有工具调用就处理，没有就收尾
	function endRequest(): void {
		const produced = root.streamText.trim() !== "" || Object.keys(root.streamToolCalls).length > 0;

		if (!produced && root.attemptIndex + 1 < root.endpointCandidates.length) {
			root.attemptIndex++;
			// 这次尝试没产出任何内容：扔掉本轮的空占位气泡，否则重试成功后界面上会留下一个空泡
			const last = root.messages[root.messages.length - 1];
			if (last && last.role === "assistant" && String(last.content) === "")
				root.messages = root.messages.slice(0, -1);
			console.info(`[aichat] 该地址没拿到内容（HTTP ${root.lastHttpStatus}），改试 ${root.resolvedEndpoint}`);
			root.startRequest();
			return;
		}

		if (!produced) {
			const raw = root.streamRaw.trim();
			const statusHint = root.lastHttpStatus > 0 ? `HTTP ${root.lastHttpStatus}。` : "";
			const hint = raw === ""
				? `${statusHint}没有收到任何响应：检查接口地址 / 模型名 / API key / 网络。\n试过的地址：\n${root.endpointCandidates.join("\n")}`
				: `${statusHint}没有解析到内容，原始响应：\n${raw.slice(0, 800)}`;
			console.warn(`[aichat] 请求失败 endpoint=${root.resolvedEndpoint} http=${root.lastHttpStatus} raw=${raw === "" ? "(空)" : raw.slice(0, 200)}`);
			root.updateLast({ content: hint, error: true });
			root.streaming = false;
			root.autoSaveSession();
			return;
		}

		const calls = Object.keys(root.streamToolCalls).sort((a, b) => a - b).map(k => root.streamToolCalls[k]);
		if (calls.length === 0) {
			root.apiHistory = root.apiHistory.concat([{ role: "assistant", content: root.streamText }]);
			root.toolRound = 0;
			root.streaming = false;
			root.autoSaveSession();
			return;
		}

		// 记录助手这一轮的 tool_calls，并按顺序执行
		if (root.streamText.trim() === "" && root.messages.length > 0)
			root.messages = root.messages.slice(0, -1); // 这一轮只有工具调用：去掉空的占位气泡
		root.apiHistory = root.apiHistory.concat([{
			role: "assistant",
			content: root.streamText !== "" ? root.streamText : null,
			tool_calls: calls.map(c => ({
				id: c.id,
				type: "function",
				function: { name: c.name, arguments: c.args === "" ? "{}" : c.args }
			}))
		}]);
		root.pendingToolCalls = calls;
		root.streaming = false;
		root.runNextToolCall();
	}

	function runNextToolCall(): void {
		if (root.pendingToolCalls.length === 0) {
			root.toolRound++;
			if (root.toolRound > root.maxToolRounds) {
				root.appendMessage({ role: "assistant", content: `工具调用超过 ${root.maxToolRounds} 轮，先停下。`, error: true });
				root.toolRound = 0;
				return;
			}
			root.startRequest();
			return;
		}
		const call = root.pendingToolCalls[0];
		root.pendingToolCalls = root.pendingToolCalls.slice(1);
		let args = {};
		try {
			args = JSON.parse(call.args === "" ? "{}" : call.args);
		} catch (e) {
			root.finishToolCall(call, `参数不是合法 JSON：${call.args}`);
			return;
		}
		if (call.name === "run_shell_command") {
			if (!args.command) {
				root.finishToolCall(call, "缺少 command 参数");
				return;
			}
			// 需要用户批准：把这条挂到最后一个气泡上，等 approve/reject
			root.pendingToolCall = call;
			root.appendMessage({
				role: "assistant",
				content: "",
				kind: "tool",
				name: call.name,
				detail: args.command,
				pending: true,
				running: false,
				output: "",
				error: false
			});
			return;
		}
		if (call.name === "get_shell_config") {
			root.readConfig(call);
			return;
		}
		if (call.name === "set_shell_config") {
			if (!args.key) {
				root.finishToolCall(call, "缺少 key 参数");
				return;
			}
			root.writeConfig(call, String(args.key), String(args.value ?? ""));
			return;
		}
		root.finishToolCall(call, `未知工具：${call.name}`);
	}

	// 工具结果回灌 + 继续下一轮
	function finishToolCall(call: var, output: string): void {
		root.apiHistory = root.apiHistory.concat([{
			role: "tool",
			tool_call_id: call.id,
			content: String(output).slice(0, 4000)
		}]);
		root.runNextToolCall();
	}

	function approvePending(): void {
		const call = root.pendingToolCall;
		if (!call)
			return;
		root.pendingToolCall = null;
		let args = {};
		try {
			args = JSON.parse(call.args === "" ? "{}" : call.args);
		} catch (e) {
			args = {};
		}
		root.pendingCommandOutput = "";
		root.updateLast({ pending: false, running: true });
		console.info(`[aichat] 用户批准执行：${args.command}`);
		shellProc.command = ["bash", "-c", String(args.command ?? "")];
		shellProc.pendingCall = call;
		shellProc.running = true;
	}

	function rejectPending(): void {
		const call = root.pendingToolCall;
		if (!call)
			return;
		root.pendingToolCall = null;
		root.updateLast({ pending: false, running: false, output: "（用户拒绝执行）", error: true });
		console.info("[aichat] 用户拒绝执行命令");
		root.finishToolCall(call, "用户拒绝执行该命令。请改用其它方式或直接告诉用户手动执行。");
	}

	Process {
		id: shellProc

		property var pendingCall: null

		running: false

		stdout: SplitParser {
			onRead: line => {
				root.pendingCommandOutput += line + "\n";
				root.updateLast({ output: root.pendingCommandOutput });
			}
		}

		onExited: (code, status) => {
			const call = shellProc.pendingCall;
			shellProc.pendingCall = null;
			root.updateLast({ running: false });
			const out = `${root.pendingCommandOutput}\n[[ 退出码 ${code} (${status}) ]]`;
			if (call)
				root.finishToolCall(call, out);
		}
	}

	// ---------------- 配置文件读写 ----------------
	function readConfig(call: var): void {
		root.appendMessage({ role: "assistant", content: "", kind: "tool", name: call.name, detail: root.shellConfigPath, pending: false, running: true, output: "", error: false });
		cfgReadProc.pendingCall = call;
		cfgReadProc.command = ["cat", root.shellConfigPath];
		cfgReadProc.running = true;
	}

	Process {
		id: cfgReadProc

		property var pendingCall: null

		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				const call = cfgReadProc.pendingCall;
				cfgReadProc.pendingCall = null;
				root.updateLast({ running: false, output: "（已读取配置）" });
				if (call)
					root.finishToolCall(call, String(this.text).slice(0, 6000));
			}
		}
	}

	function writeConfig(call: var, key: string, value: string): void {
		root.appendMessage({ role: "assistant", content: "", kind: "tool", name: call.name, detail: `${key} = ${value}`, pending: false, running: true, output: "", error: false });
		cfgWriteProc.pendingCall = call;
		cfgWriteProc.command = [
			"python3", "-c",
			"import json,sys\np,k,v=sys.argv[1],sys.argv[2],sys.argv[3]\nwith open(p) as f: d=json.load(f)\ntry: val=json.loads(v)\nexcept Exception: val=v\ncur=d\nparts=k.split('.')\nfor part in parts[:-1]:\n    if part not in cur or not isinstance(cur[part],dict): cur[part]={}\n    cur=cur[part]\ncur[parts[-1]]=val\nwith open(p,'w') as f: json.dump(d,f,indent=4,ensure_ascii=False)\nprint('ok: '+k)",
			root.shellConfigPath, key, value
		];
		cfgWriteProc.running = true;
	}

	Process {
		id: cfgWriteProc

		property var pendingCall: null

		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				const call = cfgWriteProc.pendingCall;
				cfgWriteProc.pendingCall = null;
				const out = String(this.text).trim();
				root.updateLast({ running: false, output: out === "" ? "（写入完成，caelestia 会自动热重载）" : out });
				if (call)
					root.finishToolCall(call, `${out}\n（配置文件已更新，caelestia 会自动热重载）`);
			}
		}
	}

	function stop(): void {
		root.stoppedFlag = true;
		if (chatProc.running)
			chatProc.running = false;
		if (root.streaming) {
			root.streaming = false;
			if (root.streamText.trim() === "")
				root.updateLast({ content: "（已停止）", error: true });
		}
	}

	Process {
		id: chatProc

		running: false

		stdout: SplitParser {
			onRead: line => root.onStreamLine(line)
		}

		onExited: (code, status) => {
			if (root.stoppedFlag) {
				root.stoppedFlag = false;
				return;
			}
			if (code !== 0 && code !== 143)
				root.appendToLast(`\n[curl 退出码 ${code}，可能是网络/证书/接口地址问题]`, true);
			root.endRequest();
		}
	}

	FileView {
		id: settingsFile

		path: root.settingsPath
		printErrors: false
		blockWrites: true

		onLoaded: {
			try {
				const cfg = JSON.parse(text());
				if (cfg.endpoint)
					root.endpoint = cfg.endpoint;
				if (cfg.model)
					root.model = cfg.model;
				if (typeof cfg.apiKey === "string")
					root.apiKey = cfg.apiKey;
				if (cfg.systemPrompt)
					root.systemPrompt = cfg.systemPrompt;
				if (typeof cfg.fontScale === "number" && cfg.fontScale > 0)
					root.fontScale = cfg.fontScale;
				if (typeof cfg.autoSwitchIme === "boolean")
					root.autoSwitchIme = cfg.autoSwitchIme;
				if (typeof cfg.desiredIme === "string")
					root.desiredIme = cfg.desiredIme;
				console.info(`[aichat] 设置已载入 ${root.settingsPath}（model=${root.model}）`);
			} catch (e) {
				console.warn("[aichat] 设置文件解析失败，用默认值");
			}
		}

		onLoadFailed: err => {
			if (err === FileViewError.FileNotFound) {
				console.info("[aichat] 首次运行：写一份默认设置");
				root.save();
			}
		}
	}
}
