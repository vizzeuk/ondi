import Darwin
import Foundation
import IOKit
import Observation

/// Live use of a running game: CPU and memory of its processes (the launcher and the host it starts),
/// the Mac's GPU load and thermal state. The in-game FPS comes from Apple's Metal HUD (DM_METAL_HUD).
@Observable @MainActor
final class PerformanceMonitor {
    struct Sample: Identifiable {
        let id: Int
        let date: Date
        let cpu: Double       // % of the whole CPU
        let cores: Double     // cores busy
        let memoryGB: Double
        let gpu: Double?      // % device utilization
    }

    private(set) var samples: [Sample] = []
    private(set) var thermal: ProcessInfo.ThermalState = .nominal
    private(set) var watchedPID: pid_t?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastCPU: Double?
    @ObservationIgnored private var lastTime: Date?
    @ObservationIgnored private var nextID = 0

    var latest: Sample? { samples.last }

    func watch(_ pid: pid_t?) {
        guard pid != watchedPID else { return }
        watchedPID = pid
        samples = []
        lastCPU = nil
        lastTime = nil
        timer?.invalidate()
        timer = nil
        guard pid != nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func tick() {
        thermal = ProcessInfo.processInfo.thermalState
        guard let root = watchedPID else { return }
        let pids = ProcStats.tree(root)
        var cpuNs = 0.0
        var footprint: UInt64 = 0
        for pid in pids {
            if let u = ProcStats.usage(pid) {
                cpuNs += u.cpuNs
                footprint += u.footprint
            }
        }
        let now = Date()
        defer {
            lastCPU = cpuNs
            lastTime = now
        }
        guard let prevCPU = lastCPU, let prevTime = lastTime else { return }
        let wallNs = now.timeIntervalSince(prevTime) * 1e9
        let cores = max(0, (cpuNs - prevCPU) / wallNs)
        let total = cores / Double(ProcessInfo.processInfo.activeProcessorCount) * 100
        samples.append(Sample(id: nextID, date: now, cpu: total, cores: cores,
                              memoryGB: Double(footprint) / 1_073_741_824, gpu: GPUStats.utilization()))
        nextID += 1
        if samples.count > 120 { samples.removeFirst(samples.count - 120) }
    }

    var thermalText: String {
        switch thermal {
        case .nominal: return String(localized: "Normal")
        case .fair: return String(localized: "Templado")
        case .serious: return String(localized: "Caliente")
        case .critical: return String(localized: "Crítico")
        @unknown default: return "—"
        }
    }
}

enum ProcStats {
    private static let timebase: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom)
    }()

    static func allPIDs() -> [pid_t] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let n = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        return pids.prefix(max(0, n)).filter { $0 > 0 }
    }

    static func path(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }

    /// The process and all its descendants.
    static func tree(_ root: pid_t) -> [pid_t] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let n = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        var parent: [pid_t: pid_t] = [:]
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        for pid in pids.prefix(max(0, n)) where pid > 0 {
            var info = proc_bsdinfo()
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size {
                parent[pid] = pid_t(info.pbi_ppid)
            }
        }
        var result = [root]
        var frontier = [root]
        while let p = frontier.popLast() {
            for (child, pp) in parent where pp == p && child != p {
                result.append(child)
                frontier.append(child)
            }
        }
        return result
    }

    static func usage(_ pid: pid_t) -> (cpuNs: Double, footprint: UInt64)? {
        var info = rusage_info_v2()
        let r = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        guard r == 0 else { return nil }
        return (Double(info.ri_user_time &+ info.ri_system_time) * timebase, info.ri_phys_footprint)
    }
}

enum GPUStats {
    /// "Device Utilization %" from the GPU driver's statistics (no special rights needed).
    static func utilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var result: Double?
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let u = (stats["Device Utilization %"] as? NSNumber)?.doubleValue {
                result = max(result ?? 0, u)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return result
    }
}
