import Foundation
import XCTest
@testable import AssistantCore

final class ManifestTests: XCTestCase {
    private func manifestJSON(schema: Int = 1, repository: String = "Otzaria/otzaria", sha: String? = nil,
                              extra: String = "") -> Data {
        let hash = sha ?? String(repeating: "a", count: 64)
        return """
        {"schemaVersion": \(schema), "releaseTag": "0.10.3+143", "releaseVersion": "0.10.3", \(extra)
         "components": [{"id": "x", "name": "אוצריא", "type": "future-type", "required": false,
           "futureField": {"nested": true},
           "assets": [{"kind": "single", "repository": "\(repository)", "releaseTag": "0.10.3+143",
                       "name": "a.exe", "size": 3, "sha256": "\(hash)"}]}]}
        """.data(using: .utf8)!
    }

    func testAcceptsUnknownFieldsAndTypes() throws {
        let manifest = try ReleaseManifest.parse(manifestJSON(extra: "\"newTopLevel\": 1,"))
        XCTAssertEqual(manifest.components.first?.type, "future-type")
        XCTAssertEqual(manifest.components.first?.platform, "")
    }

    func testRejectsOtherSchemaVersion() {
        XCTAssertThrowsError(try ReleaseManifest.parse(manifestJSON(schema: 2))) { error in
            XCTAssertEqual((error as? AssistantError)?.message, AssistantError.cannotReadList)
        }
    }

    func testRejectsRepositoryOutsideTheOrganization() {
        XCTAssertThrowsError(try ReleaseManifest.parse(manifestJSON(repository: "Evil/otzaria")))
        XCTAssertThrowsError(try ReleaseManifest.parse(manifestJSON(repository: "Otzaria/..")))
    }

    func testRejectsMissingOrMalformedHash() {
        XCTAssertThrowsError(try ReleaseManifest.parse(manifestJSON(sha: "")))
        XCTAssertThrowsError(try ReleaseManifest.parse(manifestJSON(sha: String(repeating: "A", count: 64))))
    }

    func testRejectsSplitWhosePartsDoNotSumToTheWhole() {
        let hash = String(repeating: "b", count: 64)
        let json = """
        {"schemaVersion": 1, "releaseTag": "t", "releaseVersion": "1", "components": [{"id": "x", "name": "n",
          "type": "library", "assets": [{"kind": "split", "repository": "Otzaria/otzaria", "releaseTag": "t",
          "name": "a.tar.zst", "size": 10, "sha256": "\(hash)",
          "parts": [{"name": "a.tar.zst.part-000", "size": 4, "sha256": "\(hash)"}]}]}]}
        """
        XCTAssertThrowsError(try ReleaseManifest.parse(json.data(using: .utf8)!))
    }
}

final class EndpointTests: XCTestCase {
    func testAssetURLKeepsThePlusOfTheTag() {
        XCTAssertEqual(
            Endpoints.assetURL(repository: "Otzaria/SeforimLibrary", tag: "0.10.3+143", name: "a.tar.zst")?.absoluteString,
            "https://github.com/Otzaria/SeforimLibrary/releases/download/0.10.3+143/a.tar.zst"
        )
    }

    func testAssetURLRejectsUnsafeParts() {
        XCTAssertNil(Endpoints.assetURL(repository: "otzaria/otzaria", tag: "1", name: "a"))
        XCTAssertNil(Endpoints.assetURL(repository: "Otzaria/a/b", tag: "1", name: "a"))
        XCTAssertNil(Endpoints.assetURL(repository: "Otzaria/otzaria", tag: "..", name: "a"))
        XCTAssertNil(Endpoints.assetURL(repository: "Otzaria/otzaria", tag: "1", name: "a/b"))
        XCTAssertNil(Endpoints.assetURL(repository: "Otzaria/otzaria", tag: "1", name: "א.exe"))
        XCTAssertNil(Endpoints.assetURL(repository: "Otzaria/otzaria", tag: "1 2", name: "a"))
    }

    func testRedirectHosts() {
        let allowed = [
            "https://github.com/Otzaria/otzaria/releases/download/0.10.3+143/a.exe",
            "https://objects.githubusercontent.com/github-production-release-asset/1?x=y",
            "https://release-assets.githubusercontent.com/github-production-release-asset/1/2?sp=r",
            "https://api.github.com/repositories/123/releases/latest",
            "https://GITHUB.com/Otzaria/otzaria/x",
        ]
        for url in allowed {
            XCTAssertTrue(Endpoints.isAllowed(URL(string: url)), url)
        }
        let blocked = [
            "http://github.com/Otzaria/otzaria/releases/download/1/a",
            "https://github.com/evil/otzaria/releases/download/1/a",
            "https://github.com/Otzaria/../evil/x",
            "https://evil.com/Otzaria/otzaria",
            "https://github.com.evil.com/Otzaria/x",
            "https://raw.githubusercontent.com/Otzaria/otzaria/main/x",
            "https://github.com:8443/Otzaria/x",
            "https://user@github.com/Otzaria/x",
            "ftp://github.com/Otzaria/x",
        ]
        for url in blocked {
            XCTAssertFalse(Endpoints.isAllowed(URL(string: url)), url)
        }
        XCTAssertFalse(Endpoints.isAllowed(nil))
    }
}

final class ReleaseTagTests: XCTestCase {
    func testVersionPartIgnoresBuildSuffix() {
        XCTAssertEqual(ReleaseTagChoice.versionPart("0.10.3+143"), "0.10.3")
        XCTAssertEqual(ReleaseTagChoice.versionPart(" v0.11.0 "), "0.11.0")
        XCTAssertEqual(ReleaseTagChoice.compare("0.10.3+143", "0.10.3+999"), 0)
        XCTAssertEqual(ReleaseTagChoice.compare("0.10.10", "0.10.9"), 1)
        XCTAssertEqual(ReleaseTagChoice.compare("0.9.99", "0.10.0"), -1)
        XCTAssertEqual(ReleaseTagChoice.compare("1.0", "1.0.0"), 0)
    }

