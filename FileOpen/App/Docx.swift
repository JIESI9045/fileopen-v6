import Foundation
import ZIPFoundation

/// Word 表格的最小可编辑读取器：.docx 是 zip，表格在 word/document.xml 的 <w:tbl> 里。
/// 只动单元格文字，其余格式/样式/图片原样保留（改完重新打包，Word/WPS 都能正常打开）。
struct DxCell {
    var text: String = ""
    var span: Int = 1
    /// 该单元格里每个 <w:t> 文本内容在整份 document.xml 中的绝对位置
    var ranges: [NSRange] = []
}

struct DxRow {
    var cells: [DxCell] = []
}

struct DxTable {
    var rows: [DxRow] = []
    var cols: Int {
        rows.map { $0.cells.reduce(0) { $0 + $1.span } }.max() ?? 0
    }
}

enum DxError: LocalizedError {
    case notDocx, noDocumentXML, cannotWrite
    var errorDescription: String? {
        switch self {
        case .notDocx: return "这不是一个 .docx 文件（老的 .doc 请先在 WPS 里另存为 .docx）"
        case .noDocumentXML: return "包里没有 word/document.xml"
        case .cannotWrite: return "写不出新文件"
        }
    }
}

final class Docx {
    static let entryName = "word/document.xml"

    let sourceURL: URL
    private(set) var xml: String
    private(set) var tables: [DxTable] = []
    private(set) var plainText: String = ""
    /// 改过的单元格：key "t-r-c" → 新文字
    private var edits: [String: String] = [:]
    private let ns: NSString

    var editCount: Int { edits.count }

    init(url: URL) throws {
        sourceURL = url
        guard url.pathExtension.lowercased() == "docx" else { throw DxError.notDocx }
        guard let archive = try? Archive(url: url, accessMode: .read),
              let entry = archive[Docx.entryName] else { throw DxError.noDocumentXML }
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        guard let text = String(data: data, encoding: .utf8) else { throw DxError.noDocumentXML }
        xml = text
        ns = text as NSString
        parse()
        Log.add("docx 解析：\(tables.count) 个表格，\(tables.reduce(0) { $0 + $1.rows.count }) 行")
    }

    // MARK: - 解析

