import XCTest
@testable import GreenTileKit

final class ProjectLinksTests: XCTestCase {
    func testRepositoryLinkIsAValidSecureGitHubAddress() {
        let url = URL(string: ProjectLinks.repository)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "github.com")
        XCTAssertEqual(url?.pathComponents.dropFirst().first, "peculiarimages")
        XCTAssertEqual(url?.lastPathComponent, "GreenTile")
    }

    /// The text is shown as written, so it must not carry stray whitespace or a trailing slash.
    func testRepositoryLinkIsTidy() {
        XCTAssertEqual(ProjectLinks.repository, ProjectLinks.repository.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertFalse(ProjectLinks.repository.hasSuffix("/"))
    }

    func testVersionNumbersReadTagsAndVersions() {
        XCTAssertEqual(ProjectLinks.versionNumbers("0.1.7"), [0, 1, 7])
        XCTAssertEqual(ProjectLinks.versionNumbers("v0.1.10"), [0, 1, 10])
        XCTAssertNil(ProjectLinks.versionNumbers("latest"))
        XCTAssertNil(ProjectLinks.versionNumbers("0.1.7-beta"))
        XCTAssertNil(ProjectLinks.versionNumbers(""))
    }

    func testNewerVersionsCompareNumerically() {
        XCTAssertTrue(ProjectLinks.isVersion("v0.1.8", newerThan: "0.1.7"))
        XCTAssertTrue(ProjectLinks.isVersion("0.1.10", newerThan: "0.1.9"))
        XCTAssertTrue(ProjectLinks.isVersion("1.0", newerThan: "0.9.9"))
        XCTAssertFalse(ProjectLinks.isVersion("v0.1.7", newerThan: "0.1.7"))
        XCTAssertFalse(ProjectLinks.isVersion("0.2", newerThan: "0.2.0"))
        XCTAssertFalse(ProjectLinks.isVersion("0.1.6", newerThan: "0.1.7"))
        XCTAssertFalse(ProjectLinks.isVersion("nightly", newerThan: "0.1.7"))
    }

    func testLatestReleaseAddressPointsAtThisRepository() {
        let url = URL(string: ProjectLinks.latestReleaseAPI)
        XCTAssertEqual(url?.host, "api.github.com")
        XCTAssertEqual(url?.path, "/repos/peculiarimages/GreenTile/releases/latest")
    }
}
