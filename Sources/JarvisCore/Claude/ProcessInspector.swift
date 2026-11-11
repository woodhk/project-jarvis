import Darwin
import Foundation

/// What the session reader needs to know about running processes.
public protocol ProcessInspecting: Sendable {
    func isAlive(_ pid: Int32) -> Bool
    func parent(of pid: Int32) -> Int32?
    /// The terminal device, for example "/dev/ttys012", or nil when the process has none.
    func tty(of pid: Int32) -> String?
    func executablePath(of pid: Int32) -> String?
}

public struct LiveProcessInspector: ProcessInspecting {
    public init() {}

    public func isAlive(_ pid: Int32) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    public func parent(of pid: Int32) -> Int32? {
        guard let info = processInfo(pid), info.kp_eproc.e_ppid > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    public func tty(of pid: Int32) -> String? {
        guard let info = processInfo(pid), info.kp_eproc.e_tdev != -1, info.kp_eproc.e_tdev != 0,
              let name = devname(info.kp_eproc.e_tdev, S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    public func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    /// Read through sysctl, which also answers for processes owned by root (Terminal starts shells through `login`).
    /// `proc_pidinfo` refuses those.
    private func processInfo(_ pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}
