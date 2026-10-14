import Foundation
import Darwin

enum LinkError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Owns an fd; shutdown interrupts a read without risking descriptor reuse.
final class StreamSocket {
    let fd: Int32
    init(fd: Int32) { self.fd = fd; var one: Int32 = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, 4) }
    deinit { Darwin.close(fd) }
    func interrupt() { shutdown(fd, SHUT_RDWR) }

    func readExactly(_ count: Int, timeout: TimeInterval) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        var offset = 0
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while offset < count {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw LinkError.message("Input timed out; controls released") }
            var item = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let result = poll(&item, 1, Int32(ceil(remaining * 1000)))
            if result < 0 && errno == EINTR { continue }
            guard result > 0 else { throw LinkError.message("Input timed out; controls released") }
            let n = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!.advanced(by: offset), count - offset) }
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw LinkError.message("Cable connection closed; controls released") }
            offset += n
        }
        return Data(bytes)
    }

    func write(_ data: Data) throws {
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < data.count {
                let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), data.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw LinkError.message("Could not write to USB connection") }
                offset += n
            }
        }
    }
}

struct USBDevice {
    let id: Int
    let serial: String
}

enum USBMux {
    private static func openSocket() throws -> StreamSocket {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LinkError.message("Could not open usbmuxd socket") }
        let connection = StreamSocket(fd: fd)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            target.copyBytes(from: Array("/var/run/usbmuxd".utf8) + [0])
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw LinkError.message("Apple usbmuxd is unavailable") }
        return connection
    }

    private static func request(_ message: [String: Any], on socket: StreamSocket) throws -> [String: Any] {
        var body = message
        body["ClientVersionString"] = "iPhoneGamepad/0.1"
        body["ProgName"] = "iPhoneGamepad"
        body["kLibUSBMuxVersion"] = 3
        let payload = try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
        var header = Data()
        for var word in [UInt32(payload.count + 16), 1, 8, 1].map({ $0.littleEndian }) {
            withUnsafeBytes(of: &word) { header.append(contentsOf: $0) }
        }
        try socket.write(header + payload)
        let h = Array(try socket.readExactly(16, timeout: 2))
        func word(_ i: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(h[i + $1]) << ($1 * 8) } }
        let length = Int(word(0))
        guard (16...1_048_576).contains(length), word(4) == 1, word(8) == 8, word(12) == 1 else {
            throw LinkError.message("Unexpected usbmuxd response")
        }
        let data = try socket.readExactly(length - 16, timeout: 2)
        guard let reply = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw LinkError.message("Invalid usbmuxd property list")
        }
        return reply
    }

    static func devices() throws -> [USBDevice] {
        let reply = try request(["MessageType": "ListDevices"], on: openSocket())
        guard let list = reply["DeviceList"] as? [[String: Any]] else { throw LinkError.message("Could not list USB devices") }
        return list.compactMap { item in
            guard let p = item["Properties"] as? [String: Any], p["ConnectionType"] as? String == "USB",
                  let id = item["DeviceID"] as? Int, let serial = p["SerialNumber"] as? String else { return nil }
            return USBDevice(id: id, serial: serial)
        }
    }

    static func connect(device: USBDevice, port: UInt16) throws -> StreamSocket {
        let socket = try openSocket()
        let reply = try request(["MessageType": "Connect", "DeviceID": device.id, "PortNumber": Int(port.bigEndian)], on: socket)
        guard reply["Number"] as? Int == 0 else {
            throw LinkError.message("Open the iPhone app, unlock your phone, and trust this Mac (USB error \(reply["Number"] ?? "unknown"))")
        }
        return socket
    }
}
