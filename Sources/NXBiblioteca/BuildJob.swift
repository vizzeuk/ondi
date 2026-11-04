import Foundation
import Observation

enum BuildPhase: Equatable {
    case running, succeeded, failed(String), cancelled
}

struct LogLine: Identifiable {
    enum Level { case info, error, stderr }
    let id: Int
    let text: String
    let level: Level
}

/// One run of `build_ipa_from_nsp.py --progress json` (docs/frontends.md, "Building: the NSP script").
@Observable @MainActor
final class BuildJob {
    let gameID: String
    let startedAt = Date()
    private(set) var phase: BuildPhase = .running
    private(set) var stageIndex = 0
    private(set) var stageCount = 0
    private(set) var stageName = "Preparando…"
    private(set) var stepName = ""
    private(set) var stageFraction: Double?
    private(set) var eta: Double?
    private(set) var detail = ""
    private(set) var log: [LogLine] = []

    @ObservationIgnored var onFinish: ((BuildJob) -> Void)?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var exitStatus: Int32?
    @ObservationIgnored private var closedStreams = 0
    @ObservationIgnored private var lastRed: String?
    @ObservationIgnored private var stderrTail: [String] = []
    @ObservationIgnored private var cancelRequested = false
    @ObservationIgnored private var nextLineID = 0
    /// The script's tools when a stop was asked, so the ones still alive after it exits are stopped too.
    @ObservationIgnored private var toolsAtCancel: [pid_t] = []

    init(gameID: String) { self.gameID = gameID }

    var isRunning: Bool { phase == .running }

    /// The build script's process, while it runs.
    var scriptPID: pid_t? { process.map(\.processIdentifier).flatMap { $0 > 0 ? $0 : nil } }

    var overallFraction: Double? {
        guard stageCount > 0, stageIndex > 0 else { return nil }
        return min(1, (Double(stageIndex - 1) + (stageFraction ?? 0)) / Double(stageCount))
    }

