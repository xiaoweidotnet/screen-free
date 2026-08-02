import Foundation
import ScreenFreeCore
import Speech

enum CaptionGenerationError: LocalizedError {
    case permissionDenied
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Speech recognition permission is required to generate captions."
        case .recognizerUnavailable:
            return "On-device speech recognition is unavailable for this language."
        }
    }
}

struct CaptionRecognitionContext: Equatable, Sendable {
    static let maximumPhraseCount = 100
    static let maximumPhraseLength = 80

    let phrases: [String]

    init(rawText: String) {
        let separators = CharacterSet.newlines.union(
            CharacterSet(charactersIn: ",，;；")
        )
        var seen: Set<String> = []
        var result: [String] = []
        for component in rawText.components(separatedBy: separators) {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let phrase = String(trimmed.prefix(Self.maximumPhraseLength))
            let key = phrase.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard seen.insert(key).inserted else { continue }
            result.append(phrase)
            if result.count == Self.maximumPhraseCount {
                break
            }
        }
        phrases = result
    }
}

struct CaptionGenerator {
    func generate(
        from url: URL,
        localeIdentifier: String,
        vocabulary: String = ""
    ) async throws -> [CaptionCue] {
        let authorization = await requestAuthorization()
        guard authorization == .authorized else {
            throw CaptionGenerationError.permissionDenied
        }
        let locale = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            throw CaptionGenerationError.recognizerUnavailable
        }

        let request = Self.makeRequest(
            from: url,
            vocabulary: vocabulary
        )

        return try await withCheckedThrowingContinuation { continuation in
            let state = CaptionContinuationState(continuation: continuation)
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    state.finish(.failure(error))
                    return
                }
                guard let result, result.isFinal else { return }
                let cues = result.bestTranscription.segments
                    .map {
                        CaptionCue(
                            sourceStart: $0.timestamp,
                            duration: max(0.15, $0.duration),
                            text: $0.substring
                        )
                    }
                state.finish(.success(cues))
            }
        }
    }

    static func makeRequest(
        from url: URL,
        vocabulary: String
    ) -> SFSpeechURLRecognitionRequest {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        request.contextualStrings = CaptionRecognitionContext(
            rawText: vocabulary
        ).phrases
        return request
    }

    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

private final class CaptionContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[CaptionCue], Error>?

    init(continuation: CheckedContinuation<[CaptionCue], Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<[CaptionCue], Error>) {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
