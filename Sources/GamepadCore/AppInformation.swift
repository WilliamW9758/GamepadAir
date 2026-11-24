import Foundation

/// Shared release information; also used by the offline privacy screens.
public enum AppInformation {
    public static let supportURL = URL(string: "https://github.com/WilliamW9758/PocketPad/issues")!
    public static let projectURL = URL(string: "https://github.com/WilliamW9758/PocketPad")!
    public static let privacy = """
    PocketPad privacy policy
    Effective November 23, 2026

    PocketPad is an iPhone controller with a Mac companion. This version has no accounts, advertising, analytics SDKs, cloud layout service, or AI service. The app does not upload your controls or layouts to the developer.

    Your devices
    Controller input travels to the Mac you connect to over USB, local Wi-Fi, or Bluetooth. Wireless discovery advertises a generated PocketPad name. Connection addresses and pairing codes are stored locally. Local Network and Bluetooth permissions allow these connections. Mac Accessibility permission allows PocketPad to generate the keyboard and mouse inputs you configure.

    Local storage
    Layouts, bindings, preferences, and recovery copies are saved on your devices. The Mac keeps a local diagnostic log of PocketPad-generated input, timing, pointer positions, and process identifiers. While the app is running, this log is limited to the most recent five minutes and at most 512,000 bytes. A saved log may remain on disk after the app quits; expired entries are pruned when logging starts again. It does not record physical keyboard typing. These files are not automatically uploaded. Local data may be included in backups managed by your operating system.

    Sharing and support
    Profile export creates a file only when you request it. You choose where to save or share it. Files and support reports you publish on GitHub are handled by GitHub and may be public. Review them before sharing; do not include pairing codes or private information. Opening external support links is subject to that service's privacy policy.

    Your choices
    Disconnect to stop controller input. Revoke permissions in system settings. Remove exported files from the locations you chose. Removing the iPhone app deletes its local app data, but not independent exports or backups. Mac settings and diagnostic files may remain after deleting the app; contact support for removal instructions. There is no PocketPad server account to delete.

    Contact
    Contact the PocketPad maintainer through the support link. This policy will be updated before introducing new data-handling features.
    """
}
