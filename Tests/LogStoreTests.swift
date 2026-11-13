import Foundation

@main
struct LogStoreTests {
    static func main() throws {
        assert(LogBuffer().text == "")
        var buffer = LogBuffer()
        for n in 1...700 { buffer.append("line \(n)\n") }
        assert(buffer.text == (201...700).map { "line \($0)\n" }.joined())
        buffer.append("partial")
        assert(buffer.text.hasPrefix("line 202\n"))
        buffer.append(" completed\n")
        assert(buffer.text.hasSuffix("partial completed\n"))
        assert(buffer.text.split(separator: "\n", omittingEmptySubsequences: false).count == 501)
        let blanks = LogBuffer(String(repeating: "\n", count: 600))
        assert(blanks.text == String(repeating: "\n", count: 500))
        assert(LogBuffer("a\r\nb\r\n").text == "a\r\nb\r\n")
        assert(plainLog("\u{001B}[31mERROR\u{001B}[0m 中文") == "ERROR 中文")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("log")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try buffer.write(to: url)
        assert(readLog(url.path) == buffer.text)
        print("Log buffer tests passed")
    }
}
