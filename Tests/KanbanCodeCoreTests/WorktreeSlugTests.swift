import Testing
@testable import KanbanCodeCore

@Suite("WorktreeSlug")
struct WorktreeSlugTests {
    @Test("An English prompt gives its first words")
    func english() {
        #expect(WorktreeSlug.make(from: "Fix the login redirect loop on Safari, please", fallback: "x")
            == "fix-the-login-redirect-loop")
    }

    @Test("A Russian prompt is transliterated")
    func russian() {
        #expect(WorktreeSlug.make(from: "Проверка частоты обновления статистики запроса", fallback: "x")
            == "proverka-chastoty-obnovleniya-statistiki")
    }

    @Test("Ukrainian letters are transliterated")
    func ukrainian() {
        #expect(WorktreeSlug.make(from: "Їжак і ґанок", fallback: "x") == "yizhak-i-ganok")
    }

    @Test("Punctuation and markup are word breaks, and the slug has no edge dashes")
    func punctuation() {
        #expect(WorktreeSlug.make(from: "  --> `foo/bar`: baz!!  ", fallback: "x") == "foo-bar-baz")
    }

    @Test("A prompt with no letters or digits falls back")
    func emptyFallsBack() {
        #expect(WorktreeSlug.make(from: "  ... ", fallback: "card_1") == "card_1")
        #expect(WorktreeSlug.make(from: "", fallback: "card_1") == "card_1")
        #expect(WorktreeSlug.make(from: "日本語", fallback: "card_1") == "card_1")
    }

    @Test("A name that is taken falls back, with or without the worktree- prefix")
    func takenFallsBack() {
        #expect(WorktreeSlug.make(from: "Add dark mode", fallback: "card_1", taken: ["add-dark-mode"]) == "card_1")
        #expect(WorktreeSlug.make(from: "Add dark mode", fallback: "card_1", taken: ["worktree-add-dark-mode"]) == "card_1")
        #expect(WorktreeSlug.make(from: "Add dark mode", fallback: "card_1", taken: ["other"]) == "add-dark-mode")
    }

    @Test("The slug is at most 40 characters and cuts at a word")
    func length() {
        let slug = WorktreeSlug.make(from: "implementation internationalization infrastructure migration planning", fallback: "x")
        #expect(slug.count <= WorktreeSlug.maxLength)
        #expect(slug == "implementation-internationalization")
    }

    @Test("A single word longer than the limit is cut")
    func longWord() {
        let slug = WorktreeSlug.make(from: String(repeating: "a", count: 80), fallback: "x")
        #expect(slug.count == WorktreeSlug.maxLength)
    }
}
