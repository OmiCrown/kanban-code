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
