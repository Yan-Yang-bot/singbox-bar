import Foundation

/// Separate from the menu app so Quit (keep current state) and app updates
/// leave both sing-box and bounded logging alive.
@main
struct LogCapture {
    static func main() {
        guard CommandLine.arguments.count == 4 else { exit(2) }
        let args = CommandLine.arguments
        let url = URL(fileURLWithPath: args[3])
        var buffer = LogBuffer(readLog(url.path))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[1])
        process.arguments = ["run", "-c", args[2]]
        process.currentDirectoryURL = URL(fileURLWithPath: (args[2] as NSString).deletingLastPathComponent)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try buffer.write(to: url)
            try process.run()
            // Close our copy so EOF arrives when sing-box exits.
            pipe.fileHandleForWriting.closeFile()
            var pending = Data()
            while true {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                pending.append(data)
                // Keep incomplete UTF-8 sequences for the next read.
                var end = pending.count
                while end > max(0, pending.count - 4),
                      String(data: pending.prefix(end), encoding: .utf8) == nil { end -= 1 }
                if let text = String(data: pending.prefix(end), encoding: .utf8), end > 0 {
                    buffer.append(text)
                    pending.removeFirst(end)
                    try buffer.write(to: url)
                } else if pending.count > 4 {
                    buffer.append(String(decoding: pending, as: UTF8.self))
                    pending.removeAll()
                    try buffer.write(to: url)
                }
            }
            if !pending.isEmpty {
                buffer.append(String(decoding: pending, as: UTF8.self))
                try buffer.write(to: url)
            }
            process.waitUntilExit()
            exit(process.terminationStatus)
        } catch {
            buffer.append("\nERROR: Log capture failed: \(error.localizedDescription)\n")
            try? buffer.write(to: url)
            // Do not leave an unmonitored child behind on a write failure.
            if process.isRunning { process.terminate() }
            exit(1)
        }
    }
}