    func testEmbeddedTagWinsUnlessLatestIsHigher() {
        XCTAssertEqual(ReleaseTagChoice.choose(embedded: "0.10.3+143", latest: "0.10.3"), "0.10.3+143")
        XCTAssertEqual(ReleaseTagChoice.choose(embedded: "0.10.3+143", latest: "0.9.99"), "0.10.3+143")
        XCTAssertEqual(ReleaseTagChoice.choose(embedded: "0.10.3+143", latest: "0.10.4"), "0.10.4")
        XCTAssertEqual(ReleaseTagChoice.choose(embedded: "0.10.3+143", latest: "0.10.4+150"), "0.10.4+150")
        XCTAssertEqual(ReleaseTagChoice.choose(embedded: "0.10.3+143", latest: nil), "0.10.3+143")
        XCTAssertEqual(ReleaseTagChoice.choose(embedded: "0.10.3+143", latest: ""), "0.10.3+143")
    }

    func testLocalBuildFallsBackToLatest() {
        XCTAssertEqual(ReleaseTagChoice.choose(embedded: "", latest: "0.10.3"), "0.10.3")
        XCTAssertNil(ReleaseTagChoice.choose(embedded: "", latest: nil))
    }

    func testUnsafeLatestTagIsIgnored() {
        XCTAssertEqual(ReleaseTagChoice.choose(embedded: "0.10.3", latest: "9.9.9/../x"), "0.10.3")
        XCTAssertNil(ReleaseTagChoice.choose(embedded: "", latest: "a b"))
    }
}

final class ResumeRulesTests: XCTestCase {
    func testRangeHeaderOnlyForAResumablePartial() {
        XCTAssertNil(ResumeRules.rangeHeader(existing: 0, size: 100))
        XCTAssertEqual(ResumeRules.rangeHeader(existing: 40, size: 100), "bytes=40-")
        XCTAssertNil(ResumeRules.rangeHeader(existing: 100, size: 100))
    }

    func testExactContentRangeResumes() {
        XCTAssertEqual(
            ResumeRules.action(requestedOffset: 40, statusCode: 206, contentRange: "bytes 40-99/100", expectedSize: 100),
            .append(from: 40)
        )
    }

    func testMismatchedContentRangeDiscards() {
        for range in ["bytes 0-99/100", "bytes 40-99/200", "bytes 40-59/100", nil] {
            XCTAssertEqual(
                ResumeRules.action(requestedOffset: 40, statusCode: 206, contentRange: range, expectedSize: 100),
                .discardPartial, range ?? "nil"
            )
        }
    }

    /// ברשת המסוננת Range מתעלם: 200 עם כל הקובץ נכתב מההתחלה, בלי בקשה שנייה.
    func testFullReplyToARangeRequestIsWrittenFromTheStart() {
        XCTAssertEqual(
            ResumeRules.action(requestedOffset: 40, statusCode: 200, contentRange: nil, expectedSize: 100),
            .writeFromStart
        )
        XCTAssertEqual(
            ResumeRules.action(requestedOffset: 0, statusCode: 200, contentRange: nil, expectedSize: 100),
            .writeFromStart
        )
    }

    func testOtherStatuses() {
        XCTAssertEqual(
            ResumeRules.action(requestedOffset: 0, statusCode: 404, contentRange: nil, expectedSize: 100),
            .fail(retryable: false)
        )
        XCTAssertEqual(
            ResumeRules.action(requestedOffset: 40, statusCode: 416, contentRange: nil, expectedSize: 100),
            .discardPartial
        )
        XCTAssertEqual(
            ResumeRules.action(requestedOffset: 40, statusCode: 503, contentRange: nil, expectedSize: 100),
            .fail(retryable: true)
        )
        XCTAssertEqual(
            ResumeRules.action(requestedOffset: 0, statusCode: 206, contentRange: "bytes 0-99/100", expectedSize: 100),
            .fail(retryable: false)
        )
    }

    func testRetryPolicy() {
        XCTAssertEqual(RetryPolicy.delay(forRetry: 0), 2)
        XCTAssertEqual(RetryPolicy.delay(forRetry: 1), 5)
        XCTAssertEqual(RetryPolicy.delay(forRetry: 2), 10)
        XCTAssertNil(RetryPolicy.delay(forRetry: 3))
        XCTAssertTrue(RetryPolicy.isNetworkError(URLError(.networkConnectionLost)))
        XCTAssertFalse(RetryPolicy.isNetworkError(URLError(.serverCertificateUntrusted)))
    }
}

final class CacheStatusTests: XCTestCase {
    private let sha = String(repeating: "c", count: 64)
    private let early = Date(timeIntervalSince1970: 1000)
    private let late = Date(timeIntervalSince1970: 2000)

    func testMarkerFormatIsSha256sum() {
        XCTAssertEqual(CacheMarker.line(sha256: sha, name: "a.exe"), "\(sha)  a.exe\n")
        XCTAssertEqual(CacheMarker.parse("\(sha)  a.exe\n"), sha)
        XCTAssertEqual(CacheMarker.parse(sha.uppercased() + " *a.exe"), sha)
        XCTAssertNil(CacheMarker.parse("nothex  a.exe"))
    }

    func testStatus() {
        let marker = CacheMarker.line(sha256: sha, name: "a")
        XCTAssertEqual(cacheStatus(fileSize: nil, fileModified: nil, markerText: marker, markerModified: late,
                                   expectedSize: 5, expectedSha256: sha), .missing)
        XCTAssertEqual(cacheStatus(fileSize: 4, fileModified: early, markerText: marker, markerModified: late,
                                   expectedSize: 5, expectedSha256: sha), .invalid)
        XCTAssertEqual(cacheStatus(fileSize: 5, fileModified: early, markerText: marker, markerModified: late,
                                   expectedSize: 5, expectedSha256: sha), .ready)
        XCTAssertEqual(cacheStatus(fileSize: 5, fileModified: late, markerText: marker, markerModified: late,
                                   expectedSize: 5, expectedSha256: sha), .ready)
        // קובץ שנכתב אחרי החותם, חותם פגום, או בלי חותם — hash אחד מהדיסק.
        XCTAssertEqual(cacheStatus(fileSize: 5, fileModified: late, markerText: marker, markerModified: early,
                                   expectedSize: 5, expectedSha256: sha), .needsHash)
        XCTAssertEqual(cacheStatus(fileSize: 5, fileModified: early, markerText: "garbage", markerModified: late,
                                   expectedSize: 5, expectedSha256: sha), .needsHash)
        // חותם תקף של hash אחר מוכיח שהתוכן שגוי — נמחק בלי hash.
        XCTAssertEqual(cacheStatus(fileSize: 5, fileModified: early, markerText: marker, markerModified: late,
                                   expectedSize: 5, expectedSha256: String(repeating: "d", count: 64)), .invalid)
        XCTAssertEqual(cacheStatus(fileSize: 5, fileModified: early, markerText: nil, markerModified: nil,
                                   expectedSize: 5, expectedSha256: sha), .needsHash)
    }
}

