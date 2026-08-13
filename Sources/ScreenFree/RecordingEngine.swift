import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit
import ScreenFreeCore

enum CaptureMode: String, CaseIterable, Identifiable {
    case display = "Display"
    case window = "Window"
    case area = "Area"

    var id: Self { self }
}

enum CaptureContentVisibilityPolicy {
    static func onScreenWindowsOnly(for mode: CaptureMode) -> Bool {
        mode != .window
    }
}

enum SystemAudioCaptureMode: String, CaseIterable, Identifiable, Sendable {
    case all = "All applications"
    case selected = "Selected applications"
    case off = "Off"

    var id: Self { self }
}

struct AudioApplicationOption: Identifiable, Hashable {
    let id: String
    let name: String
}

struct CaptureTarget: Identifiable, Hashable {
    enum Kind: Hashable {
        case display
        case window
    }

    let id: UInt32
    let title: String
    let kind: Kind
    let frame: CGRect
    let isPrimary: Bool
}

enum RecordingError: LocalizedError {
    case noSource
    case noAudioApplications
    case cannotStartWriter
    case cannotFinishWriter
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSource:
            return "No recordable screen or window was found."
        case .noAudioApplications:
            return "Choose at least one application for system audio."
        case .cannotStartWriter:
            return "The video writer could not start."
        case .cannotFinishWriter:
            return "The recording could not be finalized."
        case let .writerFailed(details):
            return "The recording writer failed: \(details)"
        }
    }
}

