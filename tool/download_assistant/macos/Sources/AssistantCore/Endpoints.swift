import Foundation

/// כתובות ההורדה והמארחים המותרים. אין URL חופשי: כל כתובת נבנית מ-repository+tag+name.
public enum Endpoints {
    public static let userAgent = "Otzaria-Download-Assistant-macOS"
    public static let releasesPage = URL(string: "https://github.com/Otzaria/otzaria/releases/latest")!

    public static let allowedHosts: Set<String> = [
        "github.com",
        "api.github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    ]

    /// תג או שם נכס: `^[A-Za-z0-9._+-]+$`, ולא "." או "..", שהיו משנים את הנתיב.
    public static func isSafeName(_ value: String) -> Bool {
        guard !value.isEmpty, value != ".", value != ".." else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            isAsciiAlphanumeric(scalar) || "._+-".unicodeScalars.contains(scalar)
        }
    }

    /// `^Otzaria/[A-Za-z0-9._-]+$` — מאגר בארגון Otzaria בלבד.
    public static func isOtzariaRepository(_ repository: String) -> Bool {
        let prefix = "Otzaria/"
        guard repository.hasPrefix(prefix) else { return false }
        let repo = String(repository.dropFirst(prefix.count))
        guard !repo.isEmpty, repo != ".", repo != ".." else { return false }
        return repo.unicodeScalars.allSatisfy { scalar in
            isAsciiAlphanumeric(scalar) || "._-".unicodeScalars.contains(scalar)
        }
    }

    public static func assetURL(repository: String, tag: String, name: String) -> URL? {
        guard isOtzariaRepository(repository), isSafeName(tag), isSafeName(name) else { return nil }
        // ה-`+` שבתג הוא תו חוקי בנתיב ונשאר כפי שהוא.
        return URL(string: "https://github.com/\(repository)/releases/download/\(tag)/\(name)")
    }

    /// `latest` או `tags/<tag>` ב-API של המאגר הראשי.
    public static func releaseApiURL(latest: Bool, tag: String = "") -> URL? {
        if latest {
            return URL(string: "https://api.github.com/repos/Otzaria/otzaria/releases/latest")
        }
        guard isSafeName(tag) else { return nil }
        return URL(string: "https://api.github.com/repos/Otzaria/otzaria/releases/tags/\(tag)")
    }

    /// נבדק על הכתובת ההתחלתית ועל כל הפניה: https בלבד, מארח מהרשימה, וב-github.com רק תחת /Otzaria/.
    public static func isAllowed(_ url: URL?) -> Bool {
        guard let url = url,
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              allowedHosts.contains(host),
              url.user == nil, url.password == nil
        else { return false }
        if let port = url.port, port != 443 { return false }
        if host == "github.com" {
            return url.path.hasPrefix("/Otzaria/")
                && !url.path.components(separatedBy: "/").contains("..")
        }
        return true
    }

    private static func isAsciiAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true
        default: return false
        }
    }
}

/// בחירת התג של הריצה: התג המוטבע, אלא אם /releases/latest מצביע על X.Y.Z גבוה יותר.
public enum ReleaseTagChoice {
    /// החלק X.Y.Z. סיומת `+build` אינה משתתפת: סדר מספרי ה-run אינו סדר גרסאות.
    public static func versionPart(_ tag: String) -> String {
        var result = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if let plus = result.firstIndex(of: "+") {
            result = String(result[..<plus])
        }
        if result.hasPrefix("v") || result.hasPrefix("V") {
            result = String(result.dropFirst())
        }
        return result
    }

    /// 1 אם a גבוה מ-b, -1 אם נמוך, 0 אם שווה.
    public static func compare(_ a: String, _ b: String) -> Int {
        let pa = versionPart(a).split(separator: ".").map { Int64($0) ?? 0 }
        let pb = versionPart(b).split(separator: ".").map { Int64($0) ?? 0 }
        for index in 0..<max(pa.count, pb.count) {
            let va = index < pa.count ? pa[index] : 0
            let vb = index < pb.count ? pb[index] : 0
            if va > vb { return 1 }
            if va < vb { return -1 }
        }
        return 0
    }

    /// nil = אין תג כלל (בנייה מקומית ו-latest לא זמין). תג latest שאינו בטוח לנתיב נחשב חסר.
    public static func choose(embedded: String, latest: String?) -> String? {
        let embeddedTag = embedded.trimmingCharacters(in: .whitespacesAndNewlines)
        var latestTag = latest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !Endpoints.isSafeName(latestTag) { latestTag = "" }
        if embeddedTag.isEmpty {
            return latestTag.isEmpty ? nil : latestTag
        }
        if !latestTag.isEmpty && compare(latestTag, embeddedTag) > 0 {
            return latestTag
        }
        return embeddedTag
    }
}
