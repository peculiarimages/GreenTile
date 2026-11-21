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
}
