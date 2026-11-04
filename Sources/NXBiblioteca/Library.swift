import Foundation

/// Reads what a game file is without keys: the PFS0 header of an NSP/NSZ
/// (its cnmt.xml or ticket names), falling back to the `[TitleID][vN]` filename tags.
enum ContentReader {
    static let extensions: Set<String> = ["nsp", "nsz", "xci", "xcz"]

    static func isContent(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }

    static func read(_ url: URL) -> ContentInfo {
        var tid: TitleID?
        var version: UInt32?
        var typeHint: ContentKind?
        let ext = url.pathExtension.lowercased()

        if ext == "nsp" || ext == "nsz", let pfs = readPFS0(url) {
            if let xml = pfs.cnmtXML {
                tid = firstMatch(#"<Id>0x([0-9a-fA-F]{16})</Id>"#, in: xml).flatMap { TitleID(hex: $0) }
                version = firstMatch(#"<Version>(\d+)</Version>"#, in: xml).flatMap { UInt32($0) }
                switch firstMatch(#"<Type>(\w+)</Type>"#, in: xml) {
                case "Application": typeHint = .base
                case "Patch": typeHint = .update
                case "AddOnContent": typeHint = .dlc
                default: break
                }
            }
            if tid == nil, let tik = pfs.names.first(where: { $0.lowercased().hasSuffix(".tik") }), tik.count >= 16 {
                tid = TitleID(hex: String(tik.prefix(16)))
            }
        }

        let name = url.lastPathComponent
        if tid == nil { tid = firstMatch(#"\[([0-9a-fA-F]{16})\]"#, in: name).flatMap { TitleID(hex: $0) } }
        if version == nil { version = firstMatch(#"\[v(\d+)\]"#, in: name).flatMap { UInt32($0) } }
        let kind = typeHint ?? tid?.kind ?? (ext.hasPrefix("xc") ? .base : .unknown)
        return ContentInfo(titleID: tid, version: version, kind: kind)
    }

    /// Folder-friendly name from a dump's filename: drops `[..]` and `(..)` tags.
    static func cleanName(_ url: URL) -> String {
        let raw = url.deletingPathExtension().lastPathComponent
        let stripped = raw
            .replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
        let words = stripped.split(whereSeparator: { $0.isWhitespace })
        return words.isEmpty ? raw : words.joined(separator: " ")
    }

    static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    private struct PFS0 {
        var names: [String]
        var cnmtXML: String?
    }

    private static func readPFS0(_ url: URL) -> PFS0? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        guard let header = try? fh.read(upToCount: 16), header.count == 16,
              header.prefix(4) == Data("PFS0".utf8) else { return nil }
        let count = Int(header.u32(4)), tableSize = Int(header.u32(8))
        guard count > 0, count < 4096, tableSize < 1 << 20,
              let entries = try? fh.read(upToCount: count * 24), entries.count == count * 24,
              let table = try? fh.read(upToCount: tableSize), table.count == tableSize else { return nil }

        let dataStart = UInt64(16 + count * 24 + tableSize)
        var names: [String] = []
        var xml: String?
        for i in 0..<count {
            let e = entries.subdata(in: i * 24 ..< i * 24 + 24)
            let offset = e.u64(0), size = e.u64(8), nameOffset = Int(e.u32(16))
            guard nameOffset < table.count else { continue }
            let rest = table[table.startIndex + nameOffset ..< table.endIndex]
            let end = rest.firstIndex(of: 0) ?? rest.endIndex
            let name = String(decoding: rest[rest.startIndex ..< end], as: UTF8.self)
            names.append(name)
            if name.hasSuffix(".cnmt.xml"), size < 1 << 20 {
                try? fh.seek(toOffset: dataStart + offset)
                if let d = try? fh.read(upToCount: Int(size)) { xml = String(decoding: d, as: UTF8.self) }
            }
        }
        return PFS0(names: names, cnmtXML: xml)
    }
}

private extension Data {
    func u32(_ o: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(self[startIndex + o + $1]) << (8 * $1) }
    }
    func u64(_ o: Int) -> UInt64 {
        (0..<8).reduce(0) { $0 | UInt64(self[startIndex + o + $1]) << (8 * $1) }
    }
}

/// Games nxnative has a profile for: `dm/games/<title ID>/game.tsv`.
enum Catalog {
    static func load(repo: URL) -> [TitleID: String] {
        let dir = repo.appendingPathComponent("dm/games")
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [:] }
        var out: [TitleID: String] = [:]
        for item in items {
            guard let tid = TitleID(hex: item.lastPathComponent) else { continue }
            var name = item.lastPathComponent
            if let text = try? String(contentsOf: item.appendingPathComponent("game.tsv"), encoding: .utf8),
               let line = text.split(separator: "\n").first(where: { $0.hasPrefix("name\t") }) {
                name = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            }
            out[tid] = name
        }
        return out
    }
}

extension Catalog {
    /// Each profile's tested version: `package\tv1114112` in game.tsv, its name from the header
    /// ("… + update 1.9.0 = v1114112").
    static func loadTested(repo: URL) -> [TitleID: TestedVersion] {
        let dir = repo.appendingPathComponent("dm/games")
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [:] }
        var out: [TitleID: TestedVersion] = [:]
        for item in items {
            guard let tid = TitleID(hex: item.lastPathComponent),
                  let text = try? String(contentsOf: item.appendingPathComponent("game.tsv"), encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n")
            guard let pkgLine = lines.first(where: { $0.hasPrefix("package\t") }),
                  let pkg = UInt32(pkgLine.dropFirst(8).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "v", with: "")) else { continue }
            let header = String(lines.first ?? "")
            let label = ContentReader.firstMatch(#"update ([0-9][0-9.]*[0-9])"#, in: header)
            out[tid] = TestedVersion(package: pkg, label: pkg == 0 ? nil : label)
        }
        return out
    }
}

/// One subfolder of the library per game, as the build script expects.
enum LibraryScanner {
    static let backupFolderName = "_Respaldos"

    static func scan(root: URL, catalog: [TitleID: String], tested: [TitleID: TestedVersion] = [:]) -> [Game] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return dirs
            .filter { isDirectory($0) && $0.pathExtension != "app" && $0.lastPathComponent != backupFolderName }
            .compactMap { scanGame($0, catalog: catalog, tested: tested) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func scanGame(_ dir: URL, catalog: [TitleID: String], tested: [TitleID: TestedVersion] = [:]) -> Game? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .addedToDirectoryDateKey], options: [.skipsHiddenFiles]) else { return nil }

        var files: [GameFile] = []
        for url in items where ContentReader.isContent(url) {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .addedToDirectoryDateKey])
            files.append(GameFile(url: url, size: Int64(values?.fileSize ?? 0), info: ContentReader.read(url), added: values?.addedToDirectoryDate))
        }
        files.sort(by: fileOrder)
        let apps = items.filter { $0.pathExtension == "app" }.compactMap(BuiltApp.read)
        guard !files.isEmpty || !apps.isEmpty else { return nil }

