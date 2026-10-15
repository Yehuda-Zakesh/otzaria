import Foundation

/// קצב העברה: סכומים דועכים של בתים ושל זמן, משוקלל עם הממוצע. שקט אינו נדגם;
/// הדגימה שאחריו מכסה את הפער (תקיעה בודדת: רק 2 שניות ממנו).
public struct TransferRateEstimator {
    public static let stallSeconds: TimeInterval = 5
    public static let isolatedStallSeconds: TimeInterval = 2
    public static let restartAfterStallSeconds: TimeInterval = 30

    public let tau: TimeInterval
    private var sb: Double = 0
    private var st: Double = 0
    private var lastTime: TimeInterval?
    private var lastBytes: Int64 = 0
    public private(set) var activeElapsed: TimeInterval = 0
    public private(set) var sessionBytes: Int64 = 0
    /// זמן הנתונים, הבתים והדגימות מאז תחילת ההערכה האחרונה (התחלה או תקיעה ארוכה).
    public private(set) var warmElapsed: TimeInterval = 0
    public private(set) var warmBytes: Int64 = 0
    public private(set) var warmSamples = 0
    private var maxDataGap: TimeInterval = 0
    private var lastStallRecoveryTime: TimeInterval?
    private var isolatedStallDeficit: TimeInterval = 0
    /// חימום שהושלם נשאר עד תקיעה ארוכה: תקיעה בודדת שמגדילה את maxGap לא תחזיר "מחשב".
    public private(set) var warmUpLatched = false

    public init(tau: TimeInterval = 8) {
        self.tau = tau
    }

    /// זמן הנתונים הנדרש לחימום: זרם בפרצים ממתין לכמה מחזורים.
    public var warmSecondsNeeded: TimeInterval { max(3, min(15, 3 * maxDataGap)) }

    /// `bytes` — מונה מצטבר של בתי רשת בלבד; `time` — שניות בשעון מונוטוני.
    public mutating func addSample(bytes: Int64, time: TimeInterval) {
        guard let previous = lastTime else { return rebaseline(bytes: bytes, time: time) }
        let delta = bytes - lastBytes
        if delta < 0 { return rebaseline(bytes: bytes, time: time) }
        if delta == 0 { return }
        let gap = time - previous
        if gap < 0.05 { return }
        if gap >= Self.restartAfterStallSeconds {
            // חלון חדש מתחיל בנתונים שחזרו; דגימת ההתאוששות רק קובעת בסיס.
            sb = 0
            st = 0
            warmElapsed = 0
            warmBytes = 0
            warmSamples = 0
            maxDataGap = 0
            lastStallRecoveryTime = nil
            isolatedStallDeficit = 0
            warmUpLatched = false
            return rebaseline(bytes: bytes, time: time)
        }
        var dt = gap
        if gap >= Self.stallSeconds {
            // שקט ארוך שחוזר (פרוקסי שמוסר בפרצים) הוא חלק מהקצב; תקיעה בודדת לא.
            if let lastRecovery = lastStallRecoveryTime, time - lastRecovery <= Self.restartAfterStallSeconds {
                // התקיעה הקודמת נספרה כבודדת (2 שניות) — משלימים את שאר הפער שלה.
                st += isolatedStallDeficit * exp(-(time - lastRecovery) / tau)
                activeElapsed += isolatedStallDeficit
                warmElapsed += isolatedStallDeficit
                isolatedStallDeficit = 0
            } else {
                dt = Self.isolatedStallSeconds
                isolatedStallDeficit = gap - Self.isolatedStallSeconds
            }
            lastStallRecoveryTime = time
        }
        maxDataGap = max(maxDataGap, gap)
        let decay = exp(-dt / tau)
        sb = sb * decay + Double(delta)
        st = st * decay + dt
        activeElapsed += dt
        sessionBytes += delta
        warmElapsed += dt
        warmBytes += delta
        warmSamples += 1
        lastTime = time
        lastBytes = bytes
    }

    public mutating func latchWarmUp() {
        warmUpLatched = true
    }

    /// הדגימה הבאה תימדד מכאן — הפער שלפניה אינו נהפך לדגימה איטית.
    public mutating func rebaseline(bytes: Int64, time: TimeInterval) {
        lastTime = time
        lastBytes = bytes
    }

