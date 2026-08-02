import AVFoundation
import AppKit
import CoreMedia
import Foundation
import SwiftUI

struct MediaDeviceOption: Identifiable, Hashable {
    let id: String
    let name: String
    let isDefault: Bool
}

enum MicrophoneSelectionPolicy {
    static func requiresPrompt(
        recordsMicrophone: Bool,
        availableMicrophoneCount: Int,
        selectionWasConfirmed: Bool
    ) -> Bool {
        recordsMicrophone
            && availableMicrophoneCount > 1
            && !selectionWasConfirmed
    }
}

enum AudioSignalState {
    case unavailable
    case silent
    case good
    case clipping
}

enum DeviceMonitorError: LocalizedError {
    case cameraNotReady

    var errorDescription: String? {
        switch self {
        case .cameraNotReady:
            return "The selected camera is not ready to record."
        }
    }
}

@MainActor
final class DeviceMonitor: ObservableObject {
    @Published private(set) var microphones: [MediaDeviceOption] = []
    @Published private(set) var cameras: [MediaDeviceOption] = []
    @Published private(set) var microphoneAuthorization: AVAuthorizationStatus = .notDetermined
    @Published private(set) var cameraAuthorization: AVAuthorizationStatus = .notDetermined
    @Published private(set) var microphoneLevel: Double = 0
    @Published private(set) var peakLevel: Double = 0
    @Published private(set) var isMonitoringMicrophone = false
    @Published private(set) var previewingCameraID: String?
    @Published private(set) var deviceError: String?

    let cameraSession = AVCaptureSession()

    private var audioEngine: AVAudioEngine?
    private let cameraMovieOutput = AVCaptureMovieFileOutput()
    private var cameraRecordingDelegate: CameraRecordingDelegate?
    private var cameraRecordingURL: URL?

    var audioSignalState: AudioSignalState {
        guard isMonitoringMicrophone else { return .unavailable }
        if peakLevel >= 0.96 { return .clipping }
        if microphoneLevel < 0.025 { return .silent }
        return .good
    }

    func refresh() {
        microphoneAuthorization = AVCaptureDevice.authorizationStatus(for: .audio)
        cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)

        let defaultAudioID = AVCaptureDevice.default(for: .audio)?.uniqueID
        let audioDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        microphones = audioDiscovery.devices.map {
            MediaDeviceOption(
                id: $0.uniqueID,
                name: $0.localizedName,
                isDefault: $0.uniqueID == defaultAudioID
            )
        }

