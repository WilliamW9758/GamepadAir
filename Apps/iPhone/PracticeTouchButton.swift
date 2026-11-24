import SwiftUI
import UIKit

struct PracticeTouchButton: UIViewRepresentable {
    var changed: (Bool) -> Void
    func makeUIView(context: Context) -> TouchButton { let view = TouchButton(); view.changed = changed; return view }
    func updateUIView(_ view: TouchButton, context: Context) { view.changed = changed }
    final class TouchButton: UIView {
        var changed: (Bool) -> Void = { _ in }
        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = true; accessibilityLabel = "Practice A button"; accessibilityTraits = .button
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { changed(true) }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { changed(false) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { changed(false) }
        override func accessibilityActivate() -> Bool {
            changed(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.changed(false) }
            return true
        }
    }
}
