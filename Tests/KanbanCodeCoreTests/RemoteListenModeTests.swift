import Foundation
import KanbanCodeRemoteKit
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
