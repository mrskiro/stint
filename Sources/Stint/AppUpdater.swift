import AppKit
import Security

enum AppUpdater {
    static let repo = "mrskiro/stint"

    static func checkForUpdates() async throws {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

        let (data, _) = try await URLSession.shared.data(
            from: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        )
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        let latestVersion = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst())
            : release.tagName

        guard compare(latestVersion, isNewerThan: currentVersion) else {
            await showNotification(title: "Stint", body: "You're up to date (v\(currentVersion)).")
            return
        }

        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            throw UpdateError.noDMGAsset
        }

        let dmgURL = try await download(asset)
        let mountPoint = try await mountDMG(dmgURL)
        defer { unmountDMG(mountPoint) }

        let appURL = try findApp(in: mountPoint)
        try verifyCodeSignature(of: appURL)

        let destination = Bundle.main.bundleURL
        let parent = destination.deletingLastPathComponent()
        let backupURL = parent.appendingPathComponent("Stint-old.app")

        let fm = FileManager.default
        if fm.fileExists(atPath: backupURL.path) {
            try fm.removeItem(at: backupURL)
        }
        try fm.moveItem(at: destination, to: backupURL)
        try fm.copyItem(at: appURL, to: destination)
        try fm.removeItem(at: backupURL)

        NSWorkspace.shared.open(destination)
        try? await Task.sleep(for: .milliseconds(500))
        await NSApp.terminate(nil)
    }

    private static func download(_ asset: GitHubRelease.Asset) async throws -> URL {
        let (tmpURL, _) = try await URLSession.shared.download(from: URL(string: asset.downloadURL)!)
        let dmgURL = tmpURL.deletingLastPathComponent().appendingPathComponent(asset.name)
        try? FileManager.default.removeItem(at: dmgURL)
        try FileManager.default.moveItem(at: tmpURL, to: dmgURL)
        return dmgURL
    }

    private static func mountDMG(_ url: URL) async throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", url.path, "-nobrowse", "-mountrandom", "/tmp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UpdateError.dmgMountFailed
        }
        guard let mountLine = output.split(separator: "\n").last,
              let mountPath = mountLine.split(separator: "\t").last else {
            throw UpdateError.dmgMountFailed
        }
        return URL(fileURLWithPath: String(mountPath))
    }

    private static func unmountDMG(_ mountPoint: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint.path, "-quiet"]
        try? process.run()
        process.waitUntilExit()
    }

    private static func findApp(in mountPoint: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: mountPoint, includingPropertiesForKeys: nil
        )
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.noAppInDMG
        }
        return app
    }

    private static func verifyCodeSignature(of appURL: URL) throws {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let code = staticCode else {
            throw UpdateError.codeSigningFailed
        }

        let validateStatus = SecStaticCodeCheckValidity(code, [.enforceRevocationChecks], nil)
        guard validateStatus == errSecSuccess else {
            throw UpdateError.codeSigningFailed
        }

        var currentStaticCode: SecStaticCode?
        SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &currentStaticCode)
        guard let currentCode = currentStaticCode else {
            throw UpdateError.codeSigningFailed
        }

        var newInfo: CFDictionary?
        var currentInfo: CFDictionary?
        SecCodeCopySigningInformation(code, [SecCSFlags(rawValue: kSecCSSigningInformation)], &newInfo)
        SecCodeCopySigningInformation(currentCode, [SecCSFlags(rawValue: kSecCSSigningInformation)], &currentInfo)

        let newTeamID = (newInfo as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
        let currentTeamID = (currentInfo as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String

        guard let newTeam = newTeamID, let currentTeam = currentTeamID, newTeam == currentTeam else {
            throw UpdateError.codeSigningFailed
        }
    }

    static func compare(_ a: String, isNewerThan b: String) -> Bool {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(partsA.count, partsB.count) {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va != vb { return va > vb }
        }
        return false
    }

    @MainActor
    private static func showNotification(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.runModal()
    }

    enum UpdateError: LocalizedError {
        case noDMGAsset, dmgMountFailed, noAppInDMG, codeSigningFailed

        var errorDescription: String? {
            switch self {
            case .noDMGAsset: "No DMG asset found in the latest release."
            case .dmgMountFailed: "Failed to mount the DMG."
            case .noAppInDMG: "No .app found in the DMG."
            case .codeSigningFailed: "Code signing verification failed."
            }
        }
    }
}

struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let downloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}