final class WildcardTests: XCTestCase {
    private let linuxDebX64 = AssistantTarget(platform: "linux", architecture: "x64", packageFormat: "deb")

    func testAnyMatchesEveryTarget() {
        let any = ManifestComponent(id: "a", type: "library", platform: "any", architecture: "any", packageFormat: "any")
        XCTAssertTrue(componentFitsTarget(any, linuxDebX64))
        XCTAssertTrue(componentFitsTarget(any, AssistantTarget(platform: "macos")))
        XCTAssertTrue(componentFitsTarget(ManifestComponent(id: "b", type: "library"), linuxDebX64))
        XCTAssertFalse(componentFitsTarget(
            ManifestComponent(id: "c", type: "application", platform: "linux", packageFormat: "rpm"), linuxDebX64
        ))
    }

    func testAnyIsNeverAChoice() {
        let manifest = ReleaseManifest(components: [
            ManifestComponent(id: "deb", type: "application", platform: "linux", architecture: "x64", packageFormat: "deb"),
            ManifestComponent(id: "lib", type: "library", platform: "linux", architecture: "any", packageFormat: "any"),
            ManifestComponent(id: "arm", type: "application", platform: "linux", architecture: "arm64", packageFormat: "deb"),
        ])
        XCTAssertEqual(architectureChoices(manifest, "linux"), ["x64", "arm64"])
        XCTAssertEqual(packageFormatChoices(manifest, "linux", "x64"), ["deb"])
    }
}

final class ManifestSourceTests: XCTestCase {
    /// ה-API במגבלת קצב (403/429): התג המוטבע מספיק, והמניפסט יורד מהכתובת הישירה.
    func testNoApiAnswerFallsBackToTheDirectAsset() {
        let expected = "https://github.com/Otzaria/otzaria/releases/download/0.10.3%2B143/otzaria-release-manifest.json"
        XCTAssertEqual(ManifestSource.decide(tag: "0.10.3+143", release: nil), .url(URL(string: expected)!))
        if case .url(let url) = ManifestSource.decide(tag: "0.10.3+143", release: nil) {
            XCTAssertTrue(Endpoints.isAllowed(url))
        }
        XCTAssertEqual(ManifestSource.decide(tag: "a/b", release: nil), .missing)
    }

    func testApiAssetListWins() {
        let release: [String: Any] = ["assets": [["name": "x.exe"], ["name": "otzaria-release-manifest.json"]]]
        let expected = "https://github.com/Otzaria/otzaria/releases/download/0.10.3/otzaria-release-manifest.json"
        XCTAssertEqual(ManifestSource.decide(tag: "0.10.3", release: release), .url(URL(string: expected)!))
        XCTAssertEqual(ManifestSource.decide(tag: "0.10.3", release: ["assets": [["name": "x.exe"]]]), .missing)
    }
}

final class StaleHashGateTests: XCTestCase {
    private final class Owner {}

    /// hash מהדיסק שהסתיים אחרי שהמשימה נסגרה אינו פותח את הקובץ שוב.
    func testOnlyTheCurrentOwnerContinues() {
        let transfer = Owner()
        let retry = Owner()
        XCTAssertTrue(ResumeRules.mayContinueAfterPrefixHash(engineEnded: false, currentOwner: transfer, transfer: transfer))
        XCTAssertFalse(ResumeRules.mayContinueAfterPrefixHash(engineEnded: false, currentOwner: nil, transfer: transfer))
        XCTAssertFalse(ResumeRules.mayContinueAfterPrefixHash(engineEnded: false, currentOwner: retry, transfer: transfer))
        XCTAssertFalse(ResumeRules.mayContinueAfterPrefixHash(engineEnded: true, currentOwner: transfer, transfer: transfer))
    }
}

final class FormattingTests: XCTestCase {
    func testHumanSizeMatchesTheWindowsAssistant() {
        XCTAssertEqual(humanSize(500, english: true), "1\u{00A0}KB")
        XCTAssertEqual(humanSize(5 * 1_048_576, english: true), "5\u{00A0}MB")
        XCTAssertEqual(humanSize(2_012_390_081, english: true), "1.8\u{00A0}GB")
        // בעברית אותו ערך, עטוף כדי שלא יתהפך בתוך משפט.
        XCTAssertEqual(humanSize(5 * 1_048_576), "\u{202A}5\u{00A0}MB\u{202C}")
        XCTAssertEqual(humanSpeed(1_500_000, english: true), "1.4 MB/s")
        XCTAssertEqual(humanSpeed(10_240, english: true), "10 KB/s")
    }

