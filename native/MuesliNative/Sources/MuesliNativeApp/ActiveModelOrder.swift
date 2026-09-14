import Foundation

enum ActiveModelOrder {
    /// A stable partition avoids moving unrelated models around on every render.
    static func first<T>(_ values: [T], matching selected: (T) -> Bool) -> [T] {
        values.filter(selected) + values.filter { !selected($0) }
    }
}

enum DictationModelGroup: CaseIterable {
    case system, parakeet, whisper, hinglish, cohere, bodhanCore, bodhanFlex, experimental

    static func group(for model: BackendOption) -> Self {
        if BackendOption.systemManaged.contains(model) { return .system }
        if BackendOption.parakeetFamily.contains(model) { return .parakeet }
        if BackendOption.whisperFamily.contains(model) { return .whisper }
        if model == .whisperHinglishRomanized { return .hinglish }
        if model == .cohereTranscribe { return .cohere }
        if let bodhan = BodhanModel(rawValue: model.model) { return bodhan.isCore ? .bodhanCore : .bodhanFlex }
        return .experimental
    }

    static func ordered(active: BackendOption) -> [Self] {
        ActiveModelOrder.first(allCases) { $0 == group(for: active) }
    }
}
