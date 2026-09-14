import Foundation

/// On-device vocabulary suggestions, never automatic assertions that an ASR
/// spelling is correct. Count separate dictations, not repetitions in one clip.
public enum FrequentVocabulary {
    public struct Candidate: Identifiable, Equatable, Sendable {
        public let word: String
        public let dictationCount: Int
        public var id: String { word.lowercased() }
    }

    private static let commonWords: Set<String> = Set("""
    about after again also and are because been before being between both but can
    could does doing done each even from going good have here into just know like
    make more most much need next only other over please really right said same
    should some something thank thanks that their them then there these they thing
    think this those through time very want was well were what when where which
    while will with would your you yeah okay today tomorrow yesterday meeting
    the for not all any how our out one two now see get let has had its it's don't
    hai hain nahi nahin aur mein main mujhe aap hum kar ke ki ka ko se yeh woh
    """.split(whereSeparator: \.isWhitespace).map(String.init))

    public static func candidates(
        transcripts: [String], excluding knownWords: [String],
        minimumDictations: Int = 3, limit: Int = 20
    ) -> [Candidate] {
        guard limit > 0,
              let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{M}][\p{L}\p{M}\p{N}]*(?:[-'][\p{L}\p{M}\p{N}]+)*"#) else { return [] }
        let known = Set(knownWords.map { $0.lowercased() })
        var counts: [String: Int] = [:]
        var spellings: [String: [String: Int]] = [:]
        for transcript in transcripts {
            var seen = Set<String>()
            for match in regex.matches(in: transcript, range: NSRange(transcript.startIndex..., in: transcript)) {
                guard let range = Range(match.range, in: transcript) else { continue }
                let word = String(transcript[range])
                let key = word.lowercased()
                guard word.count >= 3, word.count <= 48,
                      !commonWords.contains(key), !known.contains(key), seen.insert(key).inserted else { continue }
                counts[key, default: 0] += 1
                spellings[key, default: [:]][word, default: 0] += 1
            }
        }
        return counts.filter { $0.value >= max(2, minimumDictations) }
            .map { key, count in
                let spelling = spellings[key]?.sorted {
                    $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
                }.first?.key ?? key
                return Candidate(word: spelling, dictationCount: count)
            }
            .sorted {
                $0.dictationCount == $1.dictationCount ? $0.id < $1.id : $0.dictationCount > $1.dictationCount
            }
            .prefix(limit).map { $0 }
    }
}
