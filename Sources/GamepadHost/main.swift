import Foundation
import MacSupport

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--help") {
    print("Usage: gamepad-host [--monitor | --gamepad | --probe] [--device USB-UDID]\nDefault: input monitor. Control-C releases controls and exits.")
    exit(0)
}
if args.contains("--probe") {
    print(CableSession.gamepadAuthorized ? "Virtual HID entitlement present. Game recognition still requires testing." : "Virtual HID entitlement absent. Monitor mode is available; gamepad output needs an Apple-authorized signing profile.")
    exit(CableSession.gamepadAuthorized ? 0 : 2)
}
var serial: String?
if let index = args.firstIndex(of: "--device") {
    guard index + 1 < args.count else { fputs("--device needs a USB UDID\n", stderr); exit(1) }
    serial = args[index + 1]
}
let mode: OutputMode = args.contains("--gamepad") ? .gamepad : .monitor
if mode == .gamepad && !CableSession.gamepadAuthorized {
    fputs("Virtual HID is not authorized. See docs/SETUP.md; use --monitor to test USB.\n", stderr)
    exit(2)
}
var lastMessage = ""
let session = CableSession(mode: mode, serial: serial) { event in
    if event.message != lastMessage || event.frames % 60 == 1 {
        print("\(event.message) | frames=\(event.frames) buttons=\(event.state.buttons) L=(\(event.state.leftX),\(event.state.leftY)) R=(\(event.state.rightX),\(event.state.rightY))")
        fflush(stdout)
        lastMessage = event.message
    }
}
signal(SIGINT, SIG_IGN); signal(SIGTERM, SIG_IGN)
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
func finish() { session.stop(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) } }
interrupt.setEventHandler(handler: finish); terminate.setEventHandler(handler: finish)
interrupt.resume(); terminate.resume()
session.start()
RunLoop.main.run()
