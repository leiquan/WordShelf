import SwiftUI
import AppKit
import ApplicationServices
import UniformTypeIdentifiers

final class Model: ObservableObject {
    @Published var words: [Word] = []
    @Published var status = "正在启动…"
    @Published var authorized = false
    let store: Store?
    let collector = LookupCollector()
    private var drafts: [String: String] = [:]
    init() {
        // Finder uses Info.plist; this also supplies the icon when running the package in Xcode.
        let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
        if let iconURL, let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WordShelf")
        do { store = try Store(url: folder.appendingPathComponent("words.sqlite")) }
        catch { store = nil; status = "无法打开单词清单：\(error.localizedDescription)" }
        reload()
        collector.onPermission = { [weak self] trusted in
            guard let self else { return }
            if self.authorized != trusted { self.authorized = trusted }
        }
        collector.onStatus = { [weak self] message in
            guard let self, self.store != nil else { return }
            self.status = message
        }
        collector.onWord = { [weak self] word in
            guard let self, let store = self.store else { return }
            do { try store.save(word); self.reload(); self.status = "已记录：\(word)" }
            catch { self.status = "单词保存失败：\(error.localizedDescription)" }
        }
        collector.start()
    }
    func reload() { do { words = try store?.all() ?? [] } catch { status = "无法读取单词清单：\(error.localizedDescription)" } }
    func stageMeaning(_ word: String, value: String) { drafts[word] = value }
    func saveMeaning(_ word: String, value: String) {
        drafts[word] = value
        _ = commitDrafts()
    }
    @discardableResult func commitDrafts() -> Bool {
        guard let store else { return drafts.isEmpty }
        guard !drafts.isEmpty else { return true }
        do {
            for (word, value) in drafts { try store.setMeaning(word, value: value) }
            drafts.removeAll(); reload(); return true
        } catch { status = "中文含义保存失败：\(error.localizedDescription)"; return false }
    }
    func clearWords() {
        guard let store, !words.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "清空单词清单？"
        alert.informativeText = "将删除所有单词及中文含义，此操作无法撤销。如需保留，请先导出 CSV。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "清空单词")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do {
            try store.clearAll()
            drafts.removeAll(); reload(); status = "单词清单已清空"
        } catch { status = "单词清单清空失败：\(error.localizedDescription)" }
    }
    func exportCSV() {
        guard commitDrafts() else { return }
        guard let store else { status = "无法导出，单词清单不可用"; return }
        let panel = NSSavePanel()
        panel.title = "导出单词清单"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "WordShelf.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let csv = try store.exportCSV()
            try csv.write(to: url, atomically: true, encoding: .utf8)
            status = "已导出：\(url.lastPathComponent)"
        } catch { status = "单词清单导出失败：\(error.localizedDescription)" }
    }
    func permission() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        refreshPermission()
    }
    func refreshPermission() { collector.checkPermission() }
    func checkPermissionWithFeedback() {
        refreshPermission()
        let alert = NSAlert()
        if authorized {
            alert.alertStyle = collector.isMonitoring ? .informational : .warning
            alert.messageText = collector.isMonitoring ? "辅助功能已授权" : "已获授权，但单词记录未启动"
            alert.informativeText = collector.isMonitoring
                ? "单词记录已启用。"
                : "请退出并重新打开 WordShelf，然后检查权限。"
            alert.addButton(withTitle: "好")
            alert.runModal()
        } else {
            alert.alertStyle = .warning
            alert.messageText = "未获辅助功能授权，无法记录单词"
            alert.informativeText = ""
            alert.addButton(withTitle: "打开辅助功能设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
                if !NSWorkspace.shared.open(url) {
                    let failure = NSAlert()
                    failure.messageText = "无法打开辅助功能设置"
                    failure.informativeText = "请前往“系统设置”→“隐私与安全性”→“辅助功能”。"
                    failure.addButton(withTitle: "好")
                    failure.runModal()
                }
            }
        }
    }
    func revealApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
}
@main struct WordShelfApp: App {
    @StateObject private var model = Model()
    @NSApplicationDelegateAdaptor(ShelfDelegate.self) private var delegate
    var body: some Scene {
        Window("WordShelf", id: "word-list") {
            ShelfView(model: model)
                .onAppear {
                    delegate.model = model
                    NSApp.setActivationPolicy(.regular)
                }
                .onDisappear {
                    model.commitDrafts()
                    NSApp.setActivationPolicy(.accessory)
                }
        }.defaultSize(width: 760, height: 560)
        MenuBarExtra {
            ShelfMenu(model: model)
        } label: {
            Image(nsImage: MenuIcon.image)
        }.menuBarExtraStyle(.menu)
    }
}