        let defaultVideoID = AVCaptureDevice.default(for: .video)?.uniqueID
        let videoDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        cameras = videoDiscovery.devices.map {
            MediaDeviceOption(
                id: $0.uniqueID,
                name: $0.localizedName,
                isDefault: $0.uniqueID == defaultVideoID
            )
        }
    }

    func requestMicrophoneAccess() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
        return granted
    }

    func requestCameraAccess() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        refresh()
        return granted
    }

    func toggleMicrophoneMeter() async {
        if isMonitoringMicrophone {
            stopMicrophoneMeter()
            return
        }
        if microphoneAuthorization != .authorized,
           !(await requestMicrophoneAccess()) {
            deviceError = "Microphone permission is required to test the input."
            return
        }
        startMicrophoneMeter()
    }

    func startMicrophoneMeter() {
        stopMicrophoneMeter()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            deviceError = "The selected microphone has no readable audio format."
            return
        }

        input.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format
        ) { [weak self] buffer, _ in
            guard let samples = buffer.floatChannelData?.pointee else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            var peak: Float = 0
            for index in 0..<count {
                let value = abs(samples[index])
                sum += value * value
                peak = max(peak, value)
            }
            let rms = sqrt(sum / Float(count))
            let normalized = min(1, max(0, Double(rms) * 7.5))
            let normalizedPeak = min(1, max(0, Double(peak)))
            Task { @MainActor [weak self] in
                guard let self else { return }
                microphoneLevel = microphoneLevel * 0.68 + normalized * 0.32
                peakLevel = max(normalizedPeak, peakLevel * 0.9)
            }
        }

        do {
            try engine.start()
            audioEngine = engine
            isMonitoringMicrophone = true
            deviceError = nil
        } catch {
            input.removeTap(onBus: 0)
            deviceError = error.localizedDescription
        }
    }

    func stopMicrophoneMeter() {
        guard let audioEngine else {
            microphoneLevel = 0
            peakLevel = 0
            isMonitoringMicrophone = false
            return
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        self.audioEngine = nil
        microphoneLevel = 0
        peakLevel = 0
        isMonitoringMicrophone = false
    }

    func showCameraPreview(deviceID: String?) async {
        guard let deviceID else {
            stopCameraPreview()
            return
        }
        if cameraAuthorization != .authorized,
           !(await requestCameraAccess()) {
            deviceError = "Camera permission is required to show a preview."
            return
        }
        guard let device = cameras
            .first(where: { $0.id == deviceID })
            .flatMap({ option in
                AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.builtInWideAngleCamera, .external],
                    mediaType: .video,
                    position: .unspecified
                )
                .devices
                .first(where: { $0.uniqueID == option.id })
            }) else {
            deviceError = "The selected camera is no longer connected."
            refresh()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            cameraSession.beginConfiguration()
            for existing in cameraSession.inputs {
                cameraSession.removeInput(existing)
            }
            if cameraSession.canAddInput(input) {
                cameraSession.addInput(input)
            }
            if !cameraSession.outputs.contains(where: { $0 === cameraMovieOutput }),
               cameraSession.canAddOutput(cameraMovieOutput) {
                cameraSession.addOutput(cameraMovieOutput)
            }
            cameraSession.sessionPreset = .high
            cameraSession.commitConfiguration()
            if !cameraSession.isRunning {
                cameraSession.startRunning()
            }
            previewingCameraID = deviceID
            deviceError = nil
        } catch {
            cameraSession.commitConfiguration()
            deviceError = error.localizedDescription
        }
    }

    func stopCameraPreview() {
        if cameraSession.isRunning {
            cameraSession.stopRunning()
        }
        cameraSession.beginConfiguration()
        for existing in cameraSession.inputs {
            cameraSession.removeInput(existing)
        }
        cameraSession.commitConfiguration()
        previewingCameraID = nil
    }

    func startCameraRecording() throws {
        guard previewingCameraID != nil, cameraSession.isRunning else {
            throw DeviceMonitorError.cameraNotReady
        }
        guard !cameraMovieOutput.isRecording else { return }
        let directory = (
            FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
        )
        .appendingPathComponent("ScreenFree/Camera", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("\(UUID().uuidString).mov")
        let delegate = CameraRecordingDelegate()
        cameraRecordingDelegate = delegate
        cameraRecordingURL = url
        cameraMovieOutput.startRecording(to: url, recordingDelegate: delegate)
    }

    func stopCameraRecording() async throws -> URL? {
        guard cameraMovieOutput.isRecording,
              let delegate = cameraRecordingDelegate,
              let url = cameraRecordingURL else {
            return nil
        }
        cameraMovieOutput.stopRecording()
        try await delegate.waitForFinish()
        cameraRecordingDelegate = nil
        cameraRecordingURL = nil
        return url
    }
}

private final class CameraRecordingDelegate:
    NSObject,
    AVCaptureFileOutputRecordingDelegate,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var result: Result<Void, Error>?
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForFinish() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let existing = lock.withLock { () -> Result<Void, Error>? in
                if let result { return result }
                self.continuation = continuation
                return nil
            }
            if let existing {
                continuation.resume(with: existing)
            }
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let result: Result<Void, Error> = error.map(Result.failure) ?? .success(())
        let continuation = lock.withLock {
            self.result = result
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

final class CameraPreviewNSView: NSView {
    override func makeBackingLayer() -> CALayer {
        AVCaptureVideoPreviewLayer()
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.wantsLayer = true
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
    }
}
