import AppKit
import ApplicationServices

/// Everything GreenTile can do to get the Accessibility permission granted.
///
/// macOS only shows its own "would like to control this computer" prompt when the app has no entry
/// in the Accessibility list yet. If an entry already exists (switched off, or left over from an
/// earlier build whose signature no longer matches) the system stays silent and the app is simply
/// not trusted. `resetAndAsk()` clears GreenTile's own entry so the system prompt can appear again.
enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt (when macOS still allows one) and adds GreenTile to the
    /// Accessibility list in System Settings, switched off, so the user only has to switch it on.
    @discardableResult
    static func askSystem() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Opens System Settings at Privacy & Security > Accessibility.
    static func openSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    /// Removes GreenTile's own entry from the Accessibility list (only this app's, by bundle ID),
    /// then asks again so macOS shows its prompt and lists the app afresh.
    static func resetAndAsk() {
        if let bundleID = Bundle.main.bundleIdentifier {
            let tccutil = Process()
            tccutil.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            tccutil.arguments = ["reset", "Accessibility", bundleID]
            do {
                try tccutil.run()
                tccutil.waitUntilExit()
            } catch {
                NSLog("GreenTile: tccutil reset failed: \(error.localizedDescription)")
            }
        }
        askSystem()
        openSettings()
    }

    /// True when the app is running from a randomised read-only copy (App Translocation), which
    /// happens when a downloaded app is opened before it has been moved to Applications. The
    /// permission granted to such a copy does not stick.
    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }
}
