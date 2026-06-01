import Foundation

/// A library of hand-curated writing prompts used as the empty-state placeholder
/// in the text capsule editor.
///
/// The prompts are deliberately literary and quiet — about time, memory, and
/// attention — never productivity-flavored. They live in
/// `Resources/WritingPrompts.json` so they can be edited without rebuilding
/// code, and never persist into the capsule itself (they're purely scaffolding
/// shown when the editor is empty).
enum WritingPrompts {
    /// All prompts, loaded once from the bundled JSON. Falls back to a single
    /// safe prompt if the file is missing or malformed (should be impossible
    /// in shipped builds — present only as a defensive guard).
    nonisolated static let all: [String] = loadFromBundle()

    /// Returns a fresh random prompt index, never equal to `excluding`.
    /// Used to pick the first prompt of a session (excluding the previously
    /// shown one across launches) and to swap to a new prompt when the user
    /// taps the ✦ affordance.
    nonisolated static func nextIndex(excluding: Int?) -> Int {
        let count = all.count
        guard count > 1 else { return 0 }
        var idx = Int.random(in: 0..<count)
        while idx == excluding {
            idx = Int.random(in: 0..<count)
        }
        return idx
    }

    /// Safe accessor — returns the prompt at `index`, or a fallback if `index`
    /// is somehow out of range.
    nonisolated static func prompt(at index: Int) -> String {
        guard index >= 0, index < all.count else {
            return all.first ?? "what does today smell like?"
        }
        return all[index]
    }

    // MARK: - Private

    nonisolated private struct Payload: Decodable {
        let prompts: [String]
    }

    nonisolated private static func loadFromBundle() -> [String] {
        guard let url = Bundle.main.url(forResource: "WritingPrompts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              !payload.prompts.isEmpty else {
            return ["what does today smell like?"]
        }
        return payload.prompts
    }
}
