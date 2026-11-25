import Foundation
import IOKit
import IOKit.hidsystem
import Security
#if SWIFT_PACKAGE
import GamepadCore
#endif

public enum OutputMode: String, CaseIterable { case monitor = "Input monitor", keyboardMouse = "Keyboard / mouse", gamepad = "Virtual gamepad" }

protocol GamepadOutput: AnyObject {
    func submit(_ state: GamepadState) throws
    func pointer(_ frame: PointerFrame) throws
    func reset() throws
    func close()
}

extension GamepadOutput {
    func reset() throws { try submit(.neutral) }
    func pointer(_ frame: PointerFrame) throws {}
}

final class MonitorOutput: GamepadOutput {
    func submit(_ state: GamepadState) throws {}
    func close() {}
}

final class VirtualGamepadOutput: GamepadOutput {
    private let profile: GamepadProfile
    private var device: IOHIDUserDevice?
    private let reportLock = NSLock()
    private var report = Data()
    private let style: PadStyle
    private var sequence: UInt8 = 0
    private var rumble = RumbleFrame()
    func currentRumble() -> RumbleFrame {
        reportLock.lock(); defer { reportLock.unlock() }; return rumble
    }
    private let callbackQueue = DispatchQueue(label: "gamepad.hid.requests")

    static var hasEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.hid.virtual.device" as CFString, nil) as? Bool == true
    }

    init(profile: GamepadProfile = GamepadProfile(), style: PadStyle = .xbox) throws {
        self.profile = profile
        self.style = style
        guard Self.hasEntitlement else {
            throw LinkError.message("Gamepad output requires an Apple-authorized signing profile with com.apple.developer.hid.virtual.device. Input monitor works without it. See docs/SETUP.md.")
        }
        report = style == .playStation ? CompatibilityHIDReport.encode(.neutral) : XboxHIDReport.encode(.neutral)
        let properties: [String: Any] = [
            "ReportDescriptor": style == .playStation ? CompatibilityHIDReport.descriptor : XboxHIDReport.descriptor,
            "VendorID": style == .playStation ? 0x054C : 0x045E, "ProductID": style == .playStation ? 0x09CC : 0x0B13, "VersionNumber": 1,
            "Product": style == .playStation ? "Gamepad Air PlayStation Controller" : "Xbox Gamepad Air Wireless Controller", "Manufacturer": "Gamepad Air",
            "Transport": "Virtual", "PrimaryUsagePage": 1, "PrimaryUsage": 5
        ]
        guard let device = IOHIDUserDeviceCreateWithProperties(kCFAllocatorDefault, properties as CFDictionary, 1) else {
            throw LinkError.message("macOS refused virtual HID creation. Check the signing profile and any requested Accessibility permission.")
        }
        self.device = device
        IOHIDUserDeviceRegisterGetReportBlock(device) { [weak self] type, id, buffer, length in
            guard let self, type == kIOHIDReportTypeInput, id == 1 else { return kIOReturnUnsupported }
            self.reportLock.lock(); defer { self.reportLock.unlock() }
            guard length.pointee >= self.report.count else { return kIOReturnNoSpace }
            self.report.copyBytes(to: buffer, count: self.report.count)
            length.pointee = self.report.count
            return kIOReturnSuccess
        }
        IOHIDUserDeviceRegisterSetReportBlock(device) { [weak self] type, id, buffer, length in
            guard let self, type == kIOHIDReportTypeOutput else { return kIOReturnUnsupported }
            let data = Data(bytes: buffer, count: length)
            if let value = RumbleFrame.decodeHID(data, reportID: Int(id), style: self.style) {
                self.reportLock.lock(); self.rumble = value; self.reportLock.unlock()
                return kIOReturnSuccess
            }
            return self.style == .playStation && id == 5 ? kIOReturnSuccess : kIOReturnUnsupported
        }
        IOHIDUserDeviceSetDispatchQueue(device, callbackQueue)
        IOHIDUserDeviceActivate(device)
        do { try submit(.neutral) } catch { close(); throw error }
    }

    func submit(_ state: GamepadState) throws {
        guard let device else { return }
        let mapped = profile.apply(state)
        let next = style == .playStation ? CompatibilityHIDReport.encode(mapped, sequence: sequence) : XboxHIDReport.encode(mapped)
        sequence &+= 1
        reportLock.lock(); report = next; reportLock.unlock()
        let result = next.withUnsafeBytes { IOHIDUserDeviceHandleReportWithTimeStamp(device, mach_absolute_time(), $0.baseAddress!, next.count) }
        guard result == kIOReturnSuccess else { throw LinkError.message("Virtual HID report failed (\(result))") }
    }

    func close() {
        guard let device else { return }
        try? submit(.neutral)
        IOHIDUserDeviceCancel(device)
        self.device = nil
    }
    deinit { close() }
}
