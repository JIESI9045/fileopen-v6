import UIKit

/// 收文件 → 复制成本地副本 → 立刻弹预览。三条入口都走这里。
/// 另外：每次 App 变前台，先看「收件箱」有没有人手动放进去的文件，有就直接打开。
final class Router {
    static let shared = Router()
    weak var root: RootVC?
    private var openedFromInbox: Set<String> = []

    func handle(_ urls: [URL]) {
        let files = urls.filter { $0.isFileURL }
        guard !files.isEmpty else { Log.add("Router：没有有效的文件 URL（\(urls.count) 个）"); return }
        Log.add("Router 收到 \(files.count) 个：\(files.map { $0.lastPathComponent }.joined(separator: ", "))")
        Opener.noteReceived(files)

        for url in files {
            DispatchQueue.global(qos: .userInitiated).async {
                let local = Opener.localCopy(of: url)
                DispatchQueue.main.async { [weak self] in
                    self?.root?.reload()
                    if let local {
                        self?.show(local)
                    } else {
                        self?.alertFail(name: url.lastPathComponent)
                    }
                }
            }
        }
    }

    /// 收件箱自动打开（只自动开最新的一个，避免连环弹窗）
    func checkInbox() {
        DispatchQueue.global(qos: .userInitiated).async {
            let moved = Opener.drainInbox()
            DispatchQueue.main.async { [weak self] in
                self?.root?.reload()
                guard let first = moved.first else { return }
                guard let self else { return }
                guard !self.openedFromInbox.contains(first.path) else { return }
                self.openedFromInbox.insert(first.path)
                Log.add("收件箱自动打开：\(first.lastPathComponent)")
                self.show(first)
            }
        }
    }

    func show(_ url: URL) {
        guard let base = top() else { Log.add("没有可用窗口，预览跳过"); return }
        Log.add("弹出预览：\(url.lastPathComponent)")
        let ext = url.pathExtension.lowercased()
        let vc: UIViewController
        if ext == "docx" || ext == "doc" || ext == "docm" || ext == "dotx" {
            vc = DocxVC(url: url)
        } else {
            vc = ViewerVC(url: url)
        }
        vc.modalPresentationStyle = .fullScreen
        base.present(vc, animated: true) { Log.add("预览已弹出") }
    }

    private func alertFail(name: String) {
        let a = UIAlertController(title: "打不开这个文件",
                                  message: "已收到「\(name)」，但三种复制方式都失败。详情见「日志」或 运行日志.txt。",
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "好", style: .default))
        top()?.present(a, animated: true)
    }

    private func top() -> UIViewController? {
        var base: UIViewController?
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            let win = ws.windows.first(where: { $0.isKeyWindow }) ?? ws.windows.first
            base = win?.rootViewController
            if base != nil { break }
        }
        if base == nil { base = root }
        var t = base
        while let p = t?.presentedViewController { t = p }
        return t
    }
}
