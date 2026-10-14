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
    private var monitor: Any?
    var isMonitoring: Bool { monitor != nil }
    private var permissionTimer: Timer?
    private var pending: MenuClick?
    private var contextPID: pid_t?
    private var contextTime: TimeInterval = 0
    private let system = AXUIElementCreateSystemWide()

    init() { AXUIElementSetMessagingTimeout(system, 0.15) }
    func start() {
        stop()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkPermission() }
        checkPermission()
    }
    func stop() {
        permissionTimer?.invalidate(); permissionTimer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; pending = nil; contextPID = nil
    }
    deinit { stop() }
    func checkPermission() {
        let trusted = AXIsProcessTrusted()
        onPermission?(trusted)
        guard trusted else {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil; pending = nil; contextPID = nil
            onStatus?("暂无权限，无法记录")
            return
        }
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown, .leftMouseUp]) { [weak self] event in self?.handle(event) }
        onStatus?(monitor == nil ? "无法监听鼠标点击，请重新启动 App" : "正在监听：右键单词 → 点击 Look Up")
    }
    private func handle(_ event: NSEvent) {
        guard AXIsProcessTrusted() else { pending = nil; return }
        // CGEvent uses the same top-left global coordinates as AX hit testing.
        // Use the event location, not the current cursor location (which may have moved).
        guard let point = event.cgEvent?.location else { pending = nil; return }
        if event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            pending = nil
            contextPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            contextTime = event.timestamp
            return
        }
        if event.type == .leftMouseUp {
            let candidate = pending; pending = nil
            guard let candidate, let word = candidate.released(at: point, timestamp: event.timestamp) else { return }
            contextPID = nil
            // Persist after the click has completed. Do not activate our window or reopen Look Up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard AXIsProcessTrusted() else { return }
                self?.onWord?(word)
            }
            return
        }
        guard event.type == .leftMouseDown else { return }
        pending = nil
        guard let contextPID, event.timestamp - contextTime >= 0,
              event.timestamp - contextTime < 30 else { return }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, let hit else { return }
        AXUIElementSetMessagingTimeout(hit, 0.15)
        var item = hit
        // A menu label can be a child of AXMenuItem.
        for _ in 0..<3 {
            if axValue(item, kAXRoleAttribute) as? String == kAXMenuItemRole { break }
            guard let parent = axValue(item, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return }
            item = parent as! AXUIElement
        }
        guard axValue(item, kAXRoleAttribute) as? String == kAXMenuItemRole,
              let title = axValue(item, kAXTitleAttribute) as? String,
              let word = LookupTitle.word(title),
              (axValue(item, kAXEnabledAttribute) as? Bool) == true else { return }
        var owner: pid_t = 0
        guard AXUIElementGetPid(item, &owner) == .success, owner == contextPID,
              let parent = axValue(item, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID(),
              axValue(parent as! AXUIElement, kAXRoleAttribute) as? String == kAXMenuRole else { return }
        guard let originValue = axValue(item, kAXPositionAttribute), CFGetTypeID(originValue) == AXValueGetTypeID(),
              let sizeValue = axValue(item, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return }
        var origin = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(originValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return }
        let bounds = CGRect(origin: origin, size: size)
        guard bounds.contains(point) else { return }
        pending = MenuClick(word: word, bounds: bounds, timestamp: event.timestamp)
    }
}
