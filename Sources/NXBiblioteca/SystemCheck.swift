import Foundation

struct CheckItem: Identifiable {
    enum Status { case ok, warning, error }
    let id = UUID()
    let title: String
    let status: Status
    let detail: String
    var fix: String? = nil
    /// Stable name for the diagnostics (macos, arch, xcode, metal, repo, python, pylibs, tool.<name>, keys, library).
    var key = ""
}

enum Shell {
    static func run(_ exe: String, _ args: [String]) async -> (status: Int32, output: String) {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            p.environment = OndiPaths.environment()
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            do { try p.run() } catch { return (-1, error.localizedDescription) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }.value
    }
}

/// What nxnative's README asks for, checked one by one.
enum SystemChecker {
    static func run(_ paths: SystemPaths) async -> [CheckItem] {
        let fm = FileManager.default
        var items: [CheckItem] = []

        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osText = "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let osOK = os.majorVersion > 26 || (os.majorVersion == 26 && os.minorVersion >= 6)
        items.append(CheckItem(title: String(localized: "macOS 26.6 o más nuevo"), status: osOK ? .ok : .error, detail: osText,
                               fix: osOK ? nil : String(localized: "Ajustes del Sistema → General → Actualización de software"), key: "macos"))

        var arch = utsname()
        uname(&arch)
        let machine = withUnsafeBytes(of: &arch.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        items.append(CheckItem(title: String(localized: "Mac con Apple silicon"), status: machine == "arm64" ? .ok : .error, detail: machine, key: "arch"))

        let xcode = await Shell.run("/usr/bin/xcodebuild", ["-version"])
        if xcode.status != 0 {
            items.append(CheckItem(title: "Xcode 27.1", status: .error, detail: String(localized: "Xcode no está instalado o no está seleccionado."),
                                   fix: "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer", key: "xcode"))
        } else {
            let line = xcode.output.components(separatedBy: "\n").first ?? xcode.output
            let exact = line.trimmingCharacters(in: .whitespaces) == "Xcode 27.1"
            items.append(CheckItem(
                title: "Xcode 27.1", status: exact ? .ok : .warning,
                detail: exact ? line : String(localized: "\(line). Los shaders están probados con Xcode 27.1 y la compilación se detiene con otra versión. Instala la 27.1 desde developer.apple.com/download o activa “Permitir otro compilador Metal” en Ajustes (puede haber gráficos corruptos).")
            , key: "xcode"))
            // `xcrun --find` succeeds even without the toolchain; running the compiler is the real test.
            let metal = await Shell.run("/usr/bin/xcrun", ["-sdk", "macosx", "metal", "-v"])
            items.append(CheckItem(title: "Metal Toolchain", status: metal.status == 0 ? .ok : .error,
                                   detail: metal.status == 0 ? (metal.output.components(separatedBy: "\n").first ?? String(localized: "Instalado")) : String(localized: "No está descargado (Xcode lo instala aparte)."),
                                   fix: metal.status == 0 ? nil : "xcodebuild -downloadComponent MetalToolchain", key: "metal"))
        }

        let hasRepo = fm.fileExists(atPath: paths.script.path)
        items.append(CheckItem(title: String(localized: "Motor de juegos"), status: hasRepo ? .ok : .error, detail: paths.repo.path,
                               fix: hasRepo ? nil : "git clone https://github.com/seedds/nxnative.git ~/nxnative", key: "repo"))

        if fm.isExecutableFile(atPath: paths.python.path) {
            let v = await Shell.run(paths.python.path, ["--version"])
            let nums = v.output.replacingOccurrences(of: "Python ", with: "").split(separator: ".").compactMap { Int($0) }
            let ok = nums.count >= 2 && (nums[0] > 3 || (nums[0] == 3 && nums[1] >= 12))
            items.append(CheckItem(title: String(localized: "Python 3.12 o más nuevo"), status: ok ? .ok : .error, detail: v.output, key: "python"))
            let mods = await Shell.run(paths.python.path, ["-c", "import lz4, capstone, fontTools"])
            items.append(CheckItem(title: String(localized: "Librerías de Python (lz4, capstone, fonttools)"), status: mods.status == 0 ? .ok : .error,
                                   detail: mods.status == 0 ? String(localized: "Instaladas") : (mods.output.components(separatedBy: "\n").last ?? ""),
                                   fix: mods.status == 0 ? nil : "~/nxnative-setup.sh", key: "pylibs"))
        } else {
            items.append(CheckItem(title: String(localized: "Python 3.12 o más nuevo"), status: .error, detail: String(localized: "No existe \(paths.python.path)"),
                                   fix: "~/nxnative-setup.sh", key: "python"))
        }

        let dirs = [OndiPaths.bin.path, OndiPaths.dotnet.path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/local/share/dotnet"]
        for tool in ["xcodegen", "zstd", "glslangValidator", "dotnet"] {
            let found = dirs.map { "\($0)/\(tool)" }.first { fm.isExecutableFile(atPath: $0) }
            let formula = tool == "glslangValidator" ? "glslang" : tool == "dotnet" ? "--cask dotnet-sdk" : tool
            items.append(CheckItem(title: tool, status: found != nil ? .ok : .error, detail: found ?? String(localized: "No instalado"),
                                   fix: found != nil ? nil : "brew install \(formula)", key: "tool.\(tool)"))
        }

        var keySize = (try? fm.attributesOfItem(atPath: paths.keys.path)[.size] as? Int) ?? nil
        if (keySize ?? 0) > 0, let text = try? String(contentsOf: paths.keys, encoding: .utf8) {
            let names = Set(text.split(separator: "\n").compactMap { $0.split(separator: "=").first?.trimmingCharacters(in: .whitespaces) })
            let missing = ["header_key", "master_key_00"].filter { !names.contains($0) }
            if !missing.isEmpty {
                items.append(CheckItem(title: "prod.keys", status: .error,
                                       detail: String(localized: "El archivo no tiene las claves \(missing.joined(separator: ", ")). Puede estar incompleto o no ser un prod.keys."),
                                       fix: String(localized: "Vuelve a sacarlas de tu consola con Lockpick_RCM."), key: "keys"))
                keySize = nil
            }
        }
        if !items.contains(where: { $0.key == "keys" }) {
            let found = (keySize ?? 0) > 0
            items.append(CheckItem(
                title: "prod.keys", status: found ? .ok : .error,
                detail: found ? String(localized: "Encontradas en \(paths.keys.path) (solo se comprueban los nombres de las claves)") : String(localized: "No hay archivo en \(paths.keys.path)"),
                fix: found ? nil : String(localized: "Sácalas de tu consola con Lockpick_RCM y cópialas ahí."),
                key: "keys"
            ))
        }

        var isDir: ObjCBool = false
        let libOK = fm.fileExists(atPath: paths.library.path, isDirectory: &isDir) && isDir.boolValue
        items.append(CheckItem(title: String(localized: "Carpeta de la biblioteca"), status: libOK ? .ok : .warning, detail: paths.library.path, key: "library"))

        return items
    }
}
