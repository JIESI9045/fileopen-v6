import Foundation

/// 运行日志：Documents/运行日志.txt。
/// App 开了 UIFileSharingEnabled，所以这个文件在「文件」App → 我的 iPhone → 快开 里能直接看到。
enum Log {
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("运行日志.txt")
    }
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm:ss"; return f
    }()

    static func add(_ s: String) {
        print("[FO] \(s)")
        let line = "[\(fmt.string(from: Date()))] \(s)\n"
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            _ = fm.createFile(atPath: url.path, contents: "快开 运行日志\n".data(using: .utf8))
        }
        guard let data = line.data(using: .utf8), let h = try? FileHandle(forWritingTo: url) else { return }
        defer { try? h.close() }
        h.seekToEndOfFile()
        h.write(data)
    }

    static func text() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? "（暂无日志）"
    }
}

enum Sz {
    static func human(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 KB" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: bytes)
    }
    static func of(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
