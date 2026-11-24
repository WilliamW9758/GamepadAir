import SwiftUI

/// Fires the hold when its timer recognizes the gesture, not on finger-up.
struct SettingsHandleGestures: UIViewRepresentable {
    var onTap: () -> Void
    var onHold: () -> Void
    var onDrag: (CGSize) -> Void
    var onEnd: (CGSize?) -> Void
    func makeUIView(context: Context) -> Handle {
        let view = Handle(); view.actions = self; return view
    }
    func updateUIView(_ view: Handle, context: Context) { view.actions = self }
    final class Handle: UIView {
        var actions: SettingsHandleGestures?
        override init(frame: CGRect) {
            super.init(frame: frame)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
            pan.maximumNumberOfTouches = 1
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.minimumPressDuration = 0.5; hold.allowableMovement = 8
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.require(toFail: pan); tap.require(toFail: hold)
            addGestureRecognizer(pan); addGestureRecognizer(hold); addGestureRecognizer(tap)
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        @objc private func tapped() { actions?.onTap() }
        @objc private func held(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began { actions?.onHold() }
        }
        @objc private func drag(_ gesture: UIPanGestureRecognizer) {
            let delta = gesture.translation(in: window)
            let size = CGSize(width: delta.x, height: delta.y)
            switch gesture.state {
            case .began, .changed: actions?.onDrag(size)
            case .ended: actions?.onEnd(size)
            case .cancelled, .failed: actions?.onEnd(nil)
            default: break
            }
        }
    }
}
