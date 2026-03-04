import Foundation

public enum PostProcessor {
    private static let fillerWords: [String] = [
        // Sorted longest-first so multi-word phrases are matched before their parts
        "you know", "i mean", "kind of", "sort of",
        "basically", "literally", "actually", "seriously",
        "vlastně", "prostě",
        "takže",
        "okay", "like", "right", "well",
        "jako",
        "hmm", "ehm",
        "um", "uh", "er", "ah",
        "ok", "so",
        "jo", "no",
    ]

    public static func process(_ text: String) -> String {
        var result = text
        for word in fillerWords {
            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }
        // Collapse multiple spaces
        if let spaceRegex = try? NSRegularExpression(pattern: " {2,}") {
            result = spaceRegex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: " "
            )
        }
        result = result.trimmingCharacters(in: .whitespaces)
        // Capitalize first letter
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }
        return result
    }
}
