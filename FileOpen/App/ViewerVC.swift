import UIKit
import QuickLook
import PDFKit
import AVKit
import UniformTypeIdentifiers

/// 预览页：顶部蓝色信息栏（文件名 · 类型 · 大小 · 关闭），下面按类型选查看器：
/// 图片 → UIScrollView + UIImageView（缩放）
/// 文本/md/csv/json → UITextView
/// PDF → PDFView
/// 音视频 → AVPlayerViewController
/// 其它 → QuickLook（系统兜底）
/// 这样即便系统 QuickLook 某些格式渲染不出来，也有自己的查看器顶上。
final class ViewerVC: UIViewController, QLPreviewControllerDataSource {
    private let fileURL: URL
    private let bar = UIView()
    private let nameLabel = UILabel()
    private let infoLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private var content: UIView!
    private var childVC: UIViewController?

    init(url: URL) {
        fileURL = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        bar.backgroundColor = UIColor(red: 0.06, green: 0.35, blue: 0.75, alpha: 1)
        view.addSubview(bar)

        nameLabel.text = fileURL.lastPathComponent
        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.numberOfLines = 2
        bar.addSubview(nameLabel)

        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        infoLabel.text = (exists ? "已打开" : "文件不存在")
            + " · \(typeName()) · \(Sz.human(Sz.of(fileURL)))"
        infoLabel.font = .systemFont(ofSize: 12)
        infoLabel.textColor = UIColor(white: 1, alpha: 0.85)
        bar.addSubview(infoLabel)

        closeButton.setTitle("关闭", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        bar.addSubview(closeButton)

        content = buildContent()
        view.addSubview(content)

        Log.add("预览页已建立：\(fileURL.lastPathComponent)（\(infoLabel.text ?? "")）")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let top = view.safeAreaInsets.top
        let w = view.bounds.width
        bar.frame = CGRect(x: 0, y: top, width: w, height: 62)
        closeButton.frame = CGRect(x: w - 66, y: 8, width: 54, height: 30)
        nameLabel.frame = CGRect(x: 16, y: 6, width: w - 90, height: 32)
        infoLabel.frame = CGRect(x: 16, y: 35, width: w - 90, height: 18)
        content.frame = CGRect(x: 0, y: top + 62, width: w, height: view.bounds.height - top - 62)
        relayoutContent()
    }

    // MARK: - 按类型建查看器

    private func buildContent() -> UIView {
        let ext = fileURL.pathExtension.lowercased()
        let images = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif", "ico"]
        let texts = ["txt", "md", "markdown", "json", "csv", "tsv", "log", "html", "htm", "xml",
                     "yaml", "yml", "swift", "py", "js", "ts", "jsx", "tsx", "sh", "ini", "conf", "plist"]
        let medias = ["mp4", "mov", "m4v", "mp3", "m4a", "wav", "aac", "flac", "caf", "aiff", "m4b"]

        if images.contains(ext) || ext.isEmpty {
            if let image = UIImage(contentsOfFile: fileURL.path) {
                return makeImage(image)
            }
            return makeNotice("这个图片解码不了（格式不支持或文件损坏）")
        }
        if ext == "pdf" {
            if let pdf = PDFDocument(url: fileURL) {
                return makePDF(pdf)
            }
            return makeNotice("这个 PDF 打不开（可能损坏）")
        }
        if texts.contains(ext) {
            return makeText()
        }
        if medias.contains(ext) {
            return makeMedia()
        }
        return makeQuickLook()
    }

    private func relayoutContent() {
        if let scroll = content as? UIScrollView {
            if let imageView = scroll.subviews.first as? UIImageView, let image = imageView.image {
                let fit = min(scroll.bounds.width / max(image.size.width, 1),
                              scroll.bounds.height / max(image.size.height, 1))
                let s = max(fit, 1.0)
                imageView.frame = CGRect(x: 0, y: 0,
                                         width: image.size.width * s,
                                         height: image.size.height * s)
                scroll.contentSize = imageView.frame.size
            }
        }
    }

    private func makeImage(_ image: UIImage) -> UIView {
        let scroll = UIScrollView()
        scroll.backgroundColor = .black
        scroll.maximumZoomScale = 4
        scroll.minimumZoomScale = 0.5
        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        scroll.addSubview(iv)
        Log.add("查看器：图片 \(Int(image.size.width))x\(Int(image.size.height))")
        return scroll
    }

    private func makeText() -> UIView {
        let tv = UITextView()
        tv.isEditable = false
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.text = decodeText() ?? "读不出这段文字（编码不支持或文件过大）"
        tv.backgroundColor = UIColor(red: 0.99, green: 0.99, blue: 1, alpha: 1)
        Log.add("查看器：文本 \(tv.text.count) 字")
        return tv
    }

    private func decodeText() -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let head = data.prefix(8 * 1024 * 1024)
        if let s = String(data: head, encoding: .utf8) { return s }
        if let s = String(data: head, encoding: .init(rawValue: 0x80000632)) { return s }
        if let s = String(data: head, encoding: .utf16) { return s }
        if let s = String(data: head, encoding: .isoLatin1) { return s }
        return nil
    }

    private func makePDF(_ doc: PDFDocument) -> UIView {
        let pw = PDFView()
        pw.backgroundColor = .white
        pw.document = doc
        pw.autoScales = true
        pw.displayMode = .singlePageContinuous
        Log.add("查看器：PDF \(doc.pageCount) 页")
        return pw
    }

    private func makeMedia() -> UIView {
        let player = AVPlayer(url: fileURL)
        let av = AVPlayerViewController()
        av.player = player
        av.showsPlaybackControls = true
        addChild(av)
        childVC = av
        av.didMove(toParent: self)
        player.play()
        Log.add("查看器：音视频")
        return av.view
    }

    private func makeQuickLook() -> UIView {
        let ql = QLPreviewController()
        ql.dataSource = self
        addChild(ql)
        childVC = ql
        ql.didMove(toParent: self)
        Log.add("查看器：系统 QuickLook")
        return ql.view
    }

    private func makeNotice(_ message: String) -> UIView {
        let label = UILabel()
        label.text = message
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.backgroundColor = .systemBackground
        return label
    }

    @objc private func closeTapped() {
        Log.add("用户关闭预览")
        dismiss(animated: true)
    }

    private func typeName() -> String {
        let ext = fileURL.pathExtension
        if let t = UTType(filenameExtension: ext), let n = t.localizedDescription { return n }
        return ext.isEmpty ? "文件" : ext.uppercased()
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        fileURL as NSURL
    }
}
