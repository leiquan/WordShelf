import AppKit
import ApplicationServices

func axValue(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value
}

/// Watches mouse clicks without suppressing or synthesizing system events.
/// Only an actual click in a quoted Look Up menu item is eligible for collection.
final class LookupCollector {
    var onWord: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    var onPermission: ((Bool) -> Void)?
    private let trustCheck: () -> Bool
    private var monitor: Any?
    var isMonitoring: Bool { monitor != nil }
    private var permissionTimer: Timer?
    private var trusted: Bool?
    private var lastStatus: String?
    private var generation = 0
    private let queue = DispatchQueue(label: "local.wordshelf.lookup", qos: .userInteractive)
    // Only accessed by the serial queue below.
    private var pending: MenuClick?
    private var contextPID: pid_t?
    private var contextTime: TimeInterval = 0
    private let system = AXUIElementCreateSystemWide()
    private struct Click {
        let type: NSEvent.EventType
        let point: CGPoint
        let control: Bool
        let timestamp: TimeInterval
        let pid: pid_t?
        let generation: Int
    }
    init(trustCheck: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.trustCheck = trustCheck
        AXUIElementSetMessagingTimeout(system, 0.06)
    }
    func start() {
        stop()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkPermission() }
        checkPermission()
    }
    func stop() {
        generation += 1
        permissionTimer?.invalidate(); permissionTimer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; trusted = nil; lastStatus = nil
        queue.async { [weak self] in self?.pending = nil; self?.contextPID = nil }
    }
    deinit { stop() }
    private func sendStatus(_ value: String) {
        guard value != lastStatus else { return }
        lastStatus = value; onStatus?(value)
    }
    func checkPermission() {
        let value = trustCheck()
        if trusted != value { trusted = value; onPermission?(value) }
        guard value else {
            if let monitor { NSEvent.removeMonitor(monitor); generation += 1 }
            monitor = nil
            queue.async { [weak self] in self?.pending = nil; self?.contextPID = nil }
            sendStatus("未获辅助功能授权，无法记录单词")
            return
        }
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown, .leftMouseUp]) { [weak self] event in self?.capture(event) }
        sendStatus(monitor == nil ? "无法启动单词记录，请重新打开 WordShelf" : "单词记录已启用")
    }
    private func capture(_ event: NSEvent) {
        guard trusted == true, let point = event.cgEvent?.location else { return }
        let isContext = event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        let click = Click(type: event.type, point: point, control: event.modifierFlags.contains(.control),
                          timestamp: event.timestamp, pid: isContext ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil,
                          generation: generation)
        queue.async { [weak self] in self?.handle(click) }
    }
    private func handle(_ click: Click) {
        if click.type == .rightMouseDown || (click.type == .leftMouseDown && click.control) {
            pending = nil; contextPID = click.pid; contextTime = click.timestamp; return
        }
        if click.type == .leftMouseUp {
            let candidate = pending; pending = nil
            guard let candidate, let word = candidate.released(at: click.point, timestamp: click.timestamp) else { return }
            contextPID = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, self.generation == click.generation, AXIsProcessTrusted() else { return }
                self.onWord?(word)
            }
            return
        }
        guard click.type == .leftMouseDown else { return }
        pending = nil
        guard let pid = contextPID, click.timestamp - contextTime >= 0, click.timestamp - contextTime < 30 else { return }
        // Only the first click after opening a context menu needs AX inspection.
        contextPID = nil
        pending = inspect(click, owner: pid)
    }
    private func inspect(_ click: Click, owner pid: pid_t) -> MenuClick? {
        let deadline = CFAbsoluteTimeGetCurrent() + 0.2
        func read(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            let remaining = deadline - CFAbsoluteTimeGetCurrent()
            guard remaining > 0 else { return nil }
            AXUIElementSetMessagingTimeout(element, Float(min(0.04, remaining)))
            return axValue(element, key)
        }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(click.point.x), Float(click.point.y), &hit) == .success, let hit else { return nil }
        var item = hit
        for _ in 0..<3 {
            if read(item, kAXRoleAttribute) as? String == kAXMenuItemRole { break }
            guard let parent = read(item, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            item = parent as! AXUIElement
        }
        guard read(item, kAXRoleAttribute) as? String == kAXMenuItemRole,
              let title = read(item, kAXTitleAttribute) as? String,
              let word = LookupTitle.word(title),
              (read(item, kAXEnabledAttribute) as? Bool) == true else { return nil }
        var owner: pid_t = 0
        guard AXUIElementGetPid(item, &owner) == .success, owner == pid,
              let parent = read(item, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID(),
              read(parent as! AXUIElement, kAXRoleAttribute) as? String == kAXMenuRole else { return nil }
        guard let originValue = read(item, kAXPositionAttribute), CFGetTypeID(originValue) == AXValueGetTypeID(),
              let sizeValue = read(item, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(originValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        let bounds = CGRect(origin: origin, size: size)
        guard bounds.contains(click.point) else { return nil }
        return MenuClick(word: word, bounds: bounds, timestamp: click.timestamp)
    }
}
