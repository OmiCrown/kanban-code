import SwiftUI
import MarkdownUI
import KanbanCodeCore

/// Markdown image provider that loads only the hosts `RemoteImagePolicy`
/// allows. Any other image is not requested: a one-line placeholder names the
/// host instead.
struct PolicyImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        if RemoteImagePolicy.isAllowed(url) {
            DefaultImageProvider().makeImage(url: url)
        } else {
            Label("Image from \(url?.host ?? "unknown host") not loaded", systemImage: "photo.badge.exclamationmark")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
        }
    }
}
