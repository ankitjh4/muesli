import Foundation

let url = URL(fileURLWithPath: CommandLine.arguments[1])
do {
    let data = try url.bookmarkData(options: .suitableForBookmarkFile,
                                    includingResourceValuesForKeys: nil,
                                    relativeTo: nil)
    var stale = false
    let resolved = try URL(resolvingBookmarkData: data,
                           options: [.withoutUI, .withoutMounting],
                           bookmarkDataIsStale: &stale)
    guard FileManager.default.fileExists(atPath: resolved.path) else { exit(1) }
    print(data.base64EncodedString())
} catch {
    fputs("Cannot create installer background reference: \(error)\n", stderr)
    exit(1)
}