    func testRemainingTextBuckets() {
        let table: [(TimeInterval, String)] = [
            (0, "עוד כמה שניות"),
            (4.9, "עוד כמה שניות"),
            (5, "נותרו כ-5 שניות"),
            (57, "נותרו כ-55 שניות"),
            // עיגול ל-60 שניות עובר לשורת הדקות, ולא "60 שניות".
            (59, "נותרה כדקה"),
            (60, "נותרה כדקה"),
            (95, "נותרו כדקה ו-40 שניות"),
            (90, "נותרו כדקה ו-30 שניות"),
            (150, "נותרו כ-2 דקות ו-30 שניות"),
            (599, "נותרו כ-10 דקות"),
            (600, "נותרו כ-10 דקות"),
            (44 * 60 + 10, "נותרו כ-44 דקות"),
            (3599, "נותרה כשעה"),
            (3600, "נותרה כשעה"),
            (3600 + 20 * 60, "נותרו כשעה ו-20 דקות"),
            (2 * 3600, "נותרו כשעתיים"),
            (2 * 3600 + 310, "נותרו כשעתיים ו-5 דקות"),
            (3 * 3600 + 3590, "נותרו כ-4 שעות"),
            (4.7, "עוד כמה שניות"),
            (44, "נותרו כ-45 שניות"),
            (200, "נותרו כ-3 דקות ו-20 שניות"),
            (1830, "נותרו כ-31 דקות"),
            (4500, "נותרו כשעה ו-15 דקות"),
            (3 * 3600 + 20 * 60, "נותרו כ-3 שעות ו-20 דקות"),
        ]
        for (seconds, expected) in table {
            XCTAssertEqual(remainingText(seconds), expected, "\(seconds)")
        }
        XCTAssertEqual(remainingText(4.9, english: true), "a few seconds left")
        XCTAssertEqual(remainingText(30, english: true), "about 30 seconds left")
        XCTAssertEqual(remainingText(95, english: true), "about 1 minute 40 seconds left")
        XCTAssertEqual(remainingText(3600, english: true), "about 1 hour left")
        XCTAssertEqual(remainingText(60, english: true), "about 1 minute left")
        XCTAssertEqual(remainingText(2 * 3600 + 310, english: true), "about 2 hours 5 minutes left")
    }
}

private let mb: Int64 = 1_000_000

/// מעריך עם שעון מזויף. כמו ברץ: קריאה אחרי כל דיווח, וטיימר של שנייה בשקט.
private final class EtaHarness {
    var eta = DownloadEta()
    let total: Int64
    var micros: Int64 = 0
    var bytes: Int64 = 0
    /// הקצב האמיתי הנוכחי, לחישוב הזמן הנותר המדויק.
    var trueRate: Int64 = 10 * mb

    init(total: Int64 = 1000 * mb) {
        self.total = total
    }

    var now: TimeInterval { Double(micros) / 1e6 }

    func advance(seconds: Double) {
        micros += Int64((seconds * 1e6).rounded())
    }

    func report(_ value: Int64) {
        bytes = value
        eta.report(receivedBytes: value, remainingBytes: total - value, now: now)
        _ = eta.displayReading(now: now)
    }

    func feed(seconds: Double, bytesPerSecond: Int64? = nil) {
        if let rate = bytesPerSecond { trueRate = rate }
        let steps = Int((seconds * 10).rounded())
        for _ in 0..<steps {
            advance(seconds: 0.1)
            report(bytes + trueRate / 10)
        }
    }

    /// שקט בלי בתים; מחזיר את הקריאות בתקתוקי הטיימר.
    func silence(_ seconds: Int) -> [EtaReading] {
        (0..<seconds).map { _ -> EtaReading in
            advance(seconds: 1)
            return read()
        }
    }

    func read() -> EtaReading { eta.read(now: now) }

    var etaSeconds: TimeInterval {
        if case .remaining(let value) = read() { return value }
        return -1
    }

    var exactEta: TimeInterval { Double(total - bytes) / Double(trueRate) }
}

/// מחולל פסאודו-אקראי קבוע (SplitMix64), כדי שהרעש יהיה זהה בכל ריצה.
private struct SplitMix64 {
    var state: UInt64

    mutating func nextDouble() -> Double {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}

/// צ'אנק רשת: זמן הגעה (ms) ומספר בתים.
private struct Chunk {
    let ms: Int
    let bytes: Int64
}

/// זרם יציב: צ'אנק כל 100ms בקצב `rate` עם רעש של ±`jitter`.
private func steadyChunks(totalBytes: Int64, rate: Int64, jitter: Double = 0) -> [Chunk] {
    var random = SplitMix64(state: 7)
    var chunks: [Chunk] = []
    var sent: Int64 = 0
    var ms = 100
    while sent < totalBytes {
        let factor = 1 + jitter * (2 * random.nextDouble() - 1)
        let bytes = min(Int64((Double(rate) / 10 * factor).rounded()), totalBytes - sent)
        chunks.append(Chunk(ms: ms, bytes: bytes))
        sent += bytes
        ms += 100
    }
    return chunks
}

/// פרצים בממוצע 5MB/s: `onChunks` צ'אנקים במרווח 100ms, ואז פער של `offSeconds` (במחזוריות)
/// עד הצ'אנק הבא — הפער כפי שהמעריך רואה אותו.
private func burstyChunks(offSeconds: [Double], onChunks: Int = 6, totalBytes: Int64 = 2000 * mb) -> [Chunk] {
    let meanOff = offSeconds.reduce(0, +) / Double(offSeconds.count)
    let cycle = Double(onChunks - 1) * 0.1 + meanOff
    let chunkBytes = Int64((5 * Double(mb) * cycle / Double(onChunks)).rounded())
    var chunks: [Chunk] = []
    var sent: Int64 = 0
    var ms = 0
    var cycleIndex = 0
    while sent < totalBytes {
        ms += Int((offSeconds[cycleIndex % offSeconds.count] * 1000).rounded())
        var index = 0
        while index < onChunks && sent < totalBytes {
            if index > 0 { ms += 100 }
            let bytes = min(chunkBytes, totalBytes - sent)
            chunks.append(Chunk(ms: ms, bytes: bytes))
            sent += bytes
            index += 1
        }
        cycleIndex += 1
    }
    return chunks
}

/// מקטעים של (שניות, קצב); קצב 0 = שקט. המקטע האחרון נמשך עד הסוף.
private func segmentChunks(_ segments: [(seconds: Int, rate: Int64)], totalBytes: Int64) -> [Chunk] {
    var chunks: [Chunk] = []
    var sent: Int64 = 0
    var start = 0
    for segment in segments {
        let end = start + segment.seconds * 1000
        var ms = start + 100
        while ms <= end && sent < totalBytes {
            if segment.rate != 0 {
                let bytes = min(segment.rate / 10, totalBytes - sent)
                chunks.append(Chunk(ms: ms, bytes: bytes))
                sent += bytes
            }
            ms += 100
        }
        start = end
    }
    return chunks
}

private struct EtaRun {
    struct Record {
        let t: TimeInterval
        let shown: TimeInterval?
        let reading: EtaReading
    }

    let records: [Record]
    /// (זמן, ערך מעוגל) בכל החלפת טקסט שיש בו זמן.
    let texts: [(TimeInterval, Int)]
    let tEnd: TimeInterval