    /// בתים לשנייה, או nil לפני שנמדד דבר.
    public var rate: Double? {
        guard st > 0, activeElapsed > 0 else { return nil }
        let weight = min(1, max(0.5, activeElapsed / 60))
        return weight * (sb / st) + (1 - weight) * (Double(sessionBytes) / activeElapsed)
    }
}

/// מה ששורת הזמן מציגה.
public enum EtaReading: Equatable {
    case calculating
    case waitingForConnection
    case remaining(TimeInterval)
}

/// שכבת התצוגה: סופרת לאחור בזמן אמת, ומתקנת אל ההערכה הגולמית רק בנקודות תיקון —
/// שנייה של שקט אחרי פרץ נתונים, או זרימה רציפה של 2 שניות לפחות.
public struct EtaCountdownDisplay {
    static let flowGapSeconds: TimeInterval = 1
    static let flowSeconds: TimeInterval = 2
    static let maxCorrectionSeconds: TimeInterval = 30

    public private(set) var shown: TimeInterval?
    private var lastTime: TimeInterval?
    private var lastCorrectionTime: TimeInterval?
    private var lastDataTime: TimeInterval?
    private var flowStartTime: TimeInterval = 0
    private var rawAtLastData: TimeInterval = 0
    private var runOpen = false

    public init() {}

    /// `fresh` — הגיעו נתונים חדשים מאז העדכון הקודם.
    @discardableResult
    public mutating func update(raw: TimeInterval, time: TimeInterval, fresh: Bool) -> TimeInterval {
        let current = shown
        let last = lastTime
        lastTime = time
        let lastData = lastDataTime
        var target: TimeInterval?
        if runOpen, let lastData = lastData, time - lastData >= Self.flowGapSeconds {
            // מסיימים את הפרץ הקודם גם כשכבר הגיעה הדגימה הבאה.
            runOpen = false
            target = rawAtLastData
        }
        if fresh {
            if lastData == nil || time - lastData! >= Self.flowGapSeconds { flowStartTime = time }
            lastDataTime = time
            rawAtLastData = raw
            runOpen = true
        }
        guard let previous = current, let lastUpdate = last else {
            lastCorrectionTime = time
            shown = raw
            return raw
        }
        var next = previous - (time - lastUpdate)
        if fresh && time - flowStartTime >= Self.flowSeconds { target = raw }
        if let target = target {
            let cdt = min(time - (lastCorrectionTime ?? time), Self.maxCorrectionSeconds)
            lastCorrectionTime = time
            if target < next * 0.5 {
                next = target
            } else {
                let diff = target - next
                let outsideBand = abs(diff) > max(5, next * 0.10)
                let tau: TimeInterval = !outsideBand ? 30 : (diff < 0 ? 3 : 12)
                next += (1 - exp(-cdt / tau)) * diff
            }
        }
        let value = max(next, 0)
        shown = value
        return value
    }

    /// הזמן שעובר עד העדכון הבא אינו נספר לאחור (תקיעה, השהיה: התצוגה קפואה).
    public mutating func freeze(time: TimeInterval) {
        lastTime = time
        runOpen = false
    }

    public mutating func reset() {
        shown = nil
        lastTime = nil
        lastCorrectionTime = nil
        runOpen = false
    }
}

public enum EtaPhaseKind: Hashable {
    case hash
    case join
    case copy

    /// הערכה זהירה עד שנמדד קצב אמיתי בעבודה הזאת (MB = 1,000,000 בתים).
    public var defaultRate: Double {
        switch self {
        case .hash: return 150_000_000
        case .join: return 100_000_000
        case .copy: return 100_000_000
        }
    }
}

/// שלב עיבוד שאחרי ההורדה: `id` ייחודי בעבודה, `bytes` כמות העבודה.
public struct EtaPhase: Equatable {
    public let id: String
    public let kind: EtaPhaseKind
    public let bytes: Int64

    public init(_ id: String, _ kind: EtaPhaseKind, bytes: Int64) {
        self.id = id
        self.kind = kind
        self.bytes = bytes
    }