private struct ShelfMenu: View {
    @ObservedObject var model: Model
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.status)
        Button("显示单词清单") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "word-list")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("关于 WordShelf") { showAbout() }
        Divider()
        Button("退出 WordShelf") { NSApp.terminate(nil) }
    }
}

private struct ShelfView: View {
    @ObservedObject var model: Model
    var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("单词清单").font(.title2.bold())
                    Spacer()
                    Text("共 \(model.words.count) 个单词")
                    Button("清空单词") { model.clearWords() }.disabled(model.words.isEmpty || model.store == nil)
                    Button("导出 CSV") { model.exportCSV() }.disabled(model.words.isEmpty || model.store == nil)
                }
                Text("右键点击英文单词，选择“Look Up／查询”后自动记录。中文含义可手动填写。").font(.callout)
                Text(model.status).foregroundStyle(.secondary).textSelection(.enabled)
                if !model.authorized {
                    HStack {
                        Button("授权辅助功能访问") { model.permission() }
                        Button("在 Finder 中显示当前 App") { model.revealApp() }
                        Button("检查权限") { model.checkPermissionWithFeedback() }
                    }
                    Text("当前 App：\(Bundle.main.bundleURL.path)")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                HStack {
                    Text("单词").frame(width: 170, alignment: .leading)
                    Text("中文含义").frame(maxWidth: .infinity, alignment: .leading)
                }.font(.headline).padding(.horizontal, 12)
                if model.words.isEmpty {
                    Text("暂无单词")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.words.enumerated()), id: \.element.id) { index, word in
                            HStack(alignment: .top, spacing: 16) {
                                Text(word.text).textSelection(.enabled).frame(width: 170, alignment: .leading)
                                MeaningCell(word: word,
                                    onEdit: { model.stageMeaning(word.text, value: $0) },
                                    onSave: { model.saveMeaning(word.text, value: $0) })
                            }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: NSColor.alternatingContentBackgroundColors[index % 2]))
                        }
                    }
                }
                }
            }.padding(20).frame(minWidth: 680, minHeight: 480)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshPermission() }
    }
}

private final class ShelfDelegate: NSObject, NSApplicationDelegate {
    weak var model: Model?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.commitDrafts() == false ? .terminateCancel : .terminateNow
    }
}

private struct MeaningCell: View {
    let word: Word
    let onEdit: (String) -> Void
    let onSave: (String) -> Void
    @State private var hovered = false
    @State private var draft: String
    @FocusState private var focused: Bool
    init(word: Word, onEdit: @escaping (String) -> Void, onSave: @escaping (String) -> Void) {
        self.word = word; self.onEdit = onEdit; self.onSave = onSave
        _draft = State(initialValue: word.meaning)
    }
    var body: some View {
        Group {
            if hovered || focused {
                TextField("输入中文含义", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .accessibilityLabel("\(word.text)的中文含义")
                    .onSubmit { commit(); focused = false }
            } else {
                Text(word.meaning.isEmpty ? "—" : word.meaning)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .onTapGesture { hovered = true; focused = true }
            .onChange(of: draft) { onEdit($0) }
            .onChange(of: focused) { if !$0 { commit() } }
            .onChange(of: word.meaning) { if !focused { draft = $0 } }
    }
    private func commit() {
        if draft != word.meaning { onSave(draft) }
    }
}

private func showAbout() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationName: "WordShelf",
        .credits: NSAttributedString(string: "作者：leiquan@live.com")
    ])
}