    var firstShownT: TimeInterval? { records.first { $0.shown != nil }?.t }

    func error(_ record: Record) -> Double {
        abs((record.shown ?? 0) - (tEnd - record.t)) / (tEnd - record.t)
    }

    var firstError: Double { records.first { $0.shown != nil }.map(error) ?? .infinity }

    /// השגיאה היחסית המרבית מ-`from`, כל עוד נותרו `minTruth` שניות לפחות.
    func maxError(from: TimeInterval, minTruth: TimeInterval = 60) -> Double {
        records.filter { $0.shown != nil && $0.t >= from && tEnd - $0.t >= minTruth }.map(error).reduce(0, max)
    }

    func errorAt(_ t: TimeInterval) -> Double {
        records.last { $0.shown != nil && $0.t <= t }.map(error) ?? .infinity
    }

    func textIncreases(until: TimeInterval = .infinity) -> Int {
        var count = 0
        var index = 1
        while index < texts.count && texts[index].0 <= until {
            if texts[index].1 > texts[index - 1].1 { count += 1 }
            index += 1
        }
        return count
    }
}

private func timeText(_ reading: EtaReading) -> String {
    switch reading {
    case .calculating: return "calculating"
    case .waitingForConnection: return "waiting"
    case .remaining(let seconds): return remainingText(seconds)
    }
}

/// מריץ את המעריך כמו הרץ: מושהה לפני ההורדה, קריאה אחרי כל צ'אנק, וטיימר של שנייה.
/// האמת: הזמן עד הצ'אנק האחרון.
private func simulate(_ chunks: [Chunk]) -> EtaRun {
    var ms = 0
    let total = chunks.reduce(Int64(0)) { $0 + $1.bytes }
    var eta = DownloadEta()
    var records: [EtaRun.Record] = []
    var texts: [(TimeInterval, Int)] = []
    var lastText: String?
    func observe() {
        let t = Double(ms) / 1000
        let published = eta.displayReading(now: t)
        let reading = eta.lastReading
        var shown: TimeInterval?
        if case .remaining(let value) = reading { shown = value }
        records.append(EtaRun.Record(t: t, shown: shown, reading: reading))
        let text = timeText(published)
        if text != lastText, case .remaining(let value) = published {
            texts.append((t, roundedRemainingSeconds(value)))
        }
        lastText = text
    }
    var bytes: Int64 = 0
    var nextTick = 1050
    for chunk in chunks {
        while nextTick < chunk.ms {
            ms = nextTick
            observe()
            nextTick += 1000
        }
        ms = chunk.ms
        bytes += chunk.bytes
        eta.report(receivedBytes: bytes, remainingBytes: total - bytes, now: Double(ms) / 1000)
        observe()
    }
    return EtaRun(records: records, texts: texts, tEnd: Double(chunks.last?.ms ?? 0) / 1000)
}

/// פרצים: `dataSeconds` של נתונים (צ'אנק כל 100ms) ואז פער של `silenceSeconds` בין דגימות;
/// מחזיר את הקצב בסוף כל פרץ במחצית השנייה.
private func burstyRates(dataSeconds: Double, silenceSeconds: Double, averageRate: Double, cycles: Int = 40) -> [Double] {
    let interval = 0.1
    let chunksPerBurst = Int((dataSeconds / interval).rounded())
    var rate = TransferRateEstimator()
    let cycle = Double(chunksPerBurst - 1) * interval + silenceSeconds
    let chunk = Int64((averageRate * cycle / Double(chunksPerBurst)).rounded())
    var t = 0.0
    var bytes: Int64 = 0
    rate.addSample(bytes: 0, time: 0)
    var measured: [Double] = []
    for index in 0..<cycles {
        for _ in 0..<chunksPerBurst {
            t += interval
            bytes += chunk
            rate.addSample(bytes: bytes, time: t)
        }
        if index >= cycles / 2 { measured.append(rate.rate ?? 0) }
        t += silenceSeconds - interval
    }
    return measured
}

final class EtaWarmUpTests: XCTestCase {
    func testNoEstimateBeforeThreeSecondsOfData() {
        let h = EtaHarness()
        h.report(0)
        h.feed(seconds: 2.5, bytesPerSecond: 10 * mb)
        XCTAssertEqual(h.read(), .calculating)
        h.feed(seconds: 1)
        XCTAssertEqual(h.etaSeconds, h.exactEta, accuracy: h.exactEta * 0.05)
    }

    func testCalculatingBeforeTheFirstReportEvenWithPlannedPhases() {
        let h = EtaHarness()
        h.eta.planPhases([EtaPhase("join:0", .join, bytes: 400 * mb)])
        h.eta.pause()
        h.advance(seconds: 2)
        XCTAssertEqual(h.read(), .calculating)
    }

    func testNoEstimateUntilEnoughBytes() {
        let h = EtaHarness()
        h.report(0)
        // 100KB/s במשך 5 שניות = 500KB, פחות מ-1MiB ומ-1% מהנותר.
        h.feed(seconds: 5, bytesPerSecond: 100_000)
        XCTAssertEqual(h.read(), .calculating)
    }

    func testSpeedIsHiddenUntilASecondOfData() {
        var eta = DownloadEta()
        eta.report(receivedBytes: 0, remainingBytes: 10 * mb, now: 0)
        eta.report(receivedBytes: 500_000, remainingBytes: 10 * mb, now: 0.5)
        XCTAssertNil(eta.displaySpeed)
        eta.report(receivedBytes: 1_000_000, remainingBytes: 9 * mb, now: 1)
        XCTAssertEqual(eta.displaySpeed ?? 0, 1_000_000, accuracy: 1)
    }

