import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("RemoteImagePolicy")
struct RemoteImagePolicyTests {
    private func allowed(_ text: String) -> Bool {
        RemoteImagePolicy.isAllowed(URL(string: text))
    }

    @Test func allowsGithubHosts() {
        #expect(allowed("https://github.com/user-attachments/assets/a"))
        #expect(allowed("https://github.com/acme/api/raw/main/a.png"))
    }

    @Test func allowsGithubusercontentSubdomains() {
        #expect(allowed("https://avatars.githubusercontent.com/u/1"))
        #expect(allowed("https://user-images.githubusercontent.com/1/a.png"))
        #expect(allowed("https://private-user-images.githubusercontent.com/1/a.png"))
    }

    @Test func blocksLookalikeHosts() {
        #expect(!allowed("https://github.com.evil.com/x.png"))
        #expect(!allowed("https://evilgithub.com/x.png"))
        #expect(!allowed("https://githubusercontent.com.evil.io/x.png"))
        #expect(!allowed("https://evilgithubusercontent.com/x.png"))
    }

    @Test func blocksUserinfoTrick() {
        #expect(!allowed("https://github.com@evil.com/x.png"))
        #expect(!allowed("https://user:pass@github.com/x.png"))
    }

    @Test func blocksNonHttps() {
        #expect(!allowed("http://github.com/x.png"))
        #expect(!allowed("data:image/png;base64,AAAA"))
        #expect(!allowed("file:///etc/passwd"))
    }

    @Test func blocksOtherPorts() {
        #expect(!allowed("https://github.com:8443/x.png"))
        #expect(allowed("https://github.com:443/x.png"))
    }

    @Test func normalizesCaseAndTrailingDot() {
        #expect(allowed("HTTPS://GitHub.COM./x.png"))
        #expect(allowed("https://Avatars.GithubUserContent.com/u/1"))
    }

    @Test func blocksNil() {
        #expect(!RemoteImagePolicy.isAllowed(nil))
    }
}