    func start(executable: URL, arguments: [String], workingDirectory: URL) throws {
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        p.currentDirectoryURL = workingDirectory
        // Apps opened from Finder don't get the shell's PATH: Ondi's own tools first, then Homebrew's and dotnet's.
        var env = OndiPaths.environment()
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env

        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        attach(out.fileHandleForReading, isStderr: false)
        attach(err.fileHandleForReading, isStderr: true)
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.exitStatus = status
                    self?.finishIfDone()
                }
            }
        }

        append("$ \(executable.path) \(arguments.joined(separator: " "))", .info)
        try p.run()
        process = p
    }

    /// SIGINT lets the script stop its current tool and exit (it keeps finished stages: each one writes into a `.partial`
    /// folder and swaps it in at the end). Tools it did not stop are stopped once it exits, everything after 15 s.
    func cancel() {
        guard isRunning, let p = process else { return }
        cancelRequested = true
        let pid = p.processIdentifier
        toolsAtCancel = ProcessTree.descendants(of: pid)
        p.interrupt()
        append("Cancelando…", .info)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15) { [tools = toolsAtCancel] in
            guard ProcessTree.isAlive(pid) else { return }
            ProcessTree.stop(scripts: [], tools: [pid] + tools + ProcessTree.descendants(of: pid), grace: 5)
        }
    }

    /// For quitting the app: stops the script and its tools and waits (a few seconds at most) for them to exit,
    /// so no build keeps writing into the game's folder with nobody watching it.
    func stopForQuit() {
        guard isRunning, let p = process else { return }
        cancelRequested = true
        let pid = p.processIdentifier
        ProcessTree.stop(scripts: [pid], tools: ProcessTree.descendants(of: pid), grace: 4)
    }

    func fail(_ message: String) {
        append(message, .error)
        phase = .failed(message)
        onFinish?(self)
    }

    var fullLog: String { log.map(\.text).joined(separator: "\n") }

    // MARK: - Output

    private func attach(_ handle: FileHandle, isStderr: Bool) {
        let splitter = LineSplitter()
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            let lines = data.isEmpty ? splitter.flush() : splitter.feed(data)
            if data.isEmpty { h.readabilityHandler = nil }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for line in lines {
                        if isStderr { self.handleStderr(line) } else { self.handleEvent(line) }
                    }
                    if data.isEmpty {
                        self.closedStreams += 1
                        self.finishIfDone()
                    }
                }
            }
        }
    }

    private func handleEvent(_ line: String) {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let ev = obj["ev"] as? String else {
            if !line.isEmpty { append(line, .info) }
            return
        }
        switch ev {
        case "stage":
            stageIndex = obj["k"] as? Int ?? stageIndex
            stageCount = obj["n"] as? Int ?? stageCount
            stageName = obj["name"] as? String ?? ""
            stepName = obj["step"] as? String ?? ""
            stageFraction = nil
            eta = nil
            detail = ""
            append("[\(stageIndex)/\(stageCount)] \(stageName)", .info)
        case "step":
            stepName = obj["step"] as? String ?? obj["name"] as? String ?? stepName
            stageFraction = nil
            eta = nil
        case "progress":
            stageFraction = obj["frac"] as? Double
            eta = obj["eta"] as? Double
            detail = Self.progressDetail(obj)
        case "stage_end":
            let ok = obj["ok"] as? Bool ?? true
            let summary = obj["summary"] as? String ?? ""
            let name = obj["name"] as? String ?? stageName
            append("\(ok ? "✓" : "✗") \(name)\(summary.isEmpty ? "" : " — \(summary)")", ok ? .info : .error)
            stageFraction = 1
        case "shaders_stale":
            append(String(localized: "Los shaders cambiaron y se vuelven a traducir (\(obj["reason"] as? String ?? ""))."), .info)
        case "say":
            let msg = obj["msg"] as? String ?? ""
            if msg.hasPrefix("[RED] ") {
                let text = String(msg.dropFirst(6))
                lastRed = text
                append(text, .error)
            } else {
                append(msg, .info)
            }
        default:
            break
        }
    }

    private func handleStderr(_ line: String) {
        guard !line.isEmpty else { return }
        stderrTail.append(line)
        if stderrTail.count > 20 { stderrTail.removeFirst() }
        append(line, .stderr)
    }

    private func finishIfDone() {
        guard isRunning, let status = exitStatus, closedStreams >= 2 else { return }
        process = nil
        if !toolsAtCancel.isEmpty {
            let left = toolsAtCancel.filter(ProcessTree.isAlive)
            toolsAtCancel = []
            if !left.isEmpty { DispatchQueue.global(qos: .utility).async { ProcessTree.stop(scripts: [], tools: left, grace: 5) } }
        }
        if cancelRequested || status == 130 {
            phase = .cancelled
            append(String(localized: "Compilación cancelada."), .info)
        } else if status == 0 {
            phase = .succeeded
            append(String(localized: "Compilación terminada."), .info)
        } else {
            let reason = lastRed ?? stderrTail.last ?? String(localized: "La compilación terminó con el código \(status).")
            phase = .failed(reason)
        }
        onFinish?(self)
    }

    private func append(_ text: String, _ level: LogLine.Level) {
        log.append(LogLine(id: nextLineID, text: text, level: level))
        nextLineID += 1
        if log.count > 4000 { log.removeFirst(log.count - 4000) }
    }

    private static func progressDetail(_ obj: [String: Any]) -> String {
        var parts: [String] = []
        if let done = obj["done"] as? Double, let total = obj["total"] as? Double, total > 0 {
            let unit = obj["unit"] as? String ?? ""
            let approx = (obj["est"] as? Bool ?? false) ? "~" : ""
            if unit == "B" {
                parts.append(String(localized: "\(Int64(done).byteString) de \(approx)\(Int64(total).byteString)"))
            } else {
                parts.append(String(localized: "\(Int(done)) de \(approx)\(Int(total))\(unit.isEmpty ? "" : " \(unit)")"))
            }
        }
        if let note = obj["note"] as? String, !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}

/// Splits a byte stream into lines; used from one file handle's queue only.
private final class LineSplitter: @unchecked Sendable {
    private var buffer = Data()

    func feed(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            lines.append(String(decoding: buffer[buffer.startIndex ..< nl], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex ... nl)
        }
        return lines
    }

    func flush() -> [String] {
        defer { buffer.removeAll() }
        return buffer.isEmpty ? [] : [String(decoding: buffer, as: UTF8.self)]
    }
}
