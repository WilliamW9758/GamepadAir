import AppKit
import SwiftUI

/// A non-activating companion panel stays visible while System Settings is frontmost.
@MainActor
final class AccessibilityHelper {
    static let shared = AccessibilityHelper()
    private var panel: NSPanel?
    private var permissionTimer: Timer?
    private var initiallyAllowed = false
    private var settingsBounds: CGRect?

    func show() {
        if panel == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 110),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            window.title = "Allow Gamepad Air"
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isFloatingPanel = true
            window.level = .floating
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            // Background window dragging takes precedence over SwiftUI's file drag.
            // The helper follows Settings automatically; only its app row should drag.
            window.isMovableByWindowBackground = false
            window.isMovable = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: AccessibilityHelperView(close: { [weak self] in self?.dismiss() }))
            panel = window
        }
        guard let panel else { return }
        if !panel.isVisible, let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 32))
        }
        settingsBounds = nil
        initiallyAllowed = KeyboardMousePermissions.allowed
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.alignWithSettings()
                if (!self.initiallyAllowed && KeyboardMousePermissions.allowed) || self.panel?.isVisible != true { self.dismiss() }
            }
        }
    }

    // Window geometry is enough; this does not inspect Settings content or request Accessibility.
    private func alignWithSettings() {
        guard let panel,
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let info = windows.first(where: {
                  ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) &&
                  ($0[kCGWindowLayer as String] as? Int) == 0
              }),
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              rect.width > 400, rect.height > 200,
              rect != settingsBounds,
              let desktopTop = NSScreen.screens.first?.frame.maxY else { return }
        settingsBounds = rect
        let window = CGRect(x: rect.minX, y: desktopTop - rect.maxY, width: rect.width, height: rect.height)
        let screen = NSScreen.screens.max { $0.frame.intersection(window).width * $0.frame.intersection(window).height < $1.frame.intersection(window).width * $1.frame.intersection(window).height }
        guard let visible = screen?.visibleFrame else { return }
        // Right-align with the list pane, leaving its sidebar unobstructed.
        let x = min(max(window.maxX - panel.frame.width - 20, visible.minX + 12), visible.maxX - panel.frame.width - 12)
        let y = max(visible.minY + 12, window.minY - panel.frame.height - 12)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func dismiss() {
        permissionTimer?.invalidate(); permissionTimer = nil
        panel?.orderOut(nil)
    }
}

private struct AccessibilityHelperView: View {
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("Drag into Accessibility, then enable.")
                    .font(.system(size: 13))
                Spacer(minLength: 4)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24).contentShape(Circle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Close permission helper")
            }
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable().frame(width: 20, height: 20)
                Text("Gamepad Air").font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 10).frame(height: 40)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
            .contentShape(Rectangle())
            .overlay { PermissionAppDragSource(onDrop: close) }
            .accessibilityLabel("Gamepad Air application. Drag into the Accessibility permissions list.")
        }
        .padding(14).frame(width: 460, height: 110)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
    }
}

/// AppKit exposes drag completion, unlike SwiftUI's onDrag provider callback.
private struct PermissionAppDragSource: NSViewRepresentable {
    let onDrop: () -> Void
    func makeNSView(context: Context) -> PermissionAppDragView {
        let view = PermissionAppDragView(); view.onDrop = onDrop; return view
    }
    func updateNSView(_ view: PermissionAppDragView, context: Context) { view.onDrop = onDrop }
}

private final class PermissionAppDragView: NSView, NSDraggingSource {
    var onDrop: (() -> Void)?
    private var dragging = false
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { dragging = false }
    override func mouseDragged(with event: NSEvent) {
        guard !dragging else { return }
        dragging = true
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        let image = NSImage(size: bounds.size, flipped: false) { rect in
            NSColor.controlBackgroundColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
            NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
                .draw(in: NSRect(x: 10, y: (rect.height - 20) / 2, width: 20, height: 20))
            ("Gamepad Air" as NSString).draw(at: NSPoint(x: 40, y: (rect.height - 16) / 2),
                withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
            return true
        }
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        // A cancelled or rejected drop keeps the helper available for another try.
        if !operation.isEmpty { onDrop?() }
    }
}