    func testCounterGoingBackwardsNeitherResetsNorInflates() {
        let h = EtaHarness()
        h.report(0)
        h.feed(seconds: 10, bytesPerSecond: 10 * mb)
        // ניסיון חוזר שאינו ניתן להמשך: ההורדה מתחילה שוב מאפס.
        h.advance(seconds: 0.1)
        h.report(1000)
        XCTAssertNotNil(remainingSeconds(h.read()))
        h.feed(seconds: 2)
        XCTAssertLessThanOrEqual(h.etaSeconds, h.exactEta * 1.1)
        XCTAssertGreaterThan(h.etaSeconds, 50)
    }
}

private func remainingSeconds(_ reading: EtaReading) -> TimeInterval? {
    if case .remaining(let value) = reading { return value }
    return nil
}

/// שניות שלמות אחרי עיגול למיקרו-שנייה, כמו Duration.inSeconds.
private func wholeSeconds(_ reading: EtaReading) -> Int? {
    remainingSeconds(reading).map { Int(($0 * 1e6).rounded()) / 1_000_000 }
}

final class EtaSilenceTests: XCTestCase {
    func testKnownPauseFreezesWithoutStall() {
        let h = EtaHarness()
        h.report(0)
        h.feed(seconds: 10, bytesPerSecond: 10 * mb)
        let before = h.etaSeconds
        h.eta.pause()
        // hash של התחילית או חיבור: דקה בלי דיווחים, בלי מצב תקיעה.
        for tick in h.silence(60) {
            XCTAssertEqual(remainingSeconds(tick) ?? -1, before, accuracy: 1e-6)
        }
        h.report(h.bytes + 64 * 1024)
        h.feed(seconds: 2)
        XCTAssertLessThanOrEqual(h.etaSeconds, before)
        XCTAssertEqual(h.etaSeconds, h.exactEta, accuracy: h.exactEta * 0.1)
    }

    func testStallShowsWaitingForConnection() {
        let h = EtaHarness()
        h.report(0)
        h.feed(seconds: 10, bytesPerSecond: 10 * mb)
        let ticks = h.silence(6)
        XCTAssertNotNil(remainingSeconds(ticks[3]))
        XCTAssertEqual(ticks[5], .waitingForConnection)
    }

    func testShortSilencesWithTimerTicksDoNotRaiseTheEta() {
        let h = EtaHarness(total: 3000 * mb)
        h.report(0)
        h.feed(seconds: 20, bytesPerSecond: 10 * mb)
        var previous = h.etaSeconds
        for gap in [1, 2, 3, 4] {
            for tick in h.silence(gap) {
                let shown = remainingSeconds(tick) ?? .infinity
                XCTAssertLessThanOrEqual(shown, previous, "gap \(gap)")
                previous = shown
            }
            h.feed(seconds: 5)
            previous = h.etaSeconds
        }
    }

    func testTwelveSecondStallStaysWithinTruthPlusTwelve() {
        let h = EtaHarness(total: 2000 * mb)
        h.report(0)
        h.feed(seconds: 20, bytesPerSecond: 10 * mb)
        _ = h.silence(12)
        for step in 0..<600 {
            h.feed(seconds: 0.1)
            XCTAssertLessThanOrEqual(h.etaSeconds, (h.exactEta + 12) * 1.1, "\(step)")
        }
    }

    func testIsolatedStallAfterWarmUpDoesNotBringBackCalculating() {
        let h = EtaHarness(total: 2000 * mb)
        h.report(0)
        h.feed(seconds: 5, bytesPerSecond: 10 * mb)
        XCTAssertNotNil(remainingSeconds(h.read()))
        for tick in h.silence(12) {
            XCTAssertNotEqual(tick, .calculating)
        }
        for step in 0..<600 {
            h.feed(seconds: 0.1)
            XCTAssertNotEqual(h.read(), .calculating, "\(step)")
        }
    }

    func testFortyFiveSecondStallCalculatesThenEstimatesWithinFifteenPercent() {
        let h = EtaHarness(total: 2000 * mb)
        h.report(0)
        h.feed(seconds: 20, bytesPerSecond: 10 * mb)
        _ = h.silence(45)
        h.feed(seconds: 0.1)
        XCTAssertEqual(h.read(), .calculating)
        var guardSteps = 0
        while h.read() == .calculating && guardSteps < 1000 {
            h.feed(seconds: 0.1)
            guardSteps += 1
        }
        XCTAssertEqual(h.etaSeconds, h.exactEta, accuracy: h.exactEta * 0.15)
    }

    func testPermanentRateChangeWithinTenPercentAfter45Seconds() {
        for (from, to) in [(Int64(10), Int64(5)), (Int64(5), Int64(10))] {
            let h = EtaHarness(total: 3000 * mb)
            h.report(0)
            h.feed(seconds: 30, bytesPerSecond: from * mb)
            h.feed(seconds: 45, bytesPerSecond: to * mb)
            XCTAssertEqual(h.etaSeconds, h.exactEta, accuracy: h.exactEta * 0.1, "\(from) -> \(to)")
        }
    }

    func testBurstyRatesAreMeasuredWithTheirDutyCycle() {
        let cases: [(silence: Double, tolerance: Double)] = [(0.4, 0.05), (1.9, 0.10), (4.9, 0.10)]
        for (silence, tolerance) in cases {
            let rates = burstyRates(dataSeconds: 0.6, silenceSeconds: silence, averageRate: 5.0 * Double(mb))
            for rate in rates {
                XCTAssertEqual(rate, 5.0 * Double(mb), accuracy: tolerance * 5.0 * Double(mb), "\(silence)")
            }
        }
    }
}

final class EtaPhaseTests: XCTestCase {
    func testPlannedPhasesAreIncluded() {
        let h = EtaHarness()
        h.eta.planPhases([EtaPhase("join:0", .join, bytes: 1000 * mb)])
        h.report(0)
        h.feed(seconds: 10, bytesPerSecond: 10 * mb)
        // 1000MB בברירת המחדל של 100MB/s = 10 שניות נוספות.
        XCTAssertEqual(h.etaSeconds, h.exactEta + 10, accuracy: h.exactEta * 0.05)
    }

    func testUntrackedPhaseCountsDownToAFewSeconds() {
        let join = EtaPhase("join:0", .join, bytes: 1000 * mb)
        let h = EtaHarness(total: 100 * mb)
        h.eta.planPhases([join])
        h.report(0)
        h.feed(seconds: 10, bytesPerSecond: 10 * mb)
        h.eta.startPhase(join, tracksProgress: false, now: h.now)
        XCTAssertEqual(wholeSeconds(h.read()), 10)
        _ = h.silence(4)
        XCTAssertEqual(wholeSeconds(h.read()), 6)
        _ = h.silence(20)
        XCTAssertEqual(remainingSeconds(h.read()), 0)
    }

