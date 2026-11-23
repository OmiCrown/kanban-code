import Foundation
import KanbanCodeRemoteKit
import Synchronization
import Testing

@testable import KanbanCodeCore

@Suite("Remote listen mode setting")
struct RemoteListenModeSettingTests {
    private func decode(_ json: String) throws -> RemoteControlSettings {
        try JSONDecoder().decode(RemoteControlSettings.self, from: Data(json.utf8))
    }

    @Test("a server that is already on keeps Tailscale when the key is missing")
    func missingKeyEnabledKeepsTailscale() throws {
        #expect(try decode(#"{"enabled":true,"port":7780}"#).listenOn == .tailscale)
    }

    @Test("a server that is off reads this Mac only when the key is missing")
    func missingKeyDisabledIsThisMac() throws {
        #expect(try decode(#"{"enabled":false,"port":7780}"#).listenOn == .thisMac)
        #expect(try decode("{}").listenOn == .thisMac)
    }

    @Test("a stored value wins over the default")
    func explicitValueWins() throws {
        #expect(try decode(#"{"enabled":true,"listenOn":"this-mac"}"#).listenOn == .thisMac)
        #expect(try decode(#"{"enabled":false,"listenOn":"tailscale"}"#).listenOn == .tailscale)
    }

    @Test("an unknown value falls back and keeps the server as it was")
    func unknownValueFallsBack() throws {
        let settings = try decode(#"{"enabled":true,"listenOn":"lan"}"#)
        #expect(settings.listenOn == .tailscale)
        #expect(settings.enabled)
    }

    @Test("the mode round trips under the key listenOn")
    func roundTrip() throws {
        let value = RemoteControlSettings(enabled: true, port: 7781, listenOn: .tailscale)
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(RemoteControlSettings.self, from: data) == value)
        #expect(String(decoding: data, as: UTF8.self).contains(#""listenOn":"tailscale""#))
    }

    @Test("settings without a remoteControl section read this Mac only")
    func settingsWithoutRemoteControlIsThisMac() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        #expect(settings.remoteControl.listenOn == .thisMac)
    }

    @Test("only enabled and port restart the server")
    func needsRestart() {
        let base = RemoteControlSettings(enabled: true, port: 7780, listenOn: .tailscale)
        #expect(!RemoteControlSettings(enabled: true, port: 7780, listenOn: .thisMac).needsRestart(from: base))
        #expect(RemoteControlSettings(enabled: false, port: 7780, listenOn: .tailscale).needsRestart(from: base))
        #expect(RemoteControlSettings(enabled: true, port: 7781, listenOn: .tailscale).needsRestart(from: base))
    }
}

@Suite("Remote listen addresses")
struct RemoteListenAddressTests {
    private static let fakeTailscale = ["100.64.0.5", "fd7a:115c:a1e0::1"]

    @Test("this Mac only is loopback alone")
    func thisMacIsLoopbackOnly() {
        #expect(RemoteNetworkAddresses.addresses(for: .thisMac, tailscale: { Self.fakeTailscale }) == ["127.0.0.1"])
    }

    @Test("also Tailscale adds the Tailscale addresses after loopback")
    func tailscaleAddsItsAddresses() {
        #expect(RemoteNetworkAddresses.addresses(for: .tailscale, tailscale: { Self.fakeTailscale })
            == ["127.0.0.1", "100.64.0.5", "fd7a:115c:a1e0::1"])
    }

    @Test("no wildcard and no duplicates")
    func noWildcardNoDuplicates() {
        let out = RemoteNetworkAddresses.addresses(for: .tailscale, tailscale: { ["100.64.0.5", "100.64.0.5", "127.0.0.1"] })
        #expect(out == ["127.0.0.1", "100.64.0.5"])
        #expect(!out.contains("0.0.0.0"))
    }

    @Test("this Mac only does not even ask for the Tailscale addresses")
    func thisMacDoesNotAskTailscale() {
        let calls = Mutex(0)
        _ = RemoteNetworkAddresses.addresses(for: .thisMac, tailscale: { calls.withLock { $0 += 1 }; return [] })
        #expect(calls.withLock { $0 } == 0)
    }

    @Test("the box follows the mode it is given")
    func boxFollowsSet() {
        let box = RemoteListenModeBox(.thisMac)
        #expect(box.bindAddresses(tailscale: { ["::1"] }) == ["127.0.0.1"])
        box.set(.tailscale)
        #expect(box.mode == .tailscale)
        #expect(box.bindAddresses(tailscale: { ["::1"] }) == ["127.0.0.1", "::1"])
    }

    @Test("bindable() is the also-Tailscale list")
    func bindableIsTailscaleMode() {
        #expect(RemoteNetworkAddresses.bindable() == RemoteNetworkAddresses.addresses(for: .tailscale))
        #expect(RemoteNetworkAddresses.bindable().first == "127.0.0.1")
    }
}
