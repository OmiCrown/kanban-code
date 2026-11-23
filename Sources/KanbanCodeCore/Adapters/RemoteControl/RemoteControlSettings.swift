import Foundation
import KanbanCodeRemoteKit

/// Settings > Remote Control: the HTTP server phones and other agents use to
/// drive this Mac (docs/remote-control.md). Off until turned on. `listenOn`
/// says whether it also listens on the Mac's Tailscale addresses.
public struct RemoteControlSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var port: Int
    public var listenOn: RemoteListenMode

    public init(enabled: Bool = false, port: Int = RemoteAPI.defaultPort, listenOn: RemoteListenMode = .thisMac) {
        self.enabled = enabled
        self.port = port
        self.listenOn = listenOn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        let port = (try? c.decodeIfPresent(Int.self, forKey: .port)) ?? RemoteAPI.defaultPort
        self.port = (1...65535).contains(port) ? port : RemoteAPI.defaultPort
        // Settings written before the key existed: a server that is on keeps
        // listening on Tailscale, so a phone that pairs today keeps working.
        listenOn = (try? c.decodeIfPresent(RemoteListenMode.self, forKey: .listenOn)) ?? (enabled ? .tailscale : .thisMac)
    }

    /// Whether going from `old` to this value needs the server stopped and
    /// started again. A change of `listenOn` alone is applied to the running server.
    public func needsRestart(from old: RemoteControlSettings) -> Bool {
        enabled != old.enabled || port != old.port
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, port, listenOn
    }
}