    func testTrackedPhaseUsesItsLiveRate() {
        let join = EtaPhase("join:0", .join, bytes: 600 * mb)
        let h = EtaHarness(total: 10 * mb)
        h.eta.planPhases([join])
        h.report(10 * mb)
        h.eta.finishDownload()
        h.eta.startPhase(join, now: h.now)
        // 10MB/s בפועל — איטי פי 10 מברירת המחדל.
        for step in 1...160 {
            h.advance(seconds: 0.25)
            h.eta.phaseProgress(Int64((Double(step) * 2.5).rounded()) * mb)
            _ = h.read()
        }
        // 400MB עובדו מתוך 600 => 20 שניות (פס ההיסטרזיס ±5).
        XCTAssertEqual(h.etaSeconds, 20, accuracy: 5)
    }

    func testInstantPhaseDoesNotInflateTheMeasuredRate() {
        var eta = DownloadEta()
        eta.startPhase(EtaPhase("place:0", .copy, bytes: 500 * mb), now: 10)
        eta.phaseProgress(500 * mb)
        eta.endPhase(now: 10.001)
        eta.startPhase(EtaPhase("place:1", .copy, bytes: 400 * mb), now: 10.001)
        eta.phaseProgress(200 * mb)
        XCTAssertEqual(eta.phaseRate(.copy, now: 12.001), 100_000_000, accuracy: 1)
    }

    func testTextChangesAtMostOncePerSecond() {
        let h = EtaHarness(total: 400 * mb)
        h.report(0)
        h.feed(seconds: 10, bytesPerSecond: 10 * mb)
        let first = h.eta.displayReading(now: h.now)
        h.feed(seconds: 0.5, bytesPerSecond: 100 * mb)
        XCTAssertEqual(h.eta.displayReading(now: h.now), first)
        h.feed(seconds: 1, bytesPerSecond: 100 * mb)
        h.advance(seconds: 1.1)
        XCTAssertNotEqual(h.eta.displayReading(now: h.now), first)
    }

    func testPhasesForActions() {
        let item = DownloadItem(
            name: "a.dmg", size: 500, sha256: "x", url: URL(string: "https://github.com/a")!, caption: "a"
        )
        let actions: [OutputAction] = [
            .place(item),
            .assemble(name: "b", size: 900, sha256: "y", caption: "b", parts: [], folder: ""),
        ]
        XCTAssertEqual(
            EtaPhase.phases(for: actions, placeIsInstant: true),
            [EtaPhase("join:1", .join, bytes: 900), EtaPhase("verify:1", .hash, bytes: 900)]
        )
        XCTAssertEqual(
            EtaPhase.phases(for: actions, placeIsInstant: false),
            [
                EtaPhase("place:0", .copy, bytes: 500), EtaPhase("join:1", .join, bytes: 900),
                EtaPhase("verify:1", .hash, bytes: 900),
            ]
        )
        // הרכבה שנקטעה: רק מה שלא חובר עדיין, וה-hash עדיין על כל הקובץ.
        XCTAssertEqual(
            EtaPhase.phases(for: actions, placeIsInstant: true, alreadyJoined: ["b": 600]),
            [EtaPhase("join:1", .join, bytes: 300), EtaPhase("verify:1", .hash, bytes: 900)]
        )
    }
}

final class EtaCountdownDisplayTests: XCTestCase {
    /// זרימה רציפה: עדכון טרי כל 100ms עם `raw` קבוע, מ-`from` עד `to`.
    private func flow(_ display: inout EtaCountdownDisplay, raw: Double, from: Double, to: Double) -> Double {
        var shown = 0.0
        var t = from
        while t <= to + 1e-9 {
            shown = display.update(raw: raw, time: t, fresh: true)
            t += 0.1
        }
        return shown
    }

    func testSteadyCountdownWithOncePerSecondDataUnderNoise() {
        var display = EtaCountdownDisplay()
        display.update(raw: 300, time: 0, fresh: true)
        var previous = 300.0
        for t in 1...60 {
            let raw = 300.0 - Double(t) + (t % 2 == 0 ? 12 : -12)
            let shown = display.update(raw: raw, time: Double(t), fresh: true)
            XCTAssertLessThanOrEqual(shown, previous)
            XCTAssertEqual(shown, 300.0 - Double(t), accuracy: 2)
            previous = shown
        }
    }

    func testContinuousFlowRisesSlowlyAndFallsFast() {
        var same = EtaCountdownDisplay()
        var up = EtaCountdownDisplay()
        var down = EtaCountdownDisplay()
        _ = flow(&same, raw: 100, from: 0, to: 3)
        _ = flow(&up, raw: 100, from: 0, to: 3)
        _ = flow(&down, raw: 100, from: 0, to: 3)
        let base = flow(&same, raw: 100, from: 3.1, to: 5)
        let rose = flow(&up, raw: 150, from: 3.1, to: 5) - base
        let fell = base - flow(&down, raw: 50, from: 3.1, to: 5)
        XCTAssertGreaterThan(rose, 0)
        XCTAssertLessThan(rose, 50 * 0.2)
        XCTAssertGreaterThan(fell, rose * 2)
    }

    func testDropBelowHalfIsShownAtTheNextCorrectionPoint() {
        var display = EtaCountdownDisplay()
        _ = flow(&display, raw: 100, from: 0, to: 3)
        XCTAssertEqual(display.update(raw: 30, time: 3.1, fresh: true), 30, accuracy: 1e-9)
    }

    func testEndOfRunCorrectsToTheLastDataSample() {
        var display = EtaCountdownDisplay()
        display.update(raw: 100, time: 0, fresh: true)
        display.update(raw: 30, time: 0.5, fresh: true)
        // פחות משנייה של שקט — עדיין לא סוף פרץ.
        XCTAssertEqual(display.update(raw: 500, time: 1, fresh: false), 99, accuracy: 1e-9)
        // שנייה של שקט: ירידה לפחות ממחצית — לפי 30 של הדגימה האחרונה.
        XCTAssertEqual(display.update(raw: 500, time: 1.5, fresh: false), 30, accuracy: 1e-9)
        XCTAssertEqual(display.update(raw: 500, time: 2.5, fresh: false), 29, accuracy: 1e-9)
    }

