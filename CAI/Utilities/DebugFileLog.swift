import Foundation

#if DEBUG
/// TEMP: writes plain-text diagnostic lines to a file in the app's
/// Documents directory — used only while debugging the local on-prem test
/// server connection, since unified OS logging wasn't reliably capturing
/// this app's own events in that environment. Remove before merging.
enum DebugFileLog {
    private static let url = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("debug_trace.log")

    static func log(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url)
        }
    }
}
#endif
