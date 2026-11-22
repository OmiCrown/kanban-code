/// Whether a build is behind its local sources. Placeholder until the git comparison lands.
public enum BuildFreshness: Equatable, Sendable {
    case unknown

    public var text: String { "" }
}