    /// הרכבה = חיבור ואז hash של הקובץ המאוחד. הנחה לתיקייה שבכונן המטמון היא קישור קשיח מיידי.
    /// `alreadyJoined` — בתים שכבר חוברו בהרכבה שנקטעה, לפי שם הנכס.
    public static func phases(
        for actions: [OutputAction], placeIsInstant: Bool, alreadyJoined: [String: Int64] = [:]
    ) -> [EtaPhase] {
        actions.enumerated().flatMap { entry -> [EtaPhase] in
            let index = entry.offset
            switch entry.element {
            case .place(let item, _):
                return placeIsInstant ? [] : [EtaPhase(placeId(index), .copy, bytes: item.size)]
            case .assemble(let name, let size, _, _, _, _):
                let join = max(0, size - (alreadyJoined[name] ?? 0))
                return [EtaPhase(joinId(index), .join, bytes: join), EtaPhase(verifyId(index), .hash, bytes: size)]
            }
        }
    }

    public static func placeId(_ index: Int) -> String { "place:\(index)" }
    public static func joinId(_ index: Int) -> String { "join:\(index)" }
    public static func verifyId(_ index: Int) -> String { "verify:\(index)" }
}

/// זמן נותר לעבודת הורדה אחת, כולל שלבי העיבוד שאחריה. הזמן מוזרק (`now`).
/// בתים שלא הגיעו מהרשת (קובץ שחודש, מטמון) רק מקטינים את `remainingBytes`.
public struct DownloadEta {
    public private(set) var rate = TransferRateEstimator()
    private var speed = TransferRateEstimator(tau: 3)
    public private(set) var display = EtaCountdownDisplay()

    private var remainingDownload: Int64 = 0
    private var lastReceived: Int64?
    private var paused = true
    private var lastActivity: TimeInterval = 0
    private var fresh = false

    private struct RunningPhase {
        let phase: EtaPhase
        let startTime: TimeInterval
        let tracksProgress: Bool
        var processed: Int64 = 0
    }

    private var plan: [EtaPhase] = []
    private var running: RunningPhase?
    private var measuredBytes: [EtaPhaseKind: Double] = [:]
    private var measuredSeconds: [EtaPhaseKind: Double] = [:]

    /// הקריאה האחרונה, לפני ויסות הטקסט.
    public private(set) var lastReading: EtaReading = .calculating
    private var published: EtaReading?
    private var publishedKey: String?
    private var publishedTime: TimeInterval = 0

    public init() {}

    /// שלב שקט ידוע (בדיקת החלק שירד, ניסיון חוזר, שאלה פתוחה): אין דגימות ואין תקיעה
    /// עד הדיווח הבא, שנקבע כבסיס חדש.
    public mutating func pause(remainingBytes: Int64? = nil) {
        paused = true
        if let remaining = remainingBytes { remainingDownload = max(0, remaining) }
    }

    /// `receivedBytes` — מונה מצטבר של בתי רשת; `remainingBytes` — מה שעוד לא על הדיסק.
    public mutating func report(receivedBytes: Int64, remainingBytes: Int64, now: TimeInterval) {
        remainingDownload = max(0, remainingBytes)
        fresh = true
        let last = lastReceived
        lastReceived = receivedBytes
        guard let previous = last, !paused, receivedBytes >= previous else {
            paused = false
            lastActivity = now
            rate.rebaseline(bytes: receivedBytes, time: now)
            speed.rebaseline(bytes: receivedBytes, time: now)
            return
        }
        if receivedBytes == previous { return }
        lastActivity = now
        rate.addSample(bytes: receivedBytes, time: now)
        speed.addSample(bytes: receivedBytes, time: now)
    }

    /// כל ההורדה הסתיימה.
    public mutating func finishDownload() {
        remainingDownload = 0
        if lastReceived == nil { lastReceived = 0 }
        paused = true
        fresh = true
    }

    public mutating func planPhases(_ phases: [EtaPhase]) {
        plan.append(contentsOf: phases)
    }

    public mutating func dropPhase(_ id: String) {
        plan.removeAll { $0.id == id }
    }

    /// `tracksProgress` שקר: שלב בלי דיווחי התקדמות — נספר לאחור מההערכה.
    public mutating func startPhase(_ phase: EtaPhase, tracksProgress: Bool = true, now: TimeInterval) {
        endPhase(now: now)
        dropPhase(phase.id)
        paused = true
        fresh = true
        running = RunningPhase(phase: phase, startTime: now, tracksProgress: tracksProgress)
    }

    public mutating func phaseProgress(_ processedBytes: Int64) {
        guard running != nil else { return }
        running?.processed = processedBytes
        fresh = true
    }

