import Foundation

/// Lightweight append-only file logger used to diagnose startup/Bluetooth flow
/// independently of the unified log (which has proven unreliable to read back
/// for this process during development). Path is overridable via MOMENTUM_DIAG.
public enum Diag {
    public static let path: String = {
        if let p = ProcessInfo.processInfo.environment["MOMENTUM_DIAG"], !p.isEmpty { return p }
        return "/tmp/momentum-diag.log"
    }()

    public static func write(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
