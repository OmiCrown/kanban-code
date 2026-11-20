import Foundation

/// Which image URLs a card may load from the network.
///
/// The body of a GitHub issue or pull request is written by someone else, and
/// an image in it is fetched the moment the card opens: the request tells the
/// image's host this Mac's address and when the card was looked at. Only
/// GitHub's own image hosts are fetched; any other image shows a placeholder.
public enum RemoteImagePolicy {
    /// True for `https` URLs on `github.com` or a subdomain of
    /// `githubusercontent.com`, without credentials and on the default port.
    /// Hosts match on whole labels: `github.com.evil.com` and `evilgithub.com`
    /// do not pass.
    public static func isAllowed(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              var host = url.host?.lowercased() else { return false }
        if host.hasSuffix(".") { host.removeLast() }
        return host == "github.com" || host.hasSuffix(".githubusercontent.com")
    }
}