    func testWithoutACorrectionPointOnlyCountsDown() {
        var display = EtaCountdownDisplay()
        display.update(raw: 100, time: 0, fresh: true)
        // פחות משנייה בין דגימות — עוד אין סוף פרץ או שתי שניות של זרימה.
        XCTAssertEqual(display.update(raw: 200, time: 0.9, fresh: true), 99.1)
    }
}

final class EtaScenarioTests: XCTestCase {
    func testOncePerSecondRateChangesAcrossTimerPhases() {
        for phase in [0.0, 0.05, 0.95] {
            for (from, to): (Int64, Int64) in [(5, 1), (1, 5)] {
                var eta = DownloadEta()
                let total = 2000 * mb
                var bytes: Int64 = 0
                eta.report(receivedBytes: 0, remainingBytes: total, now: 0)
                for second in 1...400 {
                    bytes += (second <= 20 ? from : to) * mb
                    eta.report(receivedBytes: bytes, remainingBytes: total - bytes, now: Double(second))
                    _ = eta.read(now: Double(second))
                    let reading = eta.read(now: Double(second) + phase)
                    if second >= 120 {
                        guard case .remaining(let shown) = reading else {
                            XCTFail("Expected an estimate")
                            return
                        }
                        let expected = Double(total - bytes) / Double(to * mb)
                        XCTAssertEqual(shown, expected, accuracy: expected * 0.15)
                    }
                }
            }
        }
    }

    func testSteady3GBAt5MBpsWithNoise() {
        let run = simulate(steadyChunks(totalBytes: 3000 * mb, rate: 5 * mb, jitter: 0.4))
        XCTAssertEqual(run.textIncreases(), 0)
        XCTAssertLessThan(run.maxError(from: 10), 0.10)
    }

    func testBursty06On49Off() {
        let run = simulate(burstyChunks(offSeconds: [4.9]))
        XCTAssertLessThan(run.maxError(from: (run.firstShownT ?? 0) + 20), 0.15)
    }

    func testBursty06On19Off() {
        let run = simulate(burstyChunks(offSeconds: [1.9]))
        XCTAssertLessThan(run.maxError(from: (run.firstShownT ?? 0) + 20), 0.10)
    }

    func testBursty06On20OffFirstEstimateAndFewIncreases() {
        let run = simulate(burstyChunks(offSeconds: [2.0]))
        XCTAssertLessThan(run.firstError, 0.20)
        XCTAssertLessThanOrEqual(run.textIncreases(until: 120), 3)
    }

    func testBursty3On49OffFewIncreases() {
        let run = simulate(burstyChunks(offSeconds: [4.9], onChunks: 30))
        XCTAssertLessThanOrEqual(run.textIncreases(until: 120), 3)
    }

    func testRecurringLongSilences() {
        for off in [6.0, 9.0] {
            let run = simulate(burstyChunks(offSeconds: [off]))
            XCTAssertLessThan(run.maxError(from: 60), 0.15, "\(off)")
        }
    }

    func testSilencesAroundFiveSeconds() {
        let run = simulate(burstyChunks(offSeconds: [4.8, 5.1, 4.9, 5.3]))
        XCTAssertLessThan(run.maxError(from: 60), 0.15)
    }

    func testRateChangeWithinTenPercentAfter45Seconds() {
        for (from, to) in [(Int64(10), Int64(5)), (Int64(5), Int64(10))] {
            let run = simulate(segmentChunks([(30, from * mb), (100_000, to * mb)], totalBytes: 3000 * mb))
            XCTAssertLessThan(run.errorAt(75), 0.10, "\(from) -> \(to)")
        }
    }

    func testIsolatedTwelveSecondStall() {
        let run = simulate(segmentChunks([(20, 10 * mb), (12, 0), (100_000, 10 * mb)], totalBytes: 2000 * mb))
        for record in run.records where record.t > 32 {
            guard let shown = record.shown else { continue }
            XCTAssertLessThanOrEqual(shown, (run.tEnd - record.t + 12) * 1.1, "\(record.t)")
        }
    }

    func testFortyFiveSecondStall() {
        let run = simulate(segmentChunks([(20, 10 * mb), (45, 0), (100_000, 10 * mb)], totalBytes: 2000 * mb))
        let after = run.records.filter { $0.t > 65.05 }
        XCTAssertEqual(after.first?.reading, .calculating)
        guard let reappeared = after.first(where: { $0.shown != nil }) else {
            return XCTFail("no estimate after the stall")
        }
        XCTAssertLessThan(run.error(reappeared), 0.15)
    }
}

final class LocationTests: XCTestCase {
    func testTranslocatedAppFallsBackToDocuments() {
        let fallback = URL(fileURLWithPath: "/Users/u/Documents/אוצריא-להתקנה")
        let translocated = URL(fileURLWithPath:
            "/private/var/folders/x/T/AppTranslocation/ABC/d/Otzaria-Download-Assistant.app")
        let result = OutputLocation.defaultBase(bundleURL: translocated, fallback: fallback, isWritable: { _ in true })
        XCTAssertEqual(result.url, fallback)
        XCTAssertTrue(result.usedFallback)
    }

    func testDefaultIsTheFolderContainingTheApp() {
        let app = URL(fileURLWithPath: "/Users/u/Downloads/Otzaria-Download-Assistant.app")
        let result = OutputLocation.defaultBase(
            bundleURL: app, fallback: URL(fileURLWithPath: "/tmp/f"), isWritable: { _ in true }
        )
        XCTAssertEqual(result.url.path, "/Users/u/Downloads")
        XCTAssertFalse(result.usedFallback)
        let readOnly = OutputLocation.defaultBase(
            bundleURL: app, fallback: URL(fileURLWithPath: "/tmp/f"), isWritable: { _ in false }
        )
        XCTAssertTrue(readOnly.usedFallback)
    }

    func testSubfolderNames() {
        XCTAssertEqual(outputSubfolderName("linux"), "אוצריא להתקנה ל-Linux")
        XCTAssertEqual(joinCommand(assetName: "a.tar.zst"), "cat 'a.tar.zst'.part-* > 'a.tar.zst'")
    }
}
