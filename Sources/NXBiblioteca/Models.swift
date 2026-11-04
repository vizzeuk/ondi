import Foundation

enum ContentKind: String, Hashable {
    case base, update, dlc, unknown

    var label: String {
        switch self {
        case .base: return String(localized: "Base")
        case .update: return String(localized: "Actualización")
        case .dlc: return "DLC"
        case .unknown: return String(localized: "Desconocido")
        }
    }

    var sortOrder: Int {
        switch self {
        case .base: return 0
        case .update: return 1
        case .dlc: return 2
        case .unknown: return 3
        }
    }
}

/// A Switch title ID. The low 12 bits say what the content is:
/// 000 = base game, 800 = update, anything else = DLC (base + 0x1000 + n).
struct TitleID: Hashable, Comparable, CustomStringConvertible {
    let value: UInt64

    init(_ value: UInt64) { self.value = value }

    init?(hex: String) {
        guard hex.count == 16, let v = UInt64(hex, radix: 16) else { return nil }
        value = v
    }

    var description: String { String(format: "%016llX", value) }

    var kind: ContentKind {
        switch value & 0xFFF {
        case 0: return .base
        case 0x800: return .update
        default: return .dlc
        }
    }

    var base: TitleID {
        switch kind {
        case .dlc: return TitleID((value &- 0x1000) & ~UInt64(0xFFF))
        default: return TitleID(value & ~UInt64(0xFFF))
        }
    }

    static func < (a: TitleID, b: TitleID) -> Bool { a.value < b.value }
}

struct ContentInfo: Hashable {
    var titleID: TitleID?
    var version: UInt32?
    var kind: ContentKind
}

struct GameFile: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let info: ContentInfo
    /// When the file was put in the game's folder.
    var added: Date? = nil

    var versionLabel: String? { info.version.map { "v\($0)" } }
}

/// A Mac app made by `build_ipa_from_nsp.py --platform mac-app`.
struct BuiltApp: Hashable {
    let url: URL
    let titleID: String?
    let bundleID: String
    let displayName: String?
    let version: String?
    let hasIcon: Bool

    var launcherJSON: URL { url.appendingPathComponent("Contents/Resources/dm/launcher.json") }

    static func read(_ url: URL) -> BuiltApp? {
        guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else { return nil }
        let tid = info["DMTitleID"] as? String
        let bundle = info["CFBundleIdentifier"] as? String ?? ""
        guard tid != nil || bundle.hasPrefix("org.nxnative.") else { return nil }
        return BuiltApp(
            url: url,
            titleID: tid,
            bundleID: bundle.isEmpty ? "org.nxnative.\((tid ?? "").lowercased())" : bundle,
            displayName: (info["CFBundleDisplayName"] ?? info["CFBundleName"]) as? String,
            version: info["CFBundleShortVersionString"] as? String,
            hasIcon: info["CFBundleIconFile"] != nil || info["CFBundleIconName"] != nil
        )
    }
}

struct Game: Identifiable, Hashable {
    enum Status { case ready, toBuild, missingBase }

    var id: String { folder.path }
    let folder: URL
    var name: String
    var titleID: TitleID?
    var files: [GameFile]
    var app: BuiltApp?
    var coverURL: URL?
    var hasProfile: Bool
    var buildFolder: URL?
    /// The version nxnative tested this game with (its profile's `package`).
    var tested: TestedVersion? = nil

    var hasBase: Bool { files.contains { $0.info.kind == .base } }
    /// This game's updates, newest first (files of another game are left out).
    var updates: [GameFile] {
        files.filter { $0.info.kind == .update && ($0.info.titleID?.base == titleID || titleID == nil) }
            .sorted { ($0.info.version ?? 0) > ($1.info.version ?? 0) }
    }
    var dlcs: [GameFile] { files.filter { $0.info.kind == .dlc && ($0.info.titleID?.base == titleID || titleID == nil) } }
    var hasTestedVersion: Bool {
        guard let t = tested else { return true }
        return t.package == 0 || updates.contains { $0.info.version == t.package }
    }
    /// When the Mac app was built (its Info.plist's date).
    var builtAt: Date? {
        app.flatMap { try? $0.url.appendingPathComponent("Contents/Info.plist").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
    }
    /// Updates or DLC added after the app was built: not in the app until it is rebuilt.
    var contentAddedAfterBuild: [GameFile] {
        guard let built = builtAt else { return [] }
        return (updates + dlcs).filter { ($0.added ?? .distantPast) > built }
    }
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
    var dlcCount: Int { files.filter { $0.info.kind == .dlc }.count }
    var latestUpdate: GameFile? {
        files.filter { $0.info.kind == .update }.max { ($0.info.version ?? 0) < ($1.info.version ?? 0) }
    }

    var status: Status {
        if app != nil { return .ready }
        return hasBase ? .toBuild : .missingBase
    }

    /// Key for this app's own preferences (favorites, chosen version): stays the same before and after a build.
    var stableKey: String { titleID?.description ?? id }

    /// The title ID as nxnative writes it in its folders.
    var dataTitleID: String { app?.titleID ?? titleID?.description ?? "" }

    var supportFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/nxnative/\(dataTitleID)")
    }
    var saveFolder: URL { supportFolder.appendingPathComponent("save") }
    var logFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/nxnative/\(dataTitleID).log")
    }

    /// Stable number for placeholder colours.
    var colorSeed: UInt64 {
        if let titleID { return titleID.value >> 12 }
        var h: UInt64 = 0xcbf29ce484222325
        for b in name.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }
}

struct TestedVersion: Hashable {
    let package: UInt32
    /// The update's own number ("1.9.0"), from the profile's header.
    let label: String?

    var text: String {
        if package == 0 { return String(localized: "el juego base, sin actualización") }
        return label.map { String(localized: "la actualización \($0) (v\(package))") } ?? String(localized: "la versión v\(package)")
    }
}

extension Int64 {
    var byteString: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