    private func parse() {
        let full = NSRange(location: 0, length: ns.length)
        let tblRe = Docx.re(#"<w:tbl(?:\s[^>]*)?>[\s\S]*?</w:tbl>"#)
        let trRe = Docx.re(#"<w:tr(?:\s[^>]*)?>[\s\S]*?</w:tr>"#)
        let tcRe = Docx.re(#"<w:tc(?:\s[^>]*)?>[\s\S]*?</w:tc>"#)
        let tRe = Docx.re(#"<w:t(?:\s[^>]*)?>([^<]*)</w:t>"#)
        let spanRe = Docx.re(#"<w:gridSpan[^>]*w:val="(\d+)""#)

        for tm in tblRe.matches(in: xml, range: full) {
            var rows: [DxRow] = []
            for rm in trRe.matches(in: xml, range: tm.range) {
                var row = DxRow()
                for cm in tcRe.matches(in: xml, range: rm.range) {
                    var cell = DxCell()
                    var parts: [String] = []
                    for xm in tRe.matches(in: xml, range: cm.range) {
                        let contentRange = xm.range(at: 1)
                        cell.ranges.append(contentRange)
                        parts.append(Docx.unescape(ns.substring(with: contentRange)))
                    }
                    cell.text = parts.joined()
                    if let sm = spanRe.firstMatch(in: xml, options: [], range: cm.range),
                       sm.numberOfRanges > 1,
                       let v = Int(ns.substring(with: sm.range(at: 1))) {
                        cell.span = max(1, min(v, 12))
                    }
                    row.cells.append(cell)
                }
                if !row.cells.isEmpty { rows.append(row) }
            }
            if !rows.isEmpty { tables.append(DxTable(rows: rows)) }
        }

        // 纯文本兜底（没表格的文档也能看内容）
        let paraRe = Docx.re(#"<w:p(?:\s[^>]*)?>[\s\S]*?</w:p>"#)
        var lines: [String] = []
        for pm in paraRe.matches(in: xml, range: full) {
            var s = ""
            for xm in tRe.matches(in: xml, range: pm.range) {
                s += Docx.unescape(ns.substring(with: xm.range(at: 1)))
            }
            if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.append(s) }
        }
        plainText = lines.joined(separator: "\n")
        if plainText.count > 20000 { plainText = String(plainText.prefix(20000)) + "\n…（后面省略）" }
    }

    // MARK: - 编辑

    func updateText(_ newText: String, table: Int, row: Int, cell: Int) {
        guard table < tables.count, row < tables[table].rows.count,
              cell < tables[table].rows[row].cells.count else { return }
        tables[table].rows[row].cells[cell].text = newText
        edits["\(table)-\(row)-\(cell)"] = newText
        Log.add("改单元格 [\(table)][\(row)][\(cell)] → \(newText.prefix(30))")
    }

    private func rebuiltXML() -> String {
        guard !edits.isEmpty else { return xml }
        var replacements: [(NSRange, String)] = []
        for (key, newText) in edits {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { continue }
            let t = parts[0], r = parts[1], c = parts[2]
            guard t < tables.count, r < tables[t].rows.count, c < tables[t].rows[r].cells.count else { continue }
            let ranges = tables[t].rows[r].cells[c].ranges
            guard let first = ranges.first else { continue }
            replacements.append((first, Docx.escape(newText)))
            for extra in ranges.dropFirst() { replacements.append((extra, "")) }
        }
        let out = NSMutableString(string: xml)
        for (range, value) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            out.replaceCharacters(in: range, with: value)
        }
        return out as String
    }

    /// 另存为新 docx（不覆盖原文件）
    func save(to outURL: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: outURL)
        guard let src = try? Archive(url: sourceURL, accessMode: .read) else { throw DxError.cannotWrite }

        let tmp = fm.temporaryDirectory.appendingPathComponent("dx_" + UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        var order: [String] = []
        for entry in src {
            let rel = entry.path
            order.append(rel)
            let dst = tmp.appendingPathComponent(rel)
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            if entry.type == .directory {
                try fm.createDirectory(at: dst, withIntermediateDirectories: true)
            } else {
                _ = try src.extract(entry, to: dst)
            }
        }
        try rebuiltXML().write(to: tmp.appendingPathComponent(Docx.entryName), atomically: true, encoding: .utf8)

        guard let dst = try? Archive(url: outURL, accessMode: .create) else { throw DxError.cannotWrite }
        var added = 0
        for rel in order {
            let item = tmp.appendingPathComponent(rel)
            guard fm.fileExists(atPath: item.path) else { continue }
            try dst.addEntry(with: rel, relativeTo: tmp)
            added += 1
        }
        Log.add("另存 docx：\(outURL.lastPathComponent)，\(added) 项")
    }

    // MARK: - 工具

    private static var cache: [String: NSRegularExpression] = [:]

    static func re(_ pattern: String) -> NSRegularExpression {
        if let c = cache[pattern] { return c }
        let r = (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
            ?? (try! NSRegularExpression(pattern: ".", options: []))
        cache[pattern] = r
        return r
    }

    static func unescape(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
        if out.contains("&#") {
            let rex = re(#"&#(x?)([0-9a-fA-F]+);"#)
            let nsOut = out as NSString
            var result = ""
            var cursor = 0
            for m in rex.matches(in: out, range: NSRange(location: 0, length: nsOut.length)) {
                result += nsOut.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                let isHex = nsOut.substring(with: m.range(at: 1)) == "x"
                let digits = nsOut.substring(with: m.range(at: 2))
                let value = UInt32(digits, radix: isHex ? 16 : 10) ?? 63
                result += String(UnicodeScalar(value) ?? "?")
                cursor = m.range.location + m.range.length
            }
            result += nsOut.substring(from: cursor)
            out = result
        }
        return out
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
