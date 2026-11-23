import Foundation
import Synchronization

/// Which addresses the remote control server listens on
/// (Settings > Remote Control > Listen on).
public enum RemoteListenMode: String, Codable, Sendable, CaseIterable {
    /// Loopback only: programs on this Mac, `kanban remote` and
    /// `tailscale serve` (which forwards to loopback).
    case thisMac = "this-mac"
    /// Loopback plus the Mac's Tailscale addresses.
    case tailscale
}

/// The URL a device reaches the server at, for pairing links and the Add Device sheet.
public enum RemoteBaseURL {
    /// This Mac only: always loopback. Also Tailscale: the MagicDNS name, else
    /// the first non-loopback IPv4 address the server listens on, else loopback.
    public static func make(listenOn: RemoteListenMode, magicDNSName: String?, addresses: [String], port: Int) -> String {
        let loopback = "http://\(RemoteNetworkAddresses.loopback):\(port)"
        guard listenOn == .tailscale else { return loopback }
        if let magicDNSName { return "http://\(magicDNSName):\(port)" }
        if let ip = addresses.first(where: { $0 != RemoteNetworkAddresses.loopback && !$0.contains(":") }) {
            return "http://\(ip):\(port)"
        }
        return loopback
    }
}

/// The mode a running server follows. The server asks `bindAddresses` for the
/// addresses it should hold, so changing the mode and calling the server's
/// `reconcile()` applies it without a restart.
public final class RemoteListenModeBox: Sendable {
    private let value: Mutex<RemoteListenMode>

    public init(_ mode: RemoteListenMode) {
        value = Mutex(mode)
    }

    public var mode: RemoteListenMode { value.withLock { $0 } }

    public func set(_ mode: RemoteListenMode) {
        value.withLock { $0 = mode }
    }

    public func bindAddresses(tailscale: @Sendable () -> [String] = RemoteNetworkAddresses.tailscale) -> [String] {
        RemoteNetworkAddresses.addresses(for: mode, tailscale: tailscale)
    }
}
