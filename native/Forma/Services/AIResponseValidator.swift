import Foundation

/// Last line of defence before an assistant reply reaches the screen. The Edge
/// Function screens output server-side; this catches unsafe text that would
/// still be unacceptable to display or persist.
enum AIResponseValidator {
    private static let negations = ["not ", "never ", "avoid", "stop", "don't", "do not", "cannot", "can't", "no "]

    private static let unsafePhrases = [
        "push through the pain",
        "train through the pain",
        "ignore the pain",
        "work through the pain",
        "guaranteed results",
        "definitely have",
        "i diagnose",
        "my diagnosis",
        "no need to see a doctor",
        "don't need a doctor",
        "skip the doctor",
        "take steroids",
        "starve yourself",
        "eat nothing",
    ]

    static func problem(with raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return "The coach returned an empty reply. Please try again."
        }
        if text.count > 12000 {
            return "The coach's reply was too long to display safely. Please ask a narrower question."
        }

        let sentences = text
            .split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" || $0 == "\n" })
            .map { $0.lowercased() }

        for sentence in sentences {
            guard !negations.contains(where: { sentence.contains($0) }) else { continue }
            if unsafePhrases.contains(where: { sentence.contains($0) }) {
                return "That draft reply did not meet Forma's safety standards, so it was withheld. If you are in pain, stop and speak to a qualified professional."
            }
        }
        return nil
    }
}
