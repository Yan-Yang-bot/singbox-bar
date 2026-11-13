import Foundation

/// A single writer owns the file. Readers always see a complete snapshot.
struct LogBuffer {
    static let lineLimit = 500
    private(set) var text = ""

    init(_ text: String = "") { append(text) }

    mutating func append(_ chunk: String) {
        text += chunk
        let endsWithNewline = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n")
        if endsWithNewline { lines.removeLast() }
        text = lines.suffix(Self.lineLimit).joined(separator: "\n")
        if endsWithNewline { text += "\n" }
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

func readLog(_ path: String) -> String {
    LogBuffer((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").text
}

/// Strip terminal colours before display or model submission.
func plainLog(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{001B}\\[[0-?]*[ -/]*[@-~]", with: "",
                              options: .regularExpression)
}
