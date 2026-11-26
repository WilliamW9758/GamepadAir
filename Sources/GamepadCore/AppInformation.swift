import Foundation

/// Shared release information; also used by the offline privacy screens.
public enum AppInformation {
    public static let supportURL = URL(string: "https://github.com/WilliamW9758/GamepadAir/issues")!
    public static let projectURL = URL(string: "https://github.com/WilliamW9758/GamepadAir")!
    public static let iPhoneBetaURL = URL(string: "https://testflight.apple.com/join/ZaVJEpX3")!
    public static let macDownloadURL = URL(string: "https://gamepadair.com/#get-started")!
    public static let privacy = """
    Gamepad Air privacy policy
    Effective November 26, 2026

    Gamepad Air is an iPhone controller with a Mac companion. Core controller use does not require an account. The Mac marketplace supports browsing, downloading, and optional signed-in layout submissions. AI generation is not enabled.

    Your devices
    Controller input travels to the Mac you connect to over USB, local Wi-Fi, or Bluetooth. Wireless discovery advertises a generated device name. Connection addresses and pairing codes are stored locally. Local Network and Bluetooth permissions allow these connections. Mac Accessibility permission allows Gamepad Air to generate the keyboard and mouse inputs you configure.

    Local storage
    Layouts, bindings, preferences, and recovery copies are saved on your devices. The Mac keeps a local diagnostic log of Gamepad Air-generated input, timing, pointer positions, and process identifiers. While the app is running, this log is limited to the most recent five minutes and at most 512,000 bytes. A saved log may remain on disk after the app quits; expired entries are pruned when logging starts again. It does not record physical keyboard typing. These files are not automatically uploaded. Local data may be included in backups managed by your operating system.

    Marketplace and updates
    Marketplace requests go to the Gamepad Air service. Signing in on the Mac uses Sign in with Apple through Amazon Cognito. The Mac stores authentication credentials in Keychain; they are not sent to the paired iPhone. Submitting a layout sends the selected layout and its listing information to the service for review. Approved submissions can be downloaded publicly. Controller input and local diagnostic logs are not automatically uploaded to the marketplace.

    The Mac checks an update feed hosted on GitHub and downloads signed updates from GitHub Releases. These network requests expose normal connection information, such as your IP address, to the hosting service. You can disable automatic update checks and installation in General settings. iPhone beta updates are provided through Apple's TestFlight.

    Optional usage and diagnostics
    In versions with optional diagnostics, each device asks whether you want to share basic usage and diagnostics. Sharing is off until you agree. If enabled, the app sends aggregated connection outcomes, connection setup/recovery and Mac input-processing timing buckets, setup progress, and Mac update results to the Gamepad Air service on AWS. Reports include hardware model (for example iPhone18,4), OS version, app build, platform and connection type. We do not include your personal device name, serial number, persistent device or installation identifier, account identifier, game names, layouts, controller input, or local input logs. Phone and Mac consent are separate; Mac permission does not authorize uploading phone information.

    Counts are batched in memory and normally sent every five minutes, or when leaving the app or installing an update. Failed uploads are discarded, not retried. The service stores combined daily counters rather than individual activity records, retained for 30 days; database backups may retain expired aggregates for up to seven additional days. Normal network routing exposes the source IP to our hosting provider, but our diagnostics database does not store it, and diagnostics are not joined with account records or used for advertising. Turning sharing off clears unsent counts and cancels pending requests. Previously received daily aggregates cannot be separated back into individual users for deletion. You can change your choice in Settings → Diagnostics on iPhone or General → Diagnostics on Mac. Declining does not affect app functionality.

    Sharing and support
    Layout export creates a file only when you request it. You choose where to save or share it. Files and support reports you publish on GitHub are handled by GitHub and may be public. Review them before sharing; do not include pairing codes or private information. Opening external support links is subject to that service's privacy policy.

    Your choices
    Disconnect to stop controller input. Revoke permissions in system settings. Remove exported files from the locations you chose. Removing the iPhone app deletes its local app data, but not independent exports or backups. Mac settings and diagnostic files may remain after deleting the app; contact support for removal instructions. Signing out clears local sign-in credentials; it does not delete marketplace submissions. Manage submissions from My submissions on the Mac. Contact support for account-data requests.

    Contact
    Contact the Gamepad Air maintainer through the support link.
    """
}
