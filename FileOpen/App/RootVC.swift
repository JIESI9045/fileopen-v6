import UIKit
import UniformTypeIdentifiers

/// v6 自检首页：只有几个"点一下"的按钮，每点一次屏幕立刻多一行带时间戳的字。
/// 目的：把「点了没反应」变成可以一眼看出的事实。
/// 完全不使用 UITableView / UIScrollView —— 排除一切"视图挡住触摸"的可能。
final class RootVC: UIViewController, UIDocumentPickerDelegate {
    private let banner = UIView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let logLabel = UILabel()
    private let counterButton = UIButton(type: .system)
    private let docxButton = UIButton(type: .system)
    private let inboxButton = UIButton(type: .system)
    private let logButton = UIButton(type: .system)
    private let demoButton = UIButton(type: .system)
    private var taps = 0

    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.97, green: 0.98, blue: 1, alpha: 1)

        banner.backgroundColor = UIColor(red: 0.06, green: 0.35, blue: 0.75, alpha: 1)
        view.addSubview(banner)

        titleLabel.text = "快开 v6 · 自检版"
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .white
        banner.addSubview(titleLabel)

        statusLabel.numberOfLines = 0
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 12)
        banner.addSubview(statusLabel)

        let tip = UILabel()
        tip.tag = 1001
        tip.text = "下面每个按钮点一下，这一块会立刻多一行字（带时间）。\n一个字都不变 = 手指的触摸根本没进到这个 App 里。"
        tip.numberOfLines = 0
        tip.font = .systemFont(ofSize: 12)
        tip.textColor = .secondaryLabel
        view.addSubview(tip)

        logLabel.numberOfLines = 0
        logLabel.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        logLabel.textColor = UIColor(red: 0.1, green: 0.15, blue: 0.25, alpha: 1)
        logLabel.text = "（这里会显示你刚刚点了什么）"
        view.addSubview(logLabel)

        config(counterButton, title: "① 点我测试（计数 +1）", color: UIColor(red: 0.1, green: 0.5, blue: 0.95, alpha: 1))
        counterButton.addTarget(self, action: #selector(testTap), for: .touchUpInside)
        view.addSubview(counterButton)

        config(docxButton, title: "② 选一个 Word(.docx) 打开", color: UIColor(red: 0.02, green: 0.45, blue: 0.35, alpha: 1))
        docxButton.addTarget(self, action: #selector(pickDocx), for: .touchUpInside)
        view.addSubview(docxButton)

        config(inboxButton, title: "③ 打开「收件箱」里的文件", color: UIColor(red: 0.55, green: 0.3, blue: 0.8, alpha: 1))
        inboxButton.addTarget(self, action: #selector(openInbox), for: .touchUpInside)
        view.addSubview(inboxButton)

        config(logButton, title: "④ 看运行日志", color: UIColor(red: 0.85, green: 0.45, blue: 0.1, alpha: 1))
        logButton.addTarget(self, action: #selector(showLog), for: .touchUpInside)
        view.addSubview(logButton)

        config(demoButton, title: "⑤ 显示一份示例表格（不读文件）", color: UIColor(red: 0.25, green: 0.25, blue: 0.3, alpha: 1))
        demoButton.addTarget(self, action: #selector(selfTestSheet), for: .touchUpInside)
        view.addSubview(demoButton)

        updateStatus()
        Log.add("v6 自检首页已上屏")
    }

    private func config(_ b: UIButton, title: String, color: UIColor) {
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15.5, weight: .semibold)
        b.backgroundColor = color
        b.layer.cornerRadius = 12
        b.contentHorizontalAlignment = .center
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let top = view.safeAreaInsets.top
        let w = view.bounds.width
        banner.frame = CGRect(x: 0, y: top, width: w, height: 74)
        titleLabel.frame = CGRect(x: 16, y: 8, width: w - 32, height: 26)
        statusLabel.frame = CGRect(x: 16, y: 36, width: w - 32, height: 34)
        view.viewWithTag(1001)?.frame = CGRect(x: 16, y: top + 82, width: w - 32, height: 36)
        logLabel.frame = CGRect(x: 16, y: top + 122, width: w - 32, height: 92)

        let bw = w - 32
        counterButton.frame = CGRect(x: 16, y: top + 224, width: bw, height: 48)
        docxButton.frame = CGRect(x: 16, y: top + 282, width: bw, height: 48)
        inboxButton.frame = CGRect(x: 16, y: top + 340, width: bw, height: 48)
        logButton.frame = CGRect(x: 16, y: top + 398, width: bw, height: 48)
        demoButton.frame = CGRect(x: 16, y: top + 456, width: bw, height: 48)
    }

    // MARK: - 反馈

    private func append(_ line: String) {
        var lines = (logLabel.text ?? "").components(separatedBy: "\n").filter { !$0.hasPrefix("（") }
        lines.append("[\(timeFmt.string(from: Date()))] \(line)")
        if lines.count > 6 { lines = Array(lines.suffix(6)) }
        logLabel.text = lines.joined(separator: "\n")
        Log.add(line)
    }

    private func updateStatus() {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        statusLabel.text = "v\(v) build \(b) · 文件库 \(Opener.list(Opener.libRoot).count) · 收件箱 \(Opener.list(Opener.inbox).count) · 计数 \(taps)"
    }

    func reload() { updateStatus() }

    // MARK: - 按钮

    @objc private func testTap() {
        taps += 1
        updateStatus()
        append("① 测试按钮成功 → 计数 \(taps)，触摸是通的")
    }

    @objc private func pickDocx() {
        append("② 已点：准备弹文件选择器")
        var types: [UTType] = [.data]
        if let d = UTType(filenameExtension: "docx") { types.insert(d, at: 0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.delegate = self
        present(picker, animated: true) { self.append("文件选择器已弹出") }
    }

    @objc private func openInbox() {
        append("③ 已点：打开收件箱")
        let moved = Opener.drainInbox()
        reload()
        guard let first = moved.first else {
            append("收件箱是空的")
            let a = UIAlertController(title: "收件箱空的",
                                      message: "先把文件复制到「我的 iPhone → 快开 → 收件箱」，再来点这个按钮。",
                                      preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "好", style: .default))
            present(a, animated: true)
            return
        }
        append("收件箱找到 \(moved.count) 个，打开：\(first.lastPathComponent)")
        Router.shared.show(first)
    }

    @objc private func showLog() {
        append("④ 已点：看日志")
        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground
        let tv = UITextView(frame: vc.view.bounds)
        tv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tv.isEditable = false
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.text = Log.text()
        vc.view.addSubview(tv)
        vc.modalPresentationStyle = .pageSheet
        present(vc, animated: true) { self.append("日志面板已弹出") }
    }

    @objc private func selfTestSheet() {
        append("⑤ 已点：打开示例表格")
        let vc = DemoTableVC()
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true) { self.append("示例表格页已弹出") }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        append("选到 \(urls.count) 个：\(urls.map { $0.lastPathComponent }.joined(separator: ", "))")
        Router.shared.handle(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        append("文件选择器被取消")
    }
}

/// 纯内置数据的示例表格：不读文件、不依赖权限，只验证「表格界面能不能点、能不能改」。
final class DemoTableVC: UIViewController {
    private let bar = UIView()
    private let closeButton = UIButton(type: .system)
    private let infoLabel = UILabel()
    private let scroll = UIScrollView()
    private var cells: [UILabel] = []
    private var values: [[String]] = [["姓名", "部门", "金额"],
                                      ["张三", "销售", "1200"],
                                      ["李四", "技术", "980"]]
    private var built = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1)
        bar.backgroundColor = UIColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1)
        view.addSubview(bar)
        closeButton.setTitle("关闭", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        bar.addSubview(closeButton)
        infoLabel.text = "示例表格 · 点格子改字（纯内置数据，不读文件）"
        infoLabel.font = .systemFont(ofSize: 12)
        infoLabel.textColor = UIColor(white: 1, alpha: 0.85)
        bar.addSubview(infoLabel)
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        Log.add("示例表格页已建立")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let top = view.safeAreaInsets.top
        let w = view.bounds.width
        bar.frame = CGRect(x: 0, y: top, width: w, height: 58)
        closeButton.frame = CGRect(x: 12, y: 6, width: 50, height: 28)
        infoLabel.frame = CGRect(x: 72, y: 6, width: w - 84, height: 30)
        scroll.frame = CGRect(x: 0, y: top + 58, width: w, height: view.bounds.height - top - 58)
        if !built { built = true; build(width: w) }
    }

    private func build(width: CGFloat) {
        let colW = (width - 32) / 3
        let rowH: CGFloat = 48
        for (r, row) in values.enumerated() {
            for (c, v) in row.enumerated() {
                let box = UIView(frame: CGRect(x: 16 + CGFloat(c) * colW,
                                              y: CGFloat(r) * rowH + 16,
                                              width: colW, height: rowH))
                box.backgroundColor = r == 0 ? UIColor(red: 0.9, green: 0.95, blue: 0.94, alpha: 1) : .white
                box.layer.borderWidth = 0.5
                box.layer.borderColor = UIColor(red: 0.8, green: 0.83, blue: 0.87, alpha: 1).cgColor
                let label = UILabel(frame: CGRect(x: 8, y: 6, width: colW - 16, height: rowH - 12))
                label.text = v
                label.font = .systemFont(ofSize: 15)
                label.isUserInteractionEnabled = false
                box.addSubview(label)
                let btn = UIButton(type: .custom)
                btn.frame = box.bounds
                btn.tag = r * 10 + c
                btn.addTarget(self, action: #selector(cellTapped(_:)), for: .touchUpInside)
                box.addSubview(btn)
                cells.append(label)
                scroll.addSubview(box)
            }
        }
        scroll.contentSize = CGSize(width: width, height: CGFloat(values.count) * rowH + 40)
        Log.add("示例表格已渲染 \(values.count) 行")
    }

    @objc private func cellTapped(_ sender: UIButton) {
        let r = sender.tag / 10
        let c = sender.tag % 10
        let alert = UIAlertController(title: "改格子",
                                      message: "第 \(r + 1) 行 第 \(c + 1) 列",
                                      preferredStyle: .alert)
        alert.addTextField { tf in tf.text = self.values[r][c] }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            guard let self else { return }
            let t = alert.textFields?.first?.text ?? ""
            self.values[r][c] = t
            self.built = false
            self.scroll.subviews.forEach { $0.removeFromSuperview() }
            self.build(width: self.view.bounds.width)
            self.built = true
            Log.add("示例表格改了 [\(r)][\(c)] → \(t)")
        })
        present(alert, animated: true)
    }

    @objc private func close() { dismiss(animated: true) }
}
