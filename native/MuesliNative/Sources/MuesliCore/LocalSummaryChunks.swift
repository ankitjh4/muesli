import Foundation

/// Bounds UTF-8 input without discarding text or splitting grapheme clusters.
public enum LocalSummaryChunks {
    public enum ChunkError: Error { case invalidLimit, oversizedCharacter }

    public static func split(_ text: String, maximumBytes: Int = 2_000) throws -> [String] {
        guard maximumBytes > 0 else { throw ChunkError.invalidLimit }
        var result: [String] = []
        var current = ""
        var bytes = 0
        for character in text {
            let piece = String(character)
            let size = piece.utf8.count
            guard size <= maximumBytes else { throw ChunkError.oversizedCharacter }
            if bytes + size > maximumBytes {
                if let boundary = current.lastIndex(where: \.isWhitespace) {
                    let end = current.index(after: boundary)
                    result.append(String(current[..<end]))
                    current = String(current[end...])
                    bytes = current.utf8.count
                }
                if bytes + size > maximumBytes {
                    result.append(current)
                    current = ""
                    bytes = 0
                }
            }
            current += piece
            bytes += size
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
