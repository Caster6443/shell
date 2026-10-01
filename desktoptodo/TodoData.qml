pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var tasks: []
    property var alarms: []
    property int revision: 0
    property bool loaded: false
    readonly property string stateDir: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/caelestia`
    readonly property string storePath: `${root.stateDir}/desktop-todos.json`
    signal reminderDue(var task)

    function fireReminder(task: var): void {
        const summary = task.kind === "alarm" || task.id === "desktop-alarm" ? "闹钟" : "待办提醒";
        Quickshell.execDetached(["notify-send", "--app-name=Caelestia", "--urgency=critical", summary, String(task.title || "")]);
        root.reminderDue(task);
    }

    function normalizeAlarm(value: var, id: string): var {
        const days = [...new Set((value.days || []).map(Number).filter(day => Number.isInteger(day) && day >= 0 && day <= 6))].sort();
        return {
            id: id || value.id || `alarm-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`,
            enabled: value.enabled === true,
            mode: value.mode === "weekly" ? "weekly" : "once",
            onceAt: Number(value.onceAt) > 0 ? Number(value.onceAt) : 0,
            snoozeAt: Number(value.snoozeAt) > 0 ? Number(value.snoozeAt) : 0,
            hour: Math.max(0, Math.min(23, Number(value.hour) || 0)),
            minute: Math.max(0, Math.min(59, Number(value.minute) || 0)),
            days: days,
            label: String(value.label || "闹钟").trim() || "闹钟",
            lastFiredDate: String(value.lastFiredDate || "")
        };
    }

    function saveAlarm(value: var, alarmId: string): string {
        if (!value || !Number.isInteger(value.hour) || value.hour < 0 || value.hour > 23
                || !Number.isInteger(value.minute) || value.minute < 0 || value.minute > 59)
            return "";
        const days = [...new Set((value.days || []).map(Number).filter(day => Number.isInteger(day) && day >= 0 && day <= 6))].sort();
        const mode = value.mode === "weekly" ? "weekly" : "once";
        if (mode === "weekly" && days.length === 0)
            return "";
        let onceAt = 0;
        if (mode === "once") {
            const now = new Date();
            const target = new Date(now.getFullYear(), now.getMonth(), now.getDate(), value.hour, value.minute, 0, 0);
            if (target.getTime() <= now.getTime())
                target.setDate(target.getDate() + 1);
            onceAt = target.getTime();
        }
        const current = new Date();
        const alreadyPassedToday = mode === "weekly" && days.includes(current.getDay())
            && (value.hour * 60 + value.minute) <= (current.getHours() * 60 + current.getMinutes());
        const previous = root.alarms.find(item => item.id === alarmId);
        const alarm = root.normalizeAlarm({
            enabled: previous ? previous.enabled : value.enabled !== false,
            mode: mode,
            onceAt: onceAt,
            snoozeAt: 0,
            hour: value.hour,
            minute: value.minute,
            days: mode === "weekly" ? days : [],
            label: String(value.label || "闹钟").trim() || "闹钟",
            lastFiredDate: alreadyPassedToday ? root.dateKey(current) : ""
        }, alarmId || "");
        if (previous)
            alarm.snoozeAt = previous.snoozeAt;
        root.alarms = previous
            ? root.alarms.map(item => item.id === alarm.id ? alarm : item)
            : [...root.alarms, alarm];
        root.revision++;
        root.save();
        return alarm.id;
    }

    function setAlarmEnabled(alarmId: string, enabled: bool): void {
        root.alarms = root.alarms.map(item => item.id === alarmId
            ? Object.assign({}, item, { enabled: enabled, snoozeAt: enabled ? item.snoozeAt : 0 }) : item);
        root.revision++;
        root.save();
    }

    function removeAlarm(alarmId: string): void {
        root.alarms = root.alarms.filter(item => item.id !== alarmId);
        root.revision++;
        root.save();
    }

    function snoozeAlarm(alarmId: string, minutes: int): void {
        const duration = Math.max(1, Math.min(60, minutes));
        root.alarms = root.alarms.map(item => item.id === alarmId ? Object.assign({}, item, { snoozeAt: Date.now() + duration * 60_000 }) : item);
        root.revision++;
        root.save();
    }

    IpcHandler {
        target: "desktop-todo"

        function testReminder(): void {
            root.fireReminder({
                id: "manual-reminder-test",
                title: "待办提醒效果测试",
                date: root.dateKey(new Date()),
                dueAt: Date.now(),
                done: false,
                notified: true,
                test: true
            });
        }

        function testAlarm(): void {
            root.fireReminder({
                id: "desktop-alarm",
                title: "闹钟测试提醒",
                dueAt: Date.now(),
                test: true
            });
        }
    }

    function dateKey(date: var): string {
        const pad = value => String(value).padStart(2, "0");
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    }

    function tasksFor(date: string): var {
        const rev = root.revision;
        return root.tasks.filter(task => task.date === date)
            .sort((a, b) => (a.dueAt || Number.MAX_SAFE_INTEGER) - (b.dueAt || Number.MAX_SAFE_INTEGER));
    }

    function add(date: string, title: string, timeText: string): bool {
        const cleanTitle = String(title || "").trim();
        const dueText = String(timeText || "").trim();
        if (!cleanTitle || !/^\d{4}-\d{2}-\d{2}$/.test(date))
            return false;
        let dueAt = 0;
        if (dueText !== "") {
            const match = dueText.match(/^([01]\d|2[0-3]):([0-5]\d)$/);
            if (!match)
                return false;
            const parts = date.split("-").map(Number);
            dueAt = new Date(parts[0], parts[1] - 1, parts[2], Number(match[1]), Number(match[2]), 0, 0).getTime();
            if (dueAt <= Date.now())
                return false;
        }

        const next = root.tasks.slice();
        next.push({
            id: `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`,
            date: date,
            title: cleanTitle,
            dueAt: dueAt,
            done: false,
            notified: false
        });
        root.tasks = next;
        root.revision++;
        root.save();
        return true;
    }

    function setDone(id: string, done: bool): void {
        const next = root.tasks.map(task => task.id === id ? Object.assign({}, task, { done: done }) : task);
        root.tasks = next;
        root.revision++;
        root.save();
    }

    function remove(id: string): void {
        root.tasks = root.tasks.filter(task => task.id !== id);
        root.revision++;
        root.save();
    }

    function save(): void {
        if (!root.loaded)
            return;
        try {
            storeFile.setText(JSON.stringify({ version: 2, tasks: root.tasks, alarms: root.alarms }, null, "\t"));
        } catch (e) {
            console.warn(`[desktop-todos] 保存失败: ${e}`);
            return;
        }
        Quickshell.execDetached(["bash", "-c", `mkdir -p '${root.stateDir.replace(/'/g, "'\\''")}' && chmod 600 '${root.storePath.replace(/'/g, "'\\''")}' 2>/dev/null || true`]);
    }

    FileView {
        id: storeFile
        path: root.storePath
        blockWrites: true
        printErrors: false

        onLoaded: {
            try {
                const data = JSON.parse(storeFile.text());
                if (Array.isArray(data?.tasks))
                    root.tasks = data.tasks.filter(task => task && typeof task.id === "string" && typeof task.date === "string" && typeof task.title === "string");
                if (Array.isArray(data?.alarms)) {
                    root.alarms = data.alarms.filter(item => item && typeof item === "object").map(item => root.normalizeAlarm(item, String(item.id || "")));
                } else if (data?.alarm && typeof data.alarm === "object") {
                    root.alarms = [root.normalizeAlarm(data.alarm, "alarm-legacy")];
                } else if (Number(data?.alarmAt) > 0) {
                    const onceAt = Number(data.alarmAt);
                    const oldAlarmDate = new Date(onceAt);
                    root.alarms = [root.normalizeAlarm({
                        enabled: true,
                        mode: "once",
                        onceAt: onceAt,
                        snoozeAt: 0,
                        hour: oldAlarmDate.getHours(),
                        minute: oldAlarmDate.getMinutes(),
                        days: [],
                        label: "闹钟",
                        lastFiredDate: ""
                    }, "alarm-legacy")];
                }
            } catch (e) {
                console.warn(`[desktop-todos] 存储文件解析失败: ${e}`);
            }
            root.loaded = true;
            root.revision++;
        }

        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.loaded = true;
                root.revision++;
            } else {
                console.warn(`[desktop-todos] 读取失败: ${err}`);
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.loaded && (root.alarms.some(item => item.enabled || item.snoozeAt > 0) || root.tasks.some(task => !task.done && !task.notified && Number(task.dueAt) > 0))
        onTriggered: {
            const now = Date.now();
            const due = root.tasks.filter(task => !task.done && !task.notified && Number(task.dueAt) > 0 && Number(task.dueAt) <= now);
            const nowDate = new Date(now);
            const todayKey = root.dateKey(nowDate);
            const dueAlarms = root.alarms.filter(item => {
                const snoozeDue = item.snoozeAt > 0 && item.snoozeAt <= now;
                const scheduledDue = item.enabled && (item.mode === "once"
                    ? item.onceAt > 0 && item.onceAt <= now
                    : item.days.includes(nowDate.getDay())
                        && item.lastFiredDate !== todayKey
                        && (nowDate.getHours() * 60 + nowDate.getMinutes()) >= (item.hour * 60 + item.minute));
                return snoozeDue || scheduledDue;
            });
            if (due.length === 0 && dueAlarms.length === 0)
                return;
            const dueIds = new Set(due.map(task => task.id));
            root.tasks = root.tasks.map(task => dueIds.has(task.id) ? Object.assign({}, task, { notified: true }) : task);
            const dueAlarmIds = new Set(dueAlarms.map(item => item.id));
            root.alarms = root.alarms.map(item => {
                if (!dueAlarmIds.has(item.id))
                    return item;
                const scheduledDue = item.enabled && (item.mode === "once"
                    ? item.onceAt > 0 && item.onceAt <= now
                    : item.days.includes(nowDate.getDay()) && item.lastFiredDate !== todayKey
                        && (nowDate.getHours() * 60 + nowDate.getMinutes()) >= (item.hour * 60 + item.minute));
                return Object.assign({}, item, {
                    snoozeAt: 0,
                    enabled: scheduledDue && item.mode === "once" ? false : item.enabled,
                    onceAt: scheduledDue && item.mode === "once" ? 0 : item.onceAt,
                    lastFiredDate: scheduledDue && item.mode === "weekly" ? todayKey : item.lastFiredDate
                });
            });
            root.revision++;
            root.save();
            for (const task of due)
                root.fireReminder(task);
            for (const alarm of dueAlarms)
                root.fireReminder({ id: alarm.id, kind: "alarm", title: alarm.label || "闹钟", dueAt: now, test: false });
        }
    }

    Component.onCompleted: storeFile.reload()
}