final class RecordingEngine: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let captureQueue = DispatchQueue(
        label: "com.screenfree.capture",
        qos: .userInteractive
    )
    private let lock = NSLock()

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var systemAudioSignalProcessor: MicrophoneSignalProcessor?
    private var microphoneSignalProcessor: MicrophoneSignalProcessor?
    private var firstPresentationTime: CMTime?
    private var outputURL: URL?
    private var finishing = false
    private var selectedAudioCapture: SelectedApplicationAudioCapture?
    private let recordingAudioMixer = RecordingAudioMixer()

    private(set) var sourceFrame: CGRect = .zero

    func availableTargets(for mode: CaptureMode) async throws -> [CaptureTarget] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: CaptureContentVisibilityPolicy
                .onScreenWindowsOnly(for: mode)
        )

        switch mode {
        case .display, .area:
            return content.displays.enumerated().map { index, display in
                let outputSize = DisplayPixelGeometryResolver.geometry(
                    displayID: display.displayID,
                    logicalSize: CGSize(width: display.width, height: display.height)
                ).fullDisplayOutputSize
                return CaptureTarget(
                    id: display.displayID,
                    title: "Display \(index + 1) · \(Int(outputSize.width))×\(Int(outputSize.height))",
                    kind: .display,
                    frame: display.frame,
                    isPrimary: display.frame.origin == .zero
                )
            }
        case .window:
            return content.windows
                .filter { $0.isOnScreen && $0.frame.width >= 200 && $0.frame.height >= 120 }
                .map {
                    let app = $0.owningApplication?.applicationName ?? "Application"
                    let name = $0.title?.isEmpty == false ? $0.title! : "Untitled"
                    return CaptureTarget(
                        id: $0.windowID,
                        title: "\(app) — \(name)",
                        kind: .window,
                        frame: $0.frame,
                        isPrimary: false
                    )
                }
        }
    }

    func availableAudioApplications() async throws -> [AudioApplicationOption] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        var seen: Set<String> = []
        return content.applications
            .compactMap { application -> AudioApplicationOption? in
                let identifier = application.bundleIdentifier
                guard identifier != ownBundleIdentifier,
                      !identifier.isEmpty,
                      seen.insert(identifier).inserted else {
                    return nil
                }
                return AudioApplicationOption(
                    id: identifier,
                    name: application.applicationName
                )
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            }
    }

    func thumbnail(for targetID: UInt32) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.displayID == targetID }) else {
            throw RecordingError.noSource
        }
        let ownApplications = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApplications,
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.width = 360
        configuration.height = max(
            180,
            Int(360 * CGFloat(display.height) / max(1, CGFloat(display.width)))
        )
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    func start(
        mode: CaptureMode,
        targetID: UInt32?,
        systemAudioMode: SystemAudioCaptureMode,
        selectedAudioApplicationIDs: Set<String> = [],
        recordMicrophone: Bool,
        microphoneDeviceID: String? = nil,
        reduceMicrophoneNoise: Bool = false,
        normalizeMicrophoneVolume: Bool = false,
        normalizeSystemAudioVolume: Bool = true,
        normalizedArea: CGRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    ) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: CaptureContentVisibilityPolicy
                .onScreenWindowsOnly(for: mode)
        )

        let filter: SCContentFilter
        let configuration = SCStreamConfiguration()
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 8
        configuration.captureResolution = .best
        // The cursor is recorded as an editable 30 fps metadata track by
        // EditorStore. Keeping it out of the source video lets the editor
        // resize it, add click effects, and keep it aligned after cuts.
        configuration.showsCursor = false
        configuration.capturesAudio = systemAudioMode == .all
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true
        if #available(macOS 15.0, *) {
            configuration.captureMicrophone = recordMicrophone
            configuration.microphoneCaptureDeviceID = microphoneDeviceID
        }

        var selectedAudioDisplay: SCDisplay?
        switch mode {
        case .display, .area:
            guard let display = content.displays.first(where: {
                targetID == nil || $0.displayID == targetID
            }) else {
                throw RecordingError.noSource
            }
            let ownApplications = content.applications.filter {
                $0.bundleIdentifier == Bundle.main.bundleIdentifier
            }
            filter = SCContentFilter(
                display: display,
                excludingApplications: ownApplications,
                exceptingWindows: []
            )
            sourceFrame = display.frame
            selectedAudioDisplay = display
            let displayGeometry = DisplayPixelGeometryResolver.geometry(
                displayID: display.displayID,
                logicalSize: CGSize(width: display.width, height: display.height)
            )

            if mode == .area {
                let area = displayGeometry.logicalSourceRect(
                    normalizedArea: normalizedArea
                )
                let outputSize = displayGeometry.areaOutputSize(
                    forLogicalSourceRect: area
                )
                configuration.sourceRect = area
                configuration.width = Int(outputSize.width)
                configuration.height = Int(outputSize.height)
                sourceFrame = CGRect(
                    x: display.frame.minX + display.frame.width * normalizedArea.minX,
                    y: display.frame.minY + display.frame.height * normalizedArea.minY,
                    width: display.frame.width * normalizedArea.width,
                    height: display.frame.height * normalizedArea.height
                )
            } else {
                let outputSize = displayGeometry.fullDisplayOutputSize
                configuration.width = Int(outputSize.width)
                configuration.height = Int(outputSize.height)
            }

        case .window:
            guard let window = content.windows.first(where: {
                targetID == nil || $0.windowID == targetID
            }) else {
                throw RecordingError.noSource
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            sourceFrame = window.frame
            selectedAudioDisplay = content.displays.first {
                $0.frame.intersects(window.frame)
            } ?? content.displays.first
            let displayGeometry = selectedAudioDisplay.map {
                DisplayPixelGeometryResolver.geometry(
                    displayID: $0.displayID,
                    logicalSize: CGSize(width: $0.width, height: $0.height)
                )
            } ?? RecordingDisplayGeometry(
                logicalSize: CGSize(width: 1, height: 1),
                pixelSize: CGSize(width: 1, height: 1)
            )
            let outputSize = displayGeometry.windowOutputSize(
                forLogicalSize: window.frame.size
            )
            configuration.width = Int(outputSize.width)
            configuration.height = Int(outputSize.height)
        }

        let selectedAudioFilter: SCContentFilter?
        if systemAudioMode == .selected {
            let selectedApplications = content.applications.filter {
                selectedAudioApplicationIDs.contains($0.bundleIdentifier)
            }
            guard !selectedApplications.isEmpty,
                  let selectedAudioDisplay else {
                throw RecordingError.noAudioApplications
            }
            selectedAudioFilter = SCContentFilter(
                display: selectedAudioDisplay,
                including: selectedApplications,
                exceptingWindows: []
            )
        } else {
            selectedAudioFilter = nil
        }

        let url = try makeOutputURL(fileExtension: "mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(
                    6_000_000,
                    configuration.width * configuration.height * 4
                ),
                AVVideoMaxKeyFrameIntervalKey: 120
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecordingError.cannotStartWriter }
        writer.add(input)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000
        ]
        let systemAudioInput = systemAudioMode == .all
            ? AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            : nil
        let microphoneInput = recordMicrophone
            ? AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            : nil
        systemAudioInput?.expectsMediaDataInRealTime = true
        microphoneInput?.expectsMediaDataInRealTime = true
        if let systemAudioInput {
            guard writer.canAdd(systemAudioInput) else {
                throw RecordingError.cannotStartWriter
            }
            writer.add(systemAudioInput)
        }
        if let microphoneInput {
            guard writer.canAdd(microphoneInput) else {
                throw RecordingError.cannotStartWriter
            }
            writer.add(microphoneInput)
        }

        lock.withLock {
            self.writer = writer
            self.videoInput = input
            self.systemAudioInput = systemAudioInput
            self.microphoneInput = microphoneInput
            self.systemAudioSignalProcessor = systemAudioMode == .all
                && normalizeSystemAudioVolume
                ? MicrophoneSignalProcessor(
                    settings: .systemAudioLoudness
                )
                : nil
            let enhancement = MicrophoneEnhancementSettings.microphoneLoudness(
                reduceNoise: reduceMicrophoneNoise,
                normalizeVolume: normalizeMicrophoneVolume
            )
            self.microphoneSignalProcessor = recordMicrophone
                && enhancement.isEnabled
                ? MicrophoneSignalProcessor(settings: enhancement)
                : nil
            self.outputURL = url
            self.firstPresentationTime = nil
            self.finishing = false
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(
            self,
            type: .screen,
            sampleHandlerQueue: captureQueue
        )
        if systemAudioMode == .all {
            try stream.addStreamOutput(
                self,
                type: .audio,
                sampleHandlerQueue: captureQueue
            )
        }
        if #available(macOS 15.0, *), recordMicrophone {
            try stream.addStreamOutput(
                self,
                type: .microphone,
                sampleHandlerQueue: captureQueue
            )
        }
        self.stream = stream
        do {
            if let selectedAudioFilter {
                let selectedAudioCapture = try SelectedApplicationAudioCapture(
                    outputURL: makeOutputURL(fileExtension: "m4a"),
                    normalizeVolume: normalizeSystemAudioVolume
                )
                try await selectedAudioCapture.start(
                    filter: selectedAudioFilter
                )
                self.selectedAudioCapture = selectedAudioCapture
            }
            try await stream.startCapture()
        } catch {
            if let selectedAudioCapture = self.selectedAudioCapture {
                _ = try? await selectedAudioCapture.stop()
            }
            self.selectedAudioCapture = nil
            throw error
        }
    }

    func stop() async throws -> URL {
        guard let stream else { throw RecordingError.cannotFinishWriter }

        try await stream.stopCapture()
        self.stream = nil
        let supplemental = try await selectedAudioCapture?.stop()
        selectedAudioCapture = nil

        let (writer, inputs, url): (AVAssetWriter?, [AVAssetWriterInput], URL?) = lock.withLock {
            finishing = true
            systemAudioSignalProcessor = nil
            microphoneSignalProcessor = nil
            return (
                self.writer,
                [self.videoInput, self.systemAudioInput, self.microphoneInput].compactMap { $0 },
                self.outputURL
            )
        }

        guard let writer, let url else {
            throw RecordingError.cannotFinishWriter
        }
        inputs.forEach { $0.markAsFinished() }

        let writerBox = SendableAssetWriter(writer)
        let primaryURL = try await withCheckedThrowingContinuation {
            continuation in
            writer.finishWriting {
                let writer = writerBox.value
                if writer.status == .completed {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(
                        throwing: RecordingError.writerFailed(
                            writer.error.map { String(describing: $0) }
                                ?? "status \(writer.status.rawValue)"
                        )
                    )
                }
            }
        }
        if let supplemental {
            return try await recordingAudioMixer.mix(
                primaryURL: primaryURL,
                supplemental: supplemental,
                primaryFirstPresentationTime: firstPresentationTime
            )
        }
        return primaryURL
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid else { return }
        if outputType == .screen {
            guard Self.isCompleteScreenFrame(sampleBuffer) else { return }
        }

        lock.lock()
        defer { lock.unlock() }
        guard !finishing, let writer, let videoInput else { return }

        let presentationTime = sampleBuffer.presentationTimeStamp
        if firstPresentationTime == nil, outputType == .screen {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: presentationTime)
            firstPresentationTime = presentationTime
        }

        guard let firstPresentationTime,
              presentationTime >= firstPresentationTime else {
            // Audio buffers can arrive after the first video frame while still
            // carrying a slightly earlier timestamp. AVAssetWriter permanently
            // fails if such a buffer is appended before the session start.
            return
        }
        let input: AVAssetWriterInput?
        var recordingBuffer = sampleBuffer
        switch outputType {
        case .screen:
            input = videoInput
        case .audio:
            input = systemAudioInput
            if let processed = systemAudioSignalProcessor?
                .processedSampleBuffer(sampleBuffer) {
                recordingBuffer = processed
            }
        case .microphone:
            input = microphoneInput
            if let processed = microphoneSignalProcessor?
                .processedSampleBuffer(sampleBuffer) {
                recordingBuffer = processed
            }
        @unknown default:
            input = nil
        }
        if let input, input.isReadyForMoreMediaData {
            input.append(recordingBuffer)
        }
    }

    private static func isCompleteScreenFrame(
        _ sampleBuffer: CMSampleBuffer
    ) -> Bool {
        guard sampleBuffer.imageBuffer != nil,
              let frameInfo = CMSampleBufferGetSampleAttachmentsArray(
                  sampleBuffer,
                  createIfNecessary: false
              ) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = frameInfo.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else {
            return false
        }
        return status == .complete
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        // The UI observes writer completion when Stop is pressed. Unexpected stream
        // failures are surfaced by AVAssetWriter during finalization.
    }

    private func makeOutputURL(fileExtension: String) throws -> URL {
        let directory = FileManager.default.urls(
            for: .moviesDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("ScreenFree", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                "ScreenFree",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return directory.appendingPathComponent(
            "Recording-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(6)).\(fileExtension)"
        )
    }
}

private final class SelectedApplicationAudioCapture:
    NSObject,
    SCStreamOutput,
    SCStreamDelegate,
    @unchecked Sendable
{
    private let queue = DispatchQueue(
        label: "com.screenfree.selected-application-audio",
        qos: .userInitiated
    )
    private let lock = NSLock()
    private let outputURL: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let signalProcessor: MicrophoneSignalProcessor?
    private var stream: SCStream?
    private var firstPresentationTime: CMTime?
    private var finishing = false

    init(
        outputURL: URL,
        normalizeVolume: Bool
    ) throws {
        self.outputURL = outputURL
        signalProcessor = normalizeVolume
            ? MicrophoneSignalProcessor(
                settings: .systemAudioLoudness
            )
            : nil
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ]
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw RecordingError.cannotStartWriter
        }
        writer.add(input)
    }

    func start(filter: SCContentFilter) async throws {
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true

        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        try stream.addStreamOutput(
            self,
            type: .audio,
            sampleHandlerQueue: queue
        )
        self.stream = stream
        do {
            try await stream.startCapture()
        } catch {
            self.stream = nil
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    func stop() async throws -> SupplementalAudioRecording? {
        if let stream {
            try await stream.stopCapture()
            self.stream = nil
        }
        let firstPresentationTime = lock.withLock {
            finishing = true
            return self.firstPresentationTime
        }
        guard let firstPresentationTime else {
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }

        input.markAsFinished()
        let writerBox = SendableAssetWriter(writer)
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                let writer = writerBox.value
                if writer.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: writer.error
                            ?? RecordingError.cannotFinishWriter
                    )
                }
            }
        }
        return SupplementalAudioRecording(
            url: outputURL,
            firstPresentationTime: firstPresentationTime
        )
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !finishing else { return }
        let presentationTime = sampleBuffer.presentationTimeStamp
        if firstPresentationTime == nil {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: presentationTime)
            firstPresentationTime = presentationTime
        }
        guard writer.status == .writing,
              input.isReadyForMoreMediaData else {
            return
        }
        let recordingBuffer = signalProcessor?
            .processedSampleBuffer(sampleBuffer) ?? sampleBuffer
        input.append(recordingBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        // Writer status is checked during stop(), where the error is returned
        // through the normal recording finalization path.
    }
}

private final class SendableAssetWriter: @unchecked Sendable {
    let value: AVAssetWriter

    init(_ value: AVAssetWriter) {
        self.value = value
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
