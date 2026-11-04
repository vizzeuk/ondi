import Foundation

/// The build script starts tools of its own (shader_split.py, dmsh_build.py, metal…) that outlive it when it is
/// stopped from outside: closing the app mid-build left them running, and a new build of the same game then
/// wrote into the same `*.partial` folders (shader_split: `FileNotFoundError … shader/pkg.partial/tables`).
enum ProcessTree {
    struct Entry {
        let pid: pid_t
        let ppid: pid_t
        let command: String
    }

    /// Every process of this user, from `ps` (full command lines).
    static func snapshot() -> [Entry] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-x", "-ww", "-o", "pid=,ppid=,command="]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = pid_t(parts[0]), let ppid = pid_t(parts[1]) else { return nil }
            return Entry(pid: pid, ppid: ppid, command: String(parts[2]))
        }
    }

    /// A process's children, grandchildren, … (not the process itself).
    static func descendants(of root: pid_t, in table: [Entry]? = nil) -> [pid_t] {
        let table = table ?? snapshot()
        var children: [pid_t: [pid_t]] = [:]
        for e in table { children[e.ppid, default: []].append(e.pid) }
        var out: [pid_t] = [], queue = children[root] ?? []
        while let pid = queue.popLast() {
            out.append(pid)
            queue += children[pid] ?? []
        }
        return out
    }

    /// Build processes for a game folder that this app did not start (left by an earlier session).
    /// Matches the build script with the folder as argument, and any tool working inside its `<title>_build` folder.
    static func strays(folder: URL, buildFolder: URL?, excluding own: Set<pid_t>, in table: [Entry]) -> [Entry] {
        let me = getpid()
        let gamePath = folder.path
        let buildPath = buildFolder.map { $0.path + "/" }
        return table.filter { e in
            guard e.pid != me, !own.contains(e.pid) else { return false }
            if e.command.contains("build_ipa_from_nsp.py") && e.command.contains(gamePath) { return true }
            if let buildPath, e.command.contains(buildPath) { return true }
            return false
        }
    }

    static func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

    static func signal(_ pids: [pid_t], _ sig: Int32) {
        for pid in pids where pid > 1 { kill(pid, sig) }
    }

    /// SIGINT to the build scripts (they stop their current tool and exit), SIGTERM to the tools, SIGKILL to what is left
    /// after `grace` seconds. Blocks the calling thread: call it off the main thread unless the app is quitting.
    static func stop(scripts: [pid_t], tools: [pid_t], grace: TimeInterval) {
        signal(scripts, SIGINT)
        signal(tools, SIGTERM)
        let all = scripts + tools
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline, all.contains(where: isAlive) { usleep(100_000) }
        signal(all.filter(isAlive), SIGKILL)
    }
}
