import Foundation

/// Which addresses the remote control server listens on
/// (Settings > Remote Control > Listen on).
public enum RemoteListenMode: String, Codable, Sendable, CaseIterable {
    /// Loopback only: programs on this Mac, `kanban remote` and
    /// `tailscale serve` (which forwards to loopback).
    case thisMac = "this-mac"
    /// Loopback plus the Mac's Tailscale addresses.
    case tailscale
}
