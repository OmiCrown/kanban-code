import Foundation

/// A worktree and branch name made from a task's prompt, so the folder says
/// what the task is instead of `golden-crunching-owl`.
public enum WorktreeSlug {
    public static let maxWords = 5
    public static let maxLength = 40

    /// The slug of `prompt`, or `fallback` when the prompt gives nothing
    /// usable or the name is already taken. `taken` holds the branch names in
    /// use; `claude --worktree <name>` makes the branch `worktree-<name>`, so
    /// both spellings count as taken.
    public static func make(from prompt: String, fallback: String, taken: Set<String> = []) -> String {
        let slug = slug(of: prompt)
        guard !slug.isEmpty, !taken.contains(slug), !taken.contains("worktree-" + slug) else {
            return fallback
        }
        return slug
    }

    static func slug(of prompt: String) -> String {
        let latin = transliterate(prompt.lowercased())
        var words: [String] = []
        var current = ""
        for scalar in latin.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }

        var slug = ""
        for word in words.prefix(maxWords) {
            let next = slug.isEmpty ? word : slug + "-" + word
            if next.count > maxLength { break }
            slug = next
        }
        // A first word longer than the limit is cut rather than dropped.
        if slug.isEmpty, let first = words.first { slug = String(first.prefix(maxLength)) }
        return slug
    }

    /// Russian and Ukrainian letters to Latin; other characters pass through,
    /// and the ones that are not ASCII end up as word breaks in `slug(of:)`.
    static func transliterate(_ text: String) -> String {
        var out = ""
        for ch in text {
            out += map[ch] ?? String(ch)
        }
        // Accents of other Latin letters (é, ü) fold to their base letter.
        return out.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US"))
    }

    private static let map: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "ґ": "g", "д": "d", "е": "e", "ё": "e",
        "є": "ye", "ж": "zh", "з": "z", "и": "i", "і": "i", "ї": "yi", "й": "y", "к": "k",
        "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t",
        "у": "u", "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch",
        "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
    ]
}
