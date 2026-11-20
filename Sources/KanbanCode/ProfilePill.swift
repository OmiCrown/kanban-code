import SwiftUI
import KanbanCodeCore

private struct LabelledProfilesKey: EnvironmentKey {
    static let defaultValue: [ClaudeProfile] = []
}

extension EnvironmentValues {
    /// The profiles cards are labelled with; empty while one profile is enabled.
    var labelledProfiles: [ClaudeProfile] {
        get { self[LabelledProfilesKey.self] }
        set { self[LabelledProfilesKey.self] = newValue }
    }
}

extension ClaudeProfile {
    /// The stored colour, else one picked from the name so a profile keeps its colour.
    var displayColor: Color {
        if let hex = colorHex, let color = Color(profileHex: hex) { return color }
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown]
        let seed = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[seed % palette.count]
    }
}

private extension Color {
    init?(profileHex hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

/// Small coloured label with the name of the profile a card's session lives in.
struct ProfilePill: View {
    let profile: ClaudeProfile

    var body: some View {
        Text(profile.name)
            .font(.app(.caption2, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(profile.displayColor.opacity(0.18), in: Capsule())
            .foregroundStyle(profile.displayColor)
            .help("Claude profile: \(profile.path)")
    }
}
