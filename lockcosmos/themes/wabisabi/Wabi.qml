pragma Singleton
import QtQuick
import Quickshell

// Small palette and seasonal index used by the paper-and-ink theme.
Singleton {
    readonly property string serif: "Noto Serif CJK SC"
    readonly property color paper: "#e7dfcc"
    readonly property color sumi: "#2a2621"
    readonly property color sumiSoft: "#6a6152"
    readonly property color gold: "#c29a48"
    readonly property color shu: "#b04a33"
    readonly property list<string> weekdays: ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
    readonly property list<string> solarTermNames: [
        "小寒", "大寒", "立春", "雨水", "惊蛰", "春分",
        "清明", "谷雨", "立夏", "小满", "芒种", "夏至",
        "小暑", "大暑", "立秋", "处暑", "白露", "秋分",
        "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"
    ]

    // Standard astronomical approximation (minutes from 1900-01-06 02:05,
    // adjusted for leap years). Dates are suitable for a display calendar.
    readonly property list<int> solarTermMinutes: [
        0, 21208, 42467, 63836, 85337, 107014, 128867, 150921,
        173149, 195551, 218072, 240693, 263343, 285989, 308563, 331033,
        353350, 375494, 397447, 419210, 440795, 462224, 483532, 504758
    ]

    function solarTermDate(year, index) {
        const base = new Date(1900, 0, 6, 2, 5).getTime();
        const tropicalYear = 31556925974.7;
        return new Date(base + tropicalYear * (year - 1900) + solarTermMinutes[index] * 60000);
    }

    function solarInfo(date) {
        const events = [];
        for (let year = date.getFullYear() - 1; year <= date.getFullYear() + 1; year++) {
            for (let i = 0; i < solarTermNames.length; i++)
                events.push({ name: solarTermNames[i], index: i, date: solarTermDate(year, i) });
        }
        events.sort((a, b) => a.date - b.date);

        const today = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
        let current = events[0];
        let next = events[events.length - 1];
        for (const event of events) {
            const day = new Date(event.date.getFullYear(), event.date.getMonth(), event.date.getDate()).getTime();
            if (day <= today) current = event;
            else {
                next = event;
                break;
            }
        }

        const nextDay = new Date(next.date.getFullYear(), next.date.getMonth(), next.date.getDate()).getTime();
        const daysUntilNext = Math.max(0, Math.round((nextDay - today) / 86400000));
        const season = current.index < 2 || current.index >= 20 ? "冬季"
            : current.index < 8 ? "春季"
            : current.index < 14 ? "夏季"
            : "秋季";
        return { current, next, daysUntilNext, season };
    }

    function alpha(c, x) {
        return Qt.rgba(c.r, c.g, c.b, x);
    }

    // 0 spring, 1 summer, 2 autumn, 3 winter; used only by the paper shader.
    function season(d) {
        return Math.floor(((d.getMonth() + 10) % 12) / 3);
    }
}