    public mutating func endPhase(now: TimeInterval) {
        guard let phase = running else { return }
        running = nil
        fresh = true
        let seconds = now - phase.startTime
        // שלב קצר מדי אינו מדידה (קישור קשיח מיידי, שלב בלי דיווחים) — היה מנפח את הקצב.
        if seconds < (phase.tracksProgress ? 0.25 : 1) { return }
        let kind = phase.phase.kind
        measuredBytes[kind, default: 0] += Double(phase.tracksProgress ? phase.processed : phase.phase.bytes)
        measuredSeconds[kind, default: 0] += seconds
    }

    public func phaseRate(_ kind: EtaPhaseKind, now: TimeInterval) -> Double {
        var bytes = measuredBytes[kind] ?? 0
        var seconds = measuredSeconds[kind] ?? 0
        if let phase = running, phase.tracksProgress, phase.phase.kind == kind {
            bytes += Double(phase.processed)
            seconds += now - phase.startTime
        }
        if seconds >= 1 && bytes > 0 { return bytes / seconds }
        return kind.defaultRate
    }

    private mutating func warmedUp(_ remaining: Int64) -> Bool {
        if rate.warmUpLatched { return true }
        let warm = rate.warmElapsed >= rate.warmSecondsNeeded && rate.warmSamples >= 3
            && Double(rate.warmBytes) >= min(1_048_576, Double(remaining) * 0.01)
        if warm { rate.latchWarmUp() }
        return warm
    }

    /// לא "0 KB/s": רק אחרי שנייה של נתונים, וכשהמהירות חיובית.
    public var displaySpeed: Double? {
        guard speed.activeElapsed >= 1, let value = speed.rate, value > 0 else { return nil }
        return value
    }

    /// מצב ההערכה כעת; מעדכן את שכבת התצוגה (ספירה לאחור והיסטרזיס).
    public mutating func read(now: TimeInterval) -> EtaReading {
        let current = evaluate(now: now)
        lastReading = current.reading
        return current.reading
    }

    private mutating func evaluate(now t: TimeInterval) -> (reading: EtaReading, key: String) {
        let hasNewData = fresh
        fresh = false
        let phaseKey = running.map { "phase:\($0.phase.kind)" }

        // לפני הדיווח הראשון (התחברות) אין עדיין מה להעריך.
        if lastReceived == nil && running == nil {
            display.reset()
            return (.calculating, "calculating")
        }
        if running == nil && !paused && remainingDownload > 0 {
            let silence = t - lastActivity
            if silence >= TransferRateEstimator.stallSeconds {
                display.freeze(time: t)
                if silence >= TransferRateEstimator.restartAfterStallSeconds { display.reset() }
                return (.waitingForConnection, "stalled")
            }
        }

        var raw: TimeInterval?
        if remainingDownload == 0 {
            raw = 0
        } else if let value = rate.rate, value > 0, warmedUp(remainingDownload) {
            raw = Double(remainingDownload) / value
        }
        if var total = raw {
            if let phase = running {
                let phaseRate = self.phaseRate(phase.phase.kind, now: t)
                total += phase.tracksProgress
                    ? Double(max(phase.phase.bytes - phase.processed, 0)) / phaseRate
                    : max(Double(phase.phase.bytes) / phaseRate - (t - phase.startTime), 0)
            }
            for planned in plan {
                total += Double(planned.bytes) / phaseRate(planned.kind, now: t)
            }
            raw = total
        }
        guard let estimate = raw else {
            display.reset()
            return (.calculating, phaseKey ?? "calculating")
        }
        // השהיה ידועה שאינה שלב מוערך: התצוגה קפואה, כמו בתקיעה.
        let shownValue: TimeInterval
        if paused && running == nil, let frozen = display.shown {
            display.freeze(time: t)
            shownValue = frozen
        } else {
            shownValue = display.update(raw: estimate, time: t, fresh: hasNewData)
        }
        return (.remaining(shownValue), phaseKey ?? "estimating")
    }

    /// כמו `read`, אבל הזמן המוצג מתחלף לכל היותר פעם בשנייה; שינוי מצב מוצג מיד.
    public mutating func displayReading(now: TimeInterval) -> EtaReading {
        let current = evaluate(now: now)
        lastReading = current.reading
        if let previous = published, publishedKey == current.key, now - publishedTime < 1 {
            return previous
        }
        published = current.reading
        publishedKey = current.key
        publishedTime = now
        return current.reading
    }
}
