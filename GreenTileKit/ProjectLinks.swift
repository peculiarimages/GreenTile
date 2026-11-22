/// Where to find the project online.
public enum ProjectLinks {
    /// The project's home on GitHub: shown in every help bubble and opened by clicking its icon.
    public static let repository = "https://github.com/peculiarimages/GreenTile"
}

extension ProjectLinks {
    /// The GitHub API address of the newest published release.
    public static let latestReleaseAPI = "https://api.github.com/repos/peculiarimages/GreenTile/releases/latest"

    /// The numbers of a version such as "0.1.7" or a tag such as "v0.1.7"; nil when it is not one.
    public static func versionNumbers(_ text: String) -> [Int]? {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.first == "v" || trimmed.first == "V" { trimmed.removeFirst() }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        return parts.map { $0! }
    }

    /// Whether `candidate` is a later version than `current`. Missing trailing numbers count as 0
    /// ("0.2" equals "0.2.0"), and anything that is not a version is never newer.
    public static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        guard let a = versionNumbers(candidate), let b = versionNumbers(current) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
