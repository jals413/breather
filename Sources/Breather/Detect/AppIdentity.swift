import AppKit
import Darwin

/// The user-facing app behind a process, even when the process is a helper
/// (e.g. "Google Chrome Helper (Renderer)" or a WebKit XPC service).
struct AppIdentity: Hashable {
    var bundleID: String
    var name: String
    var pid: pid_t

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    nonisolated(unsafe) private static let responsiblePID: ResponsibleFn? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let sym = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    static func resolve(pid: pid_t) -> AppIdentity? {
        if let app = NSRunningApplication(processIdentifier: pid),
           app.activationPolicy == .regular, let id = app.bundleIdentifier {
            return AppIdentity(bundleID: id, name: app.localizedName ?? id, pid: pid)
        }
        // XPC helpers: ask the kernel who is responsible for this process.
        if let responsible = responsiblePID?(pid), responsible > 0, responsible != pid,
           let app = NSRunningApplication(processIdentifier: responsible), let id = app.bundleIdentifier {
            return AppIdentity(bundleID: id, name: app.localizedName ?? id, pid: responsible)
        }
        // Helpers nested inside an app bundle: use the outermost .app.
        if let path = executablePath(pid), let range = path.range(of: ".app/") {
            let appPath = String(path[..<range.upperBound].dropLast())
            if let bundle = Bundle(path: appPath), let id = bundle.bundleIdentifier {
                let name = (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
                return AppIdentity(bundleID: id, name: name, pid: pid)
            }
        }
        if let path = executablePath(pid) {
            let name = URL(fileURLWithPath: path).lastPathComponent
            return AppIdentity(bundleID: name, name: name, pid: pid)
        }
        return nil
    }

    static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    static func runningProcessNames() -> Set<String> {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var names = Set<String>()
        var buffer = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(Int(max(0, filled))) where pid > 0 {
            if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 { names.insert(String(cString: buffer)) }
        }
        return names
    }
}
