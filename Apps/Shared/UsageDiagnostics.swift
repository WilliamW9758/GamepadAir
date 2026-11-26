import SwiftUI
import Foundation
import Darwin

/// Per-device consent. Batches are memory-only, bounded, best effort, and never retried.
/// This session has no account cookies, authorization header or device/install identifier.
@MainActor
final class UsageDiagnostics: ObservableObject {
    static let shared = UsageDiagnostics()
    static let explanation = "Share connection reliability, setup progress, update results, and performance summaries, along with your hardware model, OS version, and app build. We don’t send your button presses, layouts, game names, account details, or a persistent device ID. Sharing is optional and can be turned off in Settings."
    @Published private(set) var choice: String
    private var buffer = UsageMetricBuffer()
    private var request: URLSessionDataTask?
    private var requestID = UUID()
    private let session: URLSession
    private var timer: Task<Void, Never>?
    private let defaults: UserDefaults
    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        choice = defaults.string(forKey: "usage-diagnostics-consent-v1") ?? "undecided"
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCache = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
        buffer.setEnabled(choice == "allowed")
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                if Task.isCancelled { break }
                self?.flush()
            }
        }
    }
    var allowed: Bool { choice == "allowed" }
    var needsConsent: Bool { choice == "undecided" }
    func choose(_ allowed: Bool) {
        choice = allowed ? "allowed" : "declined"
        defaults.set(choice, forKey: "usage-diagnostics-consent-v1")
        buffer.setEnabled(allowed)
        requestID = UUID(); request?.cancel(); request = nil
        // Never report an update that occurred before permission was granted.
        defaults.removeObject(forKey: "usage-update-target")
    }
    func record(_ event: UsageMetric, transport: String = "none", milliseconds: Double? = nil) {
        buffer.record(event, transport: transport, milliseconds: milliseconds)
    }
    func installingUpdate(_ version: String) {
        guard allowed else { return }
        defaults.set(version, forKey: "usage-update-target")
        record(.updateInstallRequested); flush()
    }
    func checkInstalledUpdate() {
        guard allowed, let target = defaults.string(forKey: "usage-update-target"),
              let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else { return }
        if current.compare(target, options: .numeric) != .orderedAscending {
            record(.updateCompleted); defaults.removeObject(forKey: "usage-update-target")
        }
    }
    func flush() {
        guard allowed, request == nil else { return }
        let metrics = buffer.drain()
        guard !metrics.isEmpty else { return }
        #if os(iOS)
        let platform = "ios"
        #else
        let platform = "macos"
        #endif
        struct Batch: Encodable {
            let schema = 1
            let platform: String
            let build: String
            let os: String
            let model: String
            let metrics: [UsageMetricCount]
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let body = Batch(platform: platform, build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
                         os: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", model: Self.hardwareModel, metrics: metrics)
        var req = URLRequest(url: URL(string: "https://api.gamepadair.com/v1/telemetry")!)
        req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(body)
        let id = UUID(); requestID = id
        let task = session.dataTask(with: req) { [weak self] _, _, _ in
            Task { @MainActor in if self?.requestID == id { self?.request = nil } }
        }
        request = task; task.resume()
    }
    static var hardwareModel: String {
        #if targetEnvironment(simulator)
        return "Simulator"
        #else
        #if os(iOS)
        let key = "hw.machine"
        #else
        let key = "hw.model"
        #endif
        var length = 0
        guard sysctlbyname(key, nil, &length, nil, 0) == 0, length > 0, length < 128 else { return "Unknown" }
        var bytes = [CChar](repeating: 0, count: length)
        guard sysctlbyname(key, &bytes, &length, nil, 0) == 0 else { return "Unknown" }
        return String(cString: bytes)
        #endif
    }
}

struct DiagnosticsConsentModifier: ViewModifier {
    @ObservedObject private var diagnostics = UsageDiagnostics.shared
    let onReady: () -> Void
    @State private var showing = false
    func body(content: Content) -> some View {
        content.onAppear {
            if diagnostics.needsConsent { showing = true } else { onReady() }
        }
        .alert("Help improve Gamepad Air?", isPresented: $showing) {
            Button("Don’t Share", role: .cancel) { diagnostics.choose(false); onReady() }
            Button("Share Diagnostics") { diagnostics.choose(true); onReady() }
                .keyboardShortcut(.defaultAction)
                .tint(.blue)
        } message: { Text(UsageDiagnostics.explanation) }
        .tint(.blue)
    }
}
struct DiagnosticsSharingSetting: View {
    @ObservedObject private var diagnostics = UsageDiagnostics.shared
    var body: some View {
        Toggle("Share usage and diagnostics", isOn: Binding(get: { diagnostics.allowed }, set: diagnostics.choose))
        Text(UsageDiagnostics.explanation).font(.callout).foregroundStyle(.secondary)
    }
}
