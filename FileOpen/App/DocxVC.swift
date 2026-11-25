import UIKit
import UniformTypeIdentifiers

/// Word（.docx）表格查看 + 改字：把 w:tbl 渲染成原生表格，点单元格就能改，改完另存一份 docx。
final class DocxVC: UIViewController {
    private let fileURL: URL
    private let doc: Docx?
    private let bar = UIView()
    private let nameLabel = UILabel()
    private let infoLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let scroll = UIScrollView()
    private var built = false
    private var dirty = false

    init(url: URL) {
        fileURL = url
        doc = try? Docx(url: url)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1)

        bar.backgroundColor = UIColor(red: 0.02, green: 0.42, blue: 0.35, alpha: 1)
        view.addSubview(bar)

        nameLabel.text = fileURL.lastPathComponent
        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.numberOfLines = 2
        bar.addSubview(nameLabel)

        closeButton.setTitle("关闭", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        bar.addSubview(closeButton)

        saveButton.setTitle("另存", for: .normal)
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        bar.addSubview(saveButton)

        infoLabel.font = .systemFont(ofSize: 11.5)
        infoLabel.textColor = UIColor(white: 1, alpha: 0.85)
        bar.addSubview(infoLabel)

        scroll.backgroundColor = .clear
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)

        refreshInfo()
        if doc == nil {
            Log.add("docx 打不开：\(fileURL.lastPathComponent)")
        }
    }

    private func refreshInfo() {
        guard let doc else {
            infoLabel.text = "解析失败 · 只能看，不能改"
            return
        }
        let tables = doc.tables.count
        var text = tables > 0 ? "表格 \(tables) 个 · 点单元格改字" : "这份文档没有表格，下面是正文"
        if doc.editCount > 0 { text += " · 已改 \(doc.editCount) 处（点右上方「另存」）" }
        infoLabel.text = text
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let top = view.safeAreaInsets.top
        let w = view.bounds.width
        bar.frame = CGRect(x: 0, y: top, width: w, height: 58)
        closeButton.frame = CGRect(x: 10, y: 6, width: 46, height: 28)
        saveButton.frame = CGRect(x: w - 66, y: 6, width: 56, height: 28)
        nameLabel.frame = CGRect(x: 62, y: 4, width: w - 134, height: 26)
        infoLabel.frame = CGRect(x: 62, y: 32, width: w - 134, height: 18)
        scroll.frame = CGRect(x: 0, y: top + 58, width: w, height: view.bounds.height - top - 58)
        if !built {
            built = true
            buildContent(width: w)
        }
    }

    // MARK: - 画面

    private func buildContent(width: CGFloat) {
        scroll.subviews.forEach { $0.removeFromSuperview() }

        guard let doc else {
            let tv = UITextView(frame: CGRect(x: 12, y: 12, width: width - 24, height: scroll.bounds.height - 24))
            tv.isEditable = false
            tv.text = "这个 .docx 解析失败（可能是老的 .doc 改了后缀，或文件损坏）。\n建议用 WPS 打开后另存为 .docx 再试。"
            tv.font = .systemFont(ofSize: 14)
            scroll.addSubview(tv)
            scroll.contentSize = CGSize(width: width, height: tv.frame.maxY)
            return
        }

        if doc.tables.isEmpty {
            let note = UILabel(frame: CGRect(x: 12, y: 12, width: width - 24, height: 40))
            note.text = "没有表格，下面是正文文字"
            note.font = .systemFont(ofSize: 12)
            note.textColor = .secondaryLabel
            scroll.addSubview(note)

            let tv = UITextView(frame: CGRect(x: 12, y: 56, width: width - 24,
                                             height: max(200, scroll.bounds.height - 80)))
            tv.isEditable = false
            tv.text = doc.plainText.isEmpty ? "（没有读出文字）" : doc.plainText
            tv.font = .systemFont(ofSize: 14)
            tv.backgroundColor = .white
            tv.layer.cornerRadius = 8
            scroll.addSubview(tv)
            scroll.contentSize = CGSize(width: width, height: tv.frame.maxY + 24)
            return
        }

        var y: CGFloat = 12
        for (ti, table) in doc.tables.enumerated() {
            let cols = max(table.cols, 1)
            let colW = max(78, (width - 24) / CGFloat(min(cols, 4)))
            var tableWidth: CGFloat = 0
            for row in table.rows {
                tableWidth = max(tableWidth, CGFloat(row.cells.reduce(0) { $0 + $1.span }) * colW)
            }
            tableWidth = max(tableWidth, width - 24)
            let rowH: CGFloat = 42

            let title = UILabel(frame: CGRect(x: 12, y: y, width: width - 24, height: 18))
            title.text = "表 \(ti + 1) · \(table.rows.count) 行 × \(cols) 列"
            title.font = .systemFont(ofSize: 11.5, weight: .semibold)
            title.textColor = .secondaryLabel
            scroll.addSubview(title)
            y += 22

            let box = UIView(frame: CGRect(x: 12, y: y, width: tableWidth, height: CGFloat(table.rows.count) * rowH))
            box.backgroundColor = .white
            box.layer.cornerRadius = 8
            box.layer.borderWidth = 1
            box.layer.borderColor = UIColor(red: 0.85, green: 0.87, blue: 0.9, alpha: 1).cgColor
            box.clipsToBounds = true

            for (ri, row) in table.rows.enumerated() {
                var x: CGFloat = 0
                for (ci, cell) in row.cells.enumerated() {
                    let cw = colW * CGFloat(cell.span)
                    let c = UIView(frame: CGRect(x: x, y: CGFloat(ri) * rowH, width: cw, height: rowH))
                    c.backgroundColor = (ri == 0 && doc.tables[ti].rows.count > 1)
                        ? UIColor(red: 0.94, green: 0.97, blue: 0.96, alpha: 1) : .white
                    c.layer.borderWidth = 0.5
                    c.layer.borderColor = UIColor(red: 0.82, green: 0.85, blue: 0.88, alpha: 1).cgColor
                    let label = UILabel(frame: CGRect(x: 6, y: 4, width: cw - 12, height: rowH - 8))
                    label.text = cell.text
                    label.font = .systemFont(ofSize: 13)
                    label.numberOfLines = 2
                    label.textColor = UIColor(red: 0.1, green: 0.12, blue: 0.16, alpha: 1)
                    c.addSubview(label)
                    c.tag = ((ti * 1000) + ri) * 1000 + ci
                    let tap = UITapGestureRecognizer(target: self, action: #selector(cellTapped(_:)))
                    c.addGestureRecognizer(tap)
                    box.addSubview(c)
                    x += cw
                }
            }
            scroll.addSubview(box)
            y += box.frame.height + 18
        }
        scroll.contentSize = CGSize(width: max(width, scroll.contentSize.width), height: y)
        Log.add("表格已渲染：\(doc.tables.count) 个")
    }

    // MARK: - 改字

    @objc private func cellTapped(_ g: UITapGestureRecognizer) {
        guard let view = g.view, let doc else { return }
        let tag = view.tag
        let ti = tag / 1_000_000
        let ri = (tag / 1000) % 1000
        let ci = tag % 1000

        var current = ""
        if ti < doc.tables.count, ri < doc.tables[ti].rows.count, ci < doc.tables[ti].rows[ri].cells.count {
            current = doc.tables[ti].rows[ri].cells[ci].text
        }

        let alert = UIAlertController(title: "改单元格文字",
                                      message: "表 \(ti + 1) · 第 \(ri + 1) 行 · 第 \(ci + 1) 格",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = current
            tf.placeholder = "清空＝删除这段文字"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            guard let self, let doc = self.doc else { return }
            let newText = alert.textFields?.first?.text ?? ""
            if newText == current { return }
            doc.updateText(newText, table: ti, row: ri, cell: ci)
            self.dirty = true
            self.built = false
            self.setNeedsRebuild()
        })
        present(alert, animated: true)
    }

    private func setNeedsRebuild() {
        refreshInfo()
        scroll.subviews.forEach { $0.removeFromSuperview() }
        buildContent(width: view.bounds.width)
        built = true
    }

    // MARK: - 另存

    @objc private func saveTapped() {
        guard let doc else { return }
        let name = fileURL.deletingPathExtension().lastPathComponent + "-已修改.docx"
        let out = Opener.uniqueDest(name, in: Opener.libRoot)
        saveButton.isEnabled = false
        saveButton.setTitle("保存中", for: .normal)
        DispatchQueue.global(qos: .userInitiated).async {
            var saveError: Error?
            do { try doc.save(to: out) }
            catch let e { saveError = e; Log.add("另存失败：\(e.localizedDescription)") }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.saveButton.isEnabled = true
                self.saveButton.setTitle("另存", for: .normal)
                self.dirty = false
                self.refreshInfo()
                Router.shared.root?.reload()
                if let error = saveError {
                    let a = UIAlertController(title: "保存失败", message: error.localizedDescription, preferredStyle: .alert)
                    a.addAction(UIAlertAction(title: "好", style: .default))
                    self.present(a, animated: true)
                    return
                }
                let share = UIActivityViewController(activityItems: [out], applicationActivities: nil)
                if let pop = share.popoverPresentationController {
                    pop.sourceView = self.saveButton
                    pop.sourceRect = self.saveButton.bounds
                }
                self.present(share, animated: true) {
                    Log.add("已弹出保存/分享：\(out.lastPathComponent)")
                }
            }
        }
    }

    @objc private func closeTapped() {
        if dirty {
            let a = UIAlertController(title: "还没保存", message: "改的内容还没另存成新文件，确定关闭？", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "继续编辑", style: .cancel))
            a.addAction(UIAlertAction(title: "直接关闭", style: .destructive) { _ in self.dismiss(animated: true) })
            present(a, animated: true)
            return
        }
        dismiss(animated: true)
    }
}
