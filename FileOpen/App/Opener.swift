import Foundation

/// 收文件 → 变成我们自己沙盒里能读的本地文件。
/// 三级兜底 + 一直持有安全访问权，尽量做到"点了就一定能读"。
/// 另提供「收件箱」：把文件复制到 文件App→我的iPhone→快开→收件箱，打开 App 就自动打开它。
enum Opener {
    private static var holding: Set<String> = []
    private static let lock = NSLock()

    static var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var libRoot: URL { folder("打开过的文件") }
    static var inbox: URL { folder("收件箱") }

    private static func folder(_ name: String) -> URL {
        let f = docs.appendingPathComponent(name, isDirectory: true)
        if !FileManager.default.fileExists(atPath: f.path) {
            try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        }
        return f
    }

    static func localCopy(of url: URL) -> URL? {
        guard url.isFileURL else { Log.add("不是文件 URL：\(url)"); return nil }

        lock.lock()
        let already = holding.contains(url.path)
        if !already { holding.insert(url.path) }
        lock.unlock()
        if !already {
            let scoped = url.startAccessingSecurityScopedResource()
            Log.add("安全访问权 startAccessing = \(scoped)")
        }

        let dest = uniqueDest(url.lastPathComponent, in: libRoot)

        var coordError: NSError?
        var ok = false
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { src in
            do { try FileManager.default.copyItem(at: src, to: dest); ok = true }
            catch { Log.add("协调复制失败：\(error.localizedDescription)") }
        }
        if let coordError { Log.add("协调器报错：\(coordError.localizedDescription)") }
        if ok, exists(dest) { Log.add("✅ 方式1 协调复制：\(dest.lastPathComponent)"); return dest }

        do {
            try FileManager.default.copyItem(at: url, to: dest)
            if exists(dest) { Log.add("✅ 方式2 直接复制：\(dest.lastPathComponent)"); return dest }
        } catch { Log.add("直接复制失败：\(error.localizedDescription)") }

        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            try data.write(to: dest, options: .atomic)
            if exists(dest) { Log.add("✅ 方式3 读字节写文件：\(dest.lastPathComponent)"); return dest }
        } catch { Log.add("读字节失败：\(error.localizedDescription)") }

        Log.add("❌ 三种复制都失败，退回原 URL")
        return exists(url) ? url : nil
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func uniqueDest(_ name: String, in dir: URL) -> URL {
        let fm = FileManager.default
        let safeName = name.isEmpty ? "未命名文件" : name
        var candidate = dir.appendingPathComponent(safeName)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        let base = (safeName as NSString).deletingPathExtension
        let ext = (safeName as NSString).pathExtension
        var i = 2
        while true {
            candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    static func list(_ dir: URL) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                 includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles])) ?? []
        return items.filter { !$0.lastPathComponent.hasPrefix(".") }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
    }

    /// 收件箱里有东西就搬进文件库，返回搬过去的文件
    static func drainInbox() -> [URL] {
        var moved: [URL] = []
        for src in list(inbox) {
            let dest = uniqueDest(src.lastPathComponent, in: libRoot)
            do {
                try FileManager.default.copyItem(at: src, to: dest)
                try FileManager.default.removeItem(at: src)
                moved.append(dest)
                Log.add("收件箱 → 文件库：\(dest.lastPathComponent)")
            } catch {
                Log.add("收件箱搬运失败：\(error.localizedDescription)")
            }
        }
        return moved
    }

    /// 记录最近收到的 URL（排查"到底收到没有"）
    static func noteReceived(_ urls: [URL]) {
        let f = docs.appendingPathComponent("最近收到.txt")
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "[\(fmt.string(from: Date()))] " + urls.map { $0.absoluteString }.joined(separator: " | ") + "\n"
        if !FileManager.default.fileExists(atPath: f.path) {
            _ = FileManager.default.createFile(atPath: f.path, contents: "最近收到的文件 URL\n".data(using: .utf8))
        }
        guard let d = line.data(using: .utf8), let h = try? FileHandle(forWritingTo: f) else { return }
        defer { try? h.close() }
        h.seekToEndOfFile()
        h.write(d)
    }
}
