import Foundation

/// אותן יחידות כמו במסייע ל-Windows ובתוכנה עצמה: GB, MB, KB, עם רווח קשיח.
/// בעברית הערך עטוף ב-LRE…PDF, אחרת "37 MB" בתוך משפט עברי מוצג הפוך.
public func humanSize(_ bytes: Int64, english: Bool = false) -> String {
    let text: String
    if bytes >= 1_073_741_824 {
        let tenths = bytes * 10 / 1_073_741_824
        text = "\(tenths / 10).\(tenths % 10)\u{00A0}GB"
    } else if bytes >= 1_048_576 {
        text = "\(bytes / 1_048_576)\u{00A0}MB"
    } else {
        text = "\((bytes + 1023) / 1024)\u{00A0}KB"
    }
    return ltrUnit(text, english: english)
}

public func humanSpeed(_ bytesPerSecond: Double, english: Bool = false) -> String {
    let perSecond = Int64(max(0, bytesPerSecond))
    let text: String
    if perSecond >= 1_048_576 {
        let tenths = perSecond * 10 / 1_048_576
        text = "\(tenths / 10).\(tenths % 10) MB/s"
    } else {
        text = "\(perSecond / 1024) KB/s"
    }
    return ltrUnit(text, english: english)
}

/// השניות שאחרי עיגול התצוגה: 0 (= "כמה שניות") מתחת ל-5, ומעל זה לפי דלי הערך.
public func roundedRemainingSeconds(_ seconds: TimeInterval) -> Int {
    let value = seconds.isFinite ? min(max(0, seconds), 999 * 3600) : 999 * 3600
    if value < 5 { return 0 }
    if value < 60 { return Int((value / 5).rounded()) * 5 }
    if value < 600 { return Int((value / 10).rounded()) * 10 }
    if value < 3600 { return Int((value / 60).rounded()) * 60 }
    return Int((value / 300).rounded()) * 300
}

/// משפט הזמן שנותר, מעוגל לפי גודלו. עיגול לעולם אינו מגיע ל-0 כל עוד נותרה עבודה.
public func remainingText(_ seconds: TimeInterval, english: Bool = false) -> String {
    let value = seconds.isFinite ? min(max(0, seconds), 999 * 3600) : 999 * 3600
    if value < 5 { return english ? "a few seconds left" : "עוד כמה שניות" }
    if value < 60 {
        let rounded = Int((value / 5).rounded()) * 5
        if rounded < 60 { return english ? "about \(rounded) seconds left" : "נותרו כ-\(rounded) שניות" }
    }
    if value < 600 {
        let rounded = Int((value / 10).rounded()) * 10
        if rounded < 600 {
            let minutes = minutesText(rounded / 60, english: english)
            let rest = rounded % 60
            if rest == 0 { return approximately(minutes, english: english) }
            return english
                ? approximately("\(minutes) \(rest) seconds", english: true)
                : approximately("\(minutes) ו-\(rest) שניות", english: false)
        }
    }
    if value < 3600 {
        let rounded = Int((value / 60).rounded())
        if rounded < 60 { return approximately(minutesText(rounded, english: english), english: english) }
    }
    let totalMinutes = Int((value / 300).rounded()) * 5
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    let hoursText: String
    switch hours {
    case 1: hoursText = english ? "1 hour" : "שעה"
    case 2: hoursText = english ? "2 hours" : "שעתיים"
    default: hoursText = english ? "\(hours) hours" : "\(hours) שעות"
    }
    if minutes == 0 { return approximately(hoursText, english: english) }
    let minutesPart = minutesText(minutes, english: english)
    return english
        ? approximately("\(hoursText) \(minutesPart)", english: true)
        : approximately("\(hoursText) ו-\(minutesPart)", english: false)
}

private func minutesText(_ minutes: Int, english: Bool) -> String {
    if minutes == 1 { return english ? "1 minute" : "דקה" }
    return english ? "\(minutes) minutes" : "\(minutes) דקות"
}

/// "כ-" לפני ספרה ו"כ" צמוד לפני מילה; "נותרה" רק לדקה או לשעה לבדן.
private func approximately(_ text: String, english: Bool) -> String {
    if english { return "about \(text) left" }
    let verb = text == "דקה" || text == "שעה" ? "נותרה" : "נותרו"
    let prefix = text.first.map { $0.isNumber } == true ? "כ-" : "כ"
    return "\(verb) \(prefix)\(text)"
}

/// ערך משמאל לימין (גודל, נתיב, גרסה) בתוך משפט עברי.
public func ltrUnit(_ text: String, english: Bool) -> String {
    english ? text : "\u{202A}" + text + "\u{202C}"
}
