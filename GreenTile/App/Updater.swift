import AppKit
import CryptoKit
import GreenTileKit

/// "Update GreenTile…": finds the newest release on GitHub, and if it is newer than this copy,
/// downloads it, checks it, puts it in place of this copy and starts it.
///
/// What it checks before replacing anything: the download's SHA-256 matches the checksum published
/// next to it, the app inside is GreenTile (same bundle identifier) at the version the release
/// names, and its code signature is intact.
///
/// The Accessibility permission belongs to an app's exact signature, and every release has a new
/// one, so the old switch in System Settings no longer applies after an update (it can even stay
/// on while macOS ignores it). The updater clears GreenTile's own entry before restarting, so the
/// new copy is asked about afresh and only needs switching on again.
@MainActor
final class Updater {
    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL
        let assets: [Asset]

        func asset(_ name: String) -> URL? { assets.first { $0.name == name }?.browser_download_url }
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private var isBusy = false

    /// Nonisolated so `AppDelegate` can create it as a stored property.
    nonisolated init() {}

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Checks for a newer release and offers to install it. Every outcome is reported in a dialog,
    /// since this only runs when the user asks for it.
    func checkAndOffer() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let release = try await latestRelease()
                let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
                guard ProjectLinks.isVersion(version, newerThan: currentVersion) else {
                    show("GreenTile is up to date", "Version \(currentVersion) is the newest release.")
                    return
                }
                guard confirm(version: version, release: release) else { return }
                try await install(release, version: version)
            } catch {
                show("GreenTile could not be updated", error.localizedDescription)
            }
        }
    }

    // MARK: Steps

    private func latestRelease() async throws -> Release {
        guard let url = URL(string: ProjectLinks.latestReleaseAPI) else { throw Failure("The release address is invalid.") }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GreenTile/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure("GitHub did not answer the update check. Try again in a while.")
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    private func confirm(version: String, release: Release) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "GreenTile \(version) is available"
        alert.informativeText = """
            You have version \(currentVersion). GreenTile will download the new version, check it, \
            replace this copy and restart.

            Afterwards macOS asks again for Accessibility access, because each version is a new \
            app to macOS: switch GreenTile on in the window that opens.
            """
        alert.addButton(withTitle: "Update and Restart")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "What's New")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertThirdButtonReturn: NSWorkspace.shared.open(release.html_url); return false
        default: return false
        }
    }

    private func install(_ release: Release, version: String) async throws {
        let target = Bundle.main.bundleURL
        let folder = target.deletingLastPathComponent()
        guard !AccessibilityPermission.isTranslocated,
              folder.path == "/Applications" || folder.lastPathComponent == "Applications" else {
            throw Failure("Move GreenTile.app to your Applications folder and open it from there, then update.")
        }
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            throw Failure("GreenTile can't write to \(folder.path). Download the update from the project page instead.")
        }
        guard let zipURL = release.asset("GreenTile.zip"), let sumURL = release.asset("GreenTile.zip.sha256") else {
            throw Failure("This release has no GreenTile.zip with a checksum.")
        }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("GreenTile-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        // Download and check the archive against its published checksum.
        let (downloaded, _) = try await URLSession.shared.download(from: zipURL)
        let zip = work.appendingPathComponent("GreenTile.zip")
        try FileManager.default.moveItem(at: downloaded, to: zip)
        let (sumData, _) = try await URLSession.shared.data(from: sumURL)
        let expected = String(decoding: sumData, as: UTF8.self)
            .split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
        let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        guard !expected.isEmpty, expected == actual else {
            throw Failure("The download does not match its published checksum, so nothing was changed.")
        }

        // Unpack and make sure it is the right app, at the right version, with a sound signature.
        let unpacked = work.appendingPathComponent("unpacked")
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        let newApp = unpacked.appendingPathComponent("GreenTile.app")
        guard let bundle = Bundle(url: newApp), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version else {
            throw Failure("The download does not contain GreenTile \(version), so nothing was changed.")
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", newApp.path],
                failure: "The new version's signature could not be verified, so nothing was changed.")
        // Files fetched by the app itself carry no quarantine flag, but clear any left by unzipping.
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        // Put it in place. A running app's files can be replaced; this copy keeps running until it quits.
        _ = try FileManager.default.replaceItemAt(target, withItemAt: newApp)

        // Clear this app's Accessibility entry so the new version is asked about afresh.
        if let id = Bundle.main.bundleIdentifier {
            try? run("/usr/bin/tccutil", ["reset", "Accessibility", id])
        }

        // Start the new copy once this one has quit.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
                              "sh", String(ProcessInfo.processInfo.processIdentifier), target.path]
        try relaunch.run()
        NSApp.terminate(nil)
    }

    // MARK: Helpers

    private func run(_ tool: String, _ arguments: [String], failure: String? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure(failure ?? "\((tool as NSString).lastPathComponent) failed, so nothing was changed.")
        }
    }

    private func show(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
