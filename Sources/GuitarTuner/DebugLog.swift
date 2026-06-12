import Foundation

/// Lightweight append-only debug log at /tmp/guitartuner.log.
final class DebugLog {
    static let shared = DebugLog()

    private let queue = DispatchQueue(label: "guitartuner.debuglog")
    private let path = "/tmp/guitartuner.log"
    private lazy var formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    func line(_ message: String) {
        queue.async {
            let entry = "\(self.formatter.string(from: Date())) \(message)\n"
            if let handle = FileHandle(forWritingAtPath: self.path) {
                handle.seekToEndOfFile()
                handle.write(entry.data(using: .utf8)!)
                try? handle.close()
            } else {
                try? entry.write(toFile: self.path, atomically: true, encoding: .utf8)
            }
        }
    }
}