        let baseFile: GameFile? = files.first { $0.info.kind == .base }
        let anyFileBase: TitleID? = files.compactMap { $0.info.titleID?.base }.first
        let appTitle: TitleID? = apps.compactMap { app -> TitleID? in app.titleID.flatMap { TitleID(hex: $0) } }.first
        let tid: TitleID? = baseFile?.info.titleID ?? anyFileBase ?? appTitle
        let app = apps.first { $0.titleID?.uppercased() == tid?.description } ?? apps.first

        var buildFolder: URL?
        var cover: URL?
        if let tid {
            buildFolder = ["\(tid)_build", "\(tid.description.lowercased())_build"]
                .map { dir.appendingPathComponent($0) }
                .first { fm.fileExists(atPath: $0.path) }
            if let buildFolder,
               let versions = try? fm.contentsOfDirectory(at: buildFolder.appendingPathComponent("extract"), includingPropertiesForKeys: nil) {
                cover = versions.map { $0.appendingPathComponent("icon.jpg") }.first { fm.fileExists(atPath: $0.path) }
            }
        }

        return Game(
            folder: dir,
            name: app?.displayName ?? tid.flatMap { catalog[$0] } ?? dir.lastPathComponent,
            titleID: tid,
            files: files,
            app: app,
            coverURL: cover,
            hasProfile: tid.map { catalog[$0] != nil } ?? false,
            buildFolder: buildFolder,
            tested: tid.flatMap { tested[$0] }
        )
    }

    private static func fileOrder(_ a: GameFile, _ b: GameFile) -> Bool {
        if a.info.kind.sortOrder != b.info.kind.sortOrder { return a.info.kind.sortOrder < b.info.kind.sortOrder }
        let va = a.info.version ?? 0, vb = b.info.version ?? 0
        if va != vb { return va < vb }
        return a.url.lastPathComponent < b.url.lastPathComponent
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
}

/// Copies dumps into the library, one folder per base game (APFS clones on the same disk).
enum Importer {
    struct Result {
        var copied = 0
        var skipped = 0
        var errors: [String] = []
    }

    static func run(_ urls: [URL], root: URL, catalog: [TitleID: String], existing: [Game]) -> Result {
        let fm = FileManager.default
        var result = Result()
        var files: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let inner = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                files += inner.filter(ContentReader.isContent)
            } else if ContentReader.isContent(url) {
                files.append(url)
            } else {
                result.errors.append(String(localized: "\(url.lastPathComponent): formato no compatible (usa NSP, XCI, NSZ o XCZ)."))
            }
        }

        var folders: [TitleID: URL] = [:]
        for g in existing { if let t = g.titleID { folders[t] = g.folder } }

        // Base games first, so updates and DLC land in the base game's folder.
        let items = files.map { ($0, ContentReader.read($0)) }.sorted { $0.1.kind.sortOrder < $1.1.kind.sortOrder }
        for (url, info) in items {
            let base = info.titleID?.base
            let folder: URL
            if let base, let known = folders[base] {
                folder = known
            } else {
                let name = base.flatMap { catalog[$0] } ?? ContentReader.cleanName(url)
                folder = root.appendingPathComponent(sanitize(name), isDirectory: true)
                if let base { folders[base] = folder }
            }
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let dest = folder.appendingPathComponent(url.lastPathComponent)
                if url.standardizedFileURL == dest.standardizedFileURL || fm.fileExists(atPath: dest.path) {
                    result.skipped += 1
                    continue
                }
                try fm.copyItem(at: url, to: dest)
                result.copied += 1
            } catch {
                result.errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return result
    }

    static func sanitize(_ name: String) -> String {
        let s = name.replacingOccurrences(of: ":", with: " -").replacingOccurrences(of: "/", with: "-")
        return s.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
    }
}
