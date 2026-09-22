pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.services

// 随机 Booru 壁纸（只取 rating:safe）：Moebooru 系 API（yande.re）随机页 → 随机一张图 →
// 下载到缓存目录 → 交给 caelestia 的壁纸接口（`caelestia wallpaper -f`）应用。
Singleton {
	id: root

	property string status: ""
	property bool busy: false
	property string pendingPath: ""
	property string pendingUrl: ""
	property int attempts: 0
	readonly property int maxAttempts: 3
	readonly property string cacheDir: `${Quickshell.env("XDG_CACHE_HOME") || `${Quickshell.env("HOME")}/.cache`}/caelestia/booru`
	readonly property string userAgent: "Mozilla/5.0 (X11; Linux x86_64)"

	function shq(s: string): string {
		return "'" + String(s).replace(/'/g, "'\\''") + "'";
	}

	function randomize(): void {
		if (root.busy)
			return;
		root.busy = true;
		root.attempts = 0;
		root.status = "抓取中…";
		root.fetchNext();
	}

	function fetchNext(): void {
		root.attempts++;
		const page = 1 + Math.floor(Math.random() * 300);
		// 第一次用 16:9 比例标签（与 2560×1440 屏幕正好匹配），不行再退到"安全向 + 本地按宽高筛"
		const tags = root.attempts === 1 ? "rating%3Asafe%20ratio%3A16%3A9" : "rating%3Asafe";
		fetchProc.command = [
			"curl", "-sfL", "--max-time", "20", "-A", root.userAgent,
			`https://yande.re/post.json?limit=100&page=${page}&tags=${tags}`
		];
		fetchProc.running = true;
	}

	// 只挑横向、宽度够显示器、体积不过分的图：yande.re 大量是竖图，直接用会被裁得只剩一条（用户实测）
	function pickFrom(json: string): var {
		try {
			const arr = JSON.parse(json);
			if (!Array.isArray(arr) || arr.length === 0)
				return null;
			const mon = Hyprland.focusedMonitor;
			const minW = Math.max(1920, mon?.width ?? 2560);
			const ok = arr.filter(p => {
				if (!p.file_url || !p.width || !p.height)
					return false;
				return p.width >= minW && p.width / p.height >= 1.35 && (p.file_size ?? 0) <= 12 * 1024 * 1024;
			});
			if (ok.length === 0)
				return null;
			const chosen = ok[Math.floor(Math.random() * ok.length)];
			return {
				url: chosen.file_url,
				width: chosen.width,
				height: chosen.height
			};
		} catch (e) {
			return null;
		}
	}

	Process {
		id: fetchProc

		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				const chosen = root.pickFrom(String(this.text));
				if (chosen === null) {
					if (root.attempts < root.maxAttempts) {
						root.status = `没合适的横向图，重试 ${root.attempts}/${root.maxAttempts}…`;
						root.fetchNext();
						return;
					}
					root.busy = false;
					root.status = "没抓到合适比例的图，再点一次";
					return;
				}
				const extMatch = chosen.url.match(/\.[a-z0-9]{2,4}$/i);
				root.pendingUrl = chosen.url;
				root.pendingPath = `${root.cacheDir}/booru-${Date.now()}${extMatch ? extMatch[0] : ".jpg"}`;
				root.status = `下载中… ${chosen.width}×${chosen.height}`;
				downloadProc.command = [
					"bash", "-c",
					`mkdir -p ${root.shq(root.cacheDir)} && curl -sfL --max-time 60 -A ${root.shq(root.userAgent)} -o ${root.shq(root.pendingPath)} ${root.shq(chosen.url)}`
				];
				downloadProc.running = true;
			}
		}
	}

	Process {
		id: downloadProc

		running: false

		onExited: (code, status) => {
			root.busy = false;
			if (code === 0 && root.pendingPath !== "") {
				console.info(`[spotlight-booru] 应用随机壁纸 ${root.pendingPath}`);
				Wallpapers.setWallpaper(root.pendingPath);
				root.status = "已应用";
			} else {
				root.status = "下载失败";
				console.warn(`[spotlight-booru] curl 退出码 ${code}`);
			}
		}
	}
}
