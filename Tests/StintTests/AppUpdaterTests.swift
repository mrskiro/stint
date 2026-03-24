import Foundation
import Testing
@testable import Stint

struct VersionCompareTests {
    @Test func newerPatch() {
        #expect(AppUpdater.compare("1.0.1", isNewerThan: "1.0.0") == true)
    }

    @Test func newerMinor() {
        #expect(AppUpdater.compare("1.1.0", isNewerThan: "1.0.9") == true)
    }

    @Test func newerMajor() {
        #expect(AppUpdater.compare("2.0.0", isNewerThan: "1.9.9") == true)
    }

    @Test func sameVersion() {
        #expect(AppUpdater.compare("1.0.0", isNewerThan: "1.0.0") == false)
    }

    @Test func olderVersion() {
        #expect(AppUpdater.compare("1.0.0", isNewerThan: "1.0.1") == false)
    }

    @Test func differentSegmentCount() {
        #expect(AppUpdater.compare("1.1", isNewerThan: "1.0.0") == true)
        #expect(AppUpdater.compare("1.0.0", isNewerThan: "1.1") == false)
    }
}

struct GitHubReleaseDecodingTests {
    @Test func decodesReleaseJSON() throws {
        let json = """
        {
            "tag_name": "v1.2.3",
            "assets": [
                {
                    "name": "Stint-v1.2.3.dmg",
                    "browser_download_url": "https://github.com/mrskiro/stint/releases/download/v1.2.3/Stint-v1.2.3.dmg"
                }
            ]
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)

        #expect(release.tagName == "v1.2.3")
        #expect(release.assets.count == 1)
        #expect(release.assets[0].name == "Stint-v1.2.3.dmg")
        #expect(release.assets[0].downloadURL.contains("v1.2.3"))
    }

    @Test func decodesReleaseWithNoAssets() throws {
        let json = """
        {
            "tag_name": "v0.1.0",
            "assets": []
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)

        #expect(release.tagName == "v0.1.0")
        #expect(release.assets.isEmpty)
    }
}

struct GitHubAPIIntegrationTests {
    @Test func fetchesLatestRelease() async throws {
        let url = URL(string: "https://api.github.com/repos/mrskiro/stint/releases/latest")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = response as! HTTPURLResponse

        #expect(httpResponse.statusCode == 200)

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        #expect(release.tagName.hasPrefix("v"))
        #expect(release.assets.contains(where: { $0.name.hasSuffix(".dmg") }))
    }
}
