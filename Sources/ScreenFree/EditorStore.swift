import AppKit
import AVFoundation
import Combine
import Foundation
import ScreenFreeCore
import UniformTypeIdentifiers

enum FrameExportError: LocalizedError {
    case cannotEncodePNG
    case cannotWritePasteboard

    var errorDescription: String? {
        switch self {
        case .cannotEncodePNG:
            return "The current frame could not be encoded as PNG."
        case .cannotWritePasteboard:
            return "The current frame could not be copied to the clipboard."
        }
    }
}

enum AudioBackgroundError: LocalizedError {
    case missingAudioTrack

    var errorDescription: String? {
        "The selected background music does not contain a usable audio track."
    }
}

struct TimelineThumbnailFrame: Identifiable {
    let id: Int
    let sourceTime: TimeInterval
    let image: NSImage
}

enum CursorCaptureGate {
    static func allows(
        callbackSessionID: UUID,
        activeSessionID: UUID?,
        isRecording: Bool,
        isPaused: Bool,
        isTransitioning: Bool
    ) -> Bool {
        callbackSessionID == activeSessionID
            && isRecording
            && !isPaused
            && !isTransitioning
    }
}

@MainActor
final class EditorStore: ObservableObject {
    enum TimelineEditTool: Equatable {
        case selection
        case split
        case redaction
    }

    enum TimelineContinuousEditKind: Equatable {
        case clip
        case zoom
        case redaction

        fileprivate var actionName: String {
            switch self {
            case .clip: return "Edit Clip"
            case .zoom: return "Edit Zoom"
            case .redaction: return "Edit Privacy Block"
            }
        }
    }

    enum TimelineBlockTarget: Equatable {
        case clip(UUID)
        case zoom(UUID)
        case redaction(UUID)
    }

    enum PlaybackBoundaryAction: Equatable {
        case continueTransport
        case seek
    }

    private struct TimelineEditorSnapshot {
        var project: TimelineProject
        var selectedClipID: UUID?
        var selectedZoomID: UUID?
        var selectedRedactionID: UUID?
        var hoveredTimelineBlock: TimelineBlockTarget?
        var inspectorPanel: InspectorPanel
        var activeTimelineTool: TimelineEditTool
        var playhead: TimeInterval
    }

    private struct TimelineHistoryEntry {
        var actionName: String
        var snapshot: TimelineEditorSnapshot
    }

    private struct ActiveTimelineContinuousEdit {
        var kind: TimelineContinuousEditKind
        var snapshot: TimelineEditorSnapshot
        var hasChanges = false
    }

    enum InspectorPanel: String, CaseIterable, Identifiable {
        case canvas = "Canvas"
        case cursor = "Cursor"
        case audio = "Audio"
        case camera = "Camera"
        case captions = "Captions"
        case clip = "Clip"
        case zoom = "Zoom"
        case transition = "Transitions"
        case privacy = "Privacy"
        case export = "Export"

        var id: Self { self }

        var symbol: String {
            switch self {
            case .canvas: return "rectangle.inset.filled"
            case .cursor: return "cursorarrow.motionlines"
            case .audio: return "waveform"
            case .camera: return "video.circle"
            case .captions: return "captions.bubble"
            case .clip: return "film.stack"
            case .zoom: return "plus.magnifyingglass"
            case .transition: return "rectangle.2.swap"
            case .privacy: return "eye.slash"
            case .export: return "square.and.arrow.up"
            }
        }
    }

    enum AppScreen: Equatable {
        case home
        case recordingSetup
        case editor
    }

    @Published var inspectorPanel: InspectorPanel = .canvas
    @Published var appScreen: AppScreen = .home
    private var screenBeforeSetup: AppScreen = .home
    @Published var captureMode: CaptureMode = .display
    @Published var captureTargets: [CaptureTarget] = []
    @Published var captureThumbnails: [UInt32: NSImage] = [:]
    @Published var selectedTargetID: UInt32?
    @Published var areaInset: Double = 10
    @Published var selectedAreaNormalized = CGRect(
        x: 0.1,
        y: 0.1,
        width: 0.8,
        height: 0.8
    )
    @Published var systemAudioMode: SystemAudioCaptureMode = .all
    @Published var audioApplications: [AudioApplicationOption] = []
    @Published var selectedAudioApplicationIDs: Set<String> = []
    @Published var recordMicrophone = true
    @Published var selectedMicrophoneID: String?
    @Published var reduceMicrophoneNoise: Bool {
        didSet {
            UserDefaults.standard.set(
                reduceMicrophoneNoise,
                forKey: "reduceMicrophoneNoise"
            )
        }
    }
    @Published var normalizeMicrophoneVolume: Bool {
        didSet {
            UserDefaults.standard.set(
                normalizeMicrophoneVolume,
                forKey: "normalizeMicrophoneVolume"
            )
        }
    }
    @Published var normalizeSystemAudioVolume: Bool {
        didSet {
            UserDefaults.standard.set(
                normalizeSystemAudioVolume,
                forKey: "normalizeSystemAudioVolume"
            )
        }
    }
    @Published var selectedCameraID: String?
    @Published var countdownSeconds = 3
    @Published var highlightRecordingArea = true
    @Published var hideDockIconWhileRecording: Bool {
        didSet {
            UserDefaults.standard.set(
                hideDockIconWhileRecording,
                forKey: "hideDockIconWhileRecording"
            )
        }
    }
    @Published var hideDesktopIconsWhileRecording: Bool {
        didSet {
            UserDefaults.standard.set(
                hideDesktopIconsWhileRecording,
                forKey: "hideDesktopIconsWhileRecording"
            )
        }
    }
    @Published var hideCameraPreview: Bool {
        didSet {
            UserDefaults.standard.set(
                hideCameraPreview,
                forKey: "hideCameraPreview"
            )
        }
    }
    @Published var automaticallyCreateZooms: Bool {
        didSet {
            UserDefaults.standard.set(
                automaticallyCreateZooms,
                forKey: "automaticallyCreateZooms"
            )
        }
    }
    @Published var afterRecordingAction: AfterRecordingAction {
        didSet {
            UserDefaults.standard.set(
                afterRecordingAction.rawValue,
                forKey: "afterRecordingAction"
            )
        }
    }
    /// 本次录制实际使用的口播稿；开录瞬间捕获，随项目快照落盘。
    /// 编辑器当前会话的 `scriptText` 在录制中不可编辑（提词器只读），
    /// 单独持有可避免录制后到下次开录之间的任何改动污染项目。
    private(set) var recordingScriptText: String?
    @Published var scriptText = ""
    @Published var recentScripts: [RecentScriptEntry] = []
    @Published var prompterFontSize: Double {
        didSet {
            UserDefaults.standard.set(
                prompterFontSize,
                forKey: "teleprompterFontSize"
            )
        }
    }
    @Published var prompterSpeed: Double {
        didSet {
            UserDefaults.standard.set(
                prompterSpeed,
                forKey: "teleprompterSpeed"
            )
        }
    }
    /// 手动接管（⌥空格 / 面板按钮 / 拖动面板）后为 true，自动滚动暂停。
    @Published var prompterPaused = false
    @Published var teleprompterPanelSize: CGSize {
        didSet {
            let clamped = RecordingTeleprompterPresentation.clamped(
                size: teleprompterPanelSize
            )
            teleprompterPanelSize = clamped
            UserDefaults.standard.set(
                Double(clamped.width),
                forKey: "teleprompterPanelWidth"
            )
            UserDefaults.standard.set(
                Double(clamped.height),
                forKey: "teleprompterPanelHeight"
            )
        }
    }
    @Published var capturePermissionIssue = false
    @Published var inputMonitoringGranted = false
    @Published var isPreparingRecording = false
    @Published var recordingCountdownRemaining = 0
    @Published var recordingElapsed: TimeInterval = 0
    @Published var isRecordingPaused = false
    @Published var isTransitioningRecording = false
    @Published var recordingDrawingTool: AnnotationKind? {
        didSet {
            recordingWindowCoordinator.updateDrawingInteraction()
        }
    }
    @Published var recordingAnnotationColor: AnnotationColor = .red
    @Published var recordingAnnotationLineWidth: CGFloat = 5

    @Published var sourceURL: URL?
    @Published var cameraURL: URL?
    @Published var project = TimelineProject()
    @Published var selectedClipID: UUID?
    @Published var selectedZoomID: UUID?
    /// Multi-selection for zoom blocks (marquee, ⌘-click, Select All). When
    /// it holds more than one id, Delete removes the whole set at once.
    @Published var selectedZoomIDs: Set<UUID> = []
    @Published var selectedRedactionID: UUID?
    @Published private(set) var hoveredTimelineBlock: TimelineBlockTarget?
    @Published var activeTimelineTool: TimelineEditTool = .selection
    @Published var timelineZoom = TimelineScale.fitZoom
    @Published private(set) var timelineUndoTitle: String?
    @Published private(set) var timelineRedoTitle: String?
    @Published private(set) var recordingHistory: [RecordingHistoryItem] = []

    @Published var playhead: TimeInterval = 0
    private let scrubSeekInterval: TimeInterval = 1.0 / 60.0
    private var isScrubSeekInFlight = false
    private var pendingScrubTime: TimeInterval?
    private var lastScrubSeekTarget: TimeInterval?
    private var lastScrubSeekDispatchAt: UInt64?
    /// True while an interactive drag owns the playhead. The periodic time
    /// observer must not write the playhead while this is set, and playback
    /// resumes on release when the drag interrupted an active playback.
    private(set) var isScrubbing = false
    private var wasPlayingBeforeScrub = false
    @Published var isPlaying = false
    @Published var isRecording = false
    @Published var isExporting = false
    @Published private(set) var isVideoExporting = false
    @Published var isExportSheetPresented = false
    @Published var isMicrophoneSelectionPresented = false
    @Published var exportProgress: Double = 0
    @Published var exportDestination: ExportDestination = .file
    @Published var exportFormat: ExportFormat = .mp4
    @Published var exportResolution: ExportResolution = .source
    @Published var exportCustomWidth = 1920
    @Published var exportCustomHeight = 1080
    @Published var exportQuality: ExportQuality = .studio
    @Published var exportFrameRate = 60
    @Published var audioAnalysis: AudioAnalysis = .empty
    @Published private(set) var timelineThumbnails: [TimelineThumbnailFrame] = []
    @Published var backgroundMusicURL: URL?
    @Published var backgroundMusicVolume: Double = 0.2 {
        didSet {
            backgroundMusicPlayer.volume = Float(
                backgroundMusicVolume.clamped(to: 0...1)
            )
        }
    }
    @Published var recordedAudioLayout: RecordedAudioLayout?
    @Published var systemAudioVolume: Double = 1 {
        didSet { refreshSourceAudioMix() }
    }
    @Published var microphoneAudioVolume: Double = 1 {
        didSet { refreshSourceAudioMix() }
    }
    @Published var microphoneAudioMuted = false {
        didSet { refreshSourceAudioMix() }
    }
    @Published private(set) var backgroundMusicDuration: TimeInterval = 0
    @Published var sourceDuration: TimeInterval = 0
    @Published var sourceAspectRatio: Double = 16 / 9
    @Published var sourcePixelSize = CGSize(width: 1_920, height: 1_080)
    @Published var sourceFrameRate: Double = 60
    @Published var isAnalyzingAudio = false
    @Published var isGeneratingCaptions = false
    @Published var showCaptions = true
    @Published var captionFontSize: Double = 34
    @Published var captionLanguage = "zh-CN"
    @Published var captionVocabulary = ""

    @Published var cursorSize: Double = 1.3
    @Published var cursorReplacement: CursorReplacementStyle = .arrow
    @Published var showCursor = true
    @Published var hideCursorWhenIdle = false
    @Published var cursorIdleTimeout: Double = 2
    @Published var cursorTailFreeze: Double = 0
    @Published var cursorLoopToStart = false
    @Published var removeCursorShakes = true
    @Published var cursorShakeThreshold: Double = 0.012
    @Published var optimizeRapidCursorChanges = true
    @Published var smoothCursorMovement = true
    @Published var clickEffectPreset: ClickEffectPreset = .ripple
    @Published var showShortcutOverlay = true
    @Published var canvasAspectRatio: CanvasAspectRatio = .source
    @Published var canvasContentMode: CanvasContentMode = .fit
    @Published var canvasPadding: Double = 32
    @Published var cornerRadius: Double = 18
    @Published var backgroundHue: Double = 0.68
    @Published var backgroundMode: CanvasBackgroundMode = .gradient
    @Published var wallpaperPreset: WallpaperPreset = .aurora
    @Published var backgroundImageURL: URL?
    @Published var backgroundBlur: Double = 0
    @Published var shadowStrength: Double = 0.52
    @Published var zoomScale: Double = 1.8
    @Published var zoomDuration: Double = 3.2
    @Published var transitionStyle: ClipTransitionStyle = .fade
    @Published var transitionDuration: Double = 0.4
    @Published var selectedTransitionID: UUID?
    @Published var zoomMotionPreset: ZoomMotionPreset = .mellow
    @Published var zoomCustomTransitionDuration: Double = 0.82
    @Published var zoomCustomX1: Double = 0.25
    @Published var zoomCustomY1: Double = 0.1
    @Published var zoomCustomX2: Double = 0.25
    @Published var zoomCustomY2: Double = 1
    @Published var motionBlurEnabled = false
    @Published var motionBlurStrength: Double = 0.42
    @Published var cursorMotionBlur: Double = 0.58
    @Published var zoomMotionBlur: Double = 0.45
    @Published var panMotionBlur: Double = 0.34
    @Published var cameraSize: Double = 0.24
    @Published var cameraCornerRadius: Double = 18
    @Published var cameraMirrored = true
    @Published var cameraPosition: CameraPosition = .bottomRight
    @Published var statusMessage = "Choose a source and start recording."
    @Published var errorMessage: String?
    @Published var appLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage")
        }
    }

    let player = AVPlayer()
    let cameraPlayer = AVPlayer()
    let backgroundMusicPlayer = AVPlayer()
    let deviceMonitor = DeviceMonitor()
    lazy var recordingWindowCoordinator = RecordingWindowCoordinator(store: self)
    lazy var areaSelectionCoordinator = AreaSelectionCoordinator()

    private let recorder = RecordingEngine()
    private let exporter = VideoExporter()
    private let audioAnalyzer = AudioAnalyzer()
    private let captionGenerator = CaptionGenerator()
    private let persistence: ProjectPersistence
    private let segmentMerger = RecordingSegmentMerger()
    private let videoPasteboardWriter = VideoPasteboardWriter()
    private let originalRecordingDelivery = OriginalRecordingDelivery()
    private let originalMediaExporter = OriginalMediaExporter()
    private let stylePresetPersistence = StylePresetPersistence()
    private let recordingHistoryCatalog: RecordingHistoryCatalog
    private var timeObserver: Any?
    private var cursorTimer: Timer?
    private var activeCursorCaptureSessionID: UUID?
    private var globalClickMonitor: Any?
    private var globalKeyMonitor: Any?
    private var pendingRightClickID: UUID?
    private var recordingStartUptime: TimeInterval?
    private var recordingAccumulatedDuration: TimeInterval = 0
    private var recordingSegments: [URL] = []
    private var cameraRecordingSegments: [URL] = []
    private var activeRecordingAudioLayout: RecordedAudioLayout?
    private var recordingElapsedTimer: Timer?
    private var exportTask: Task<Void, Never>?
    private var timelineThumbnailTask: Task<Void, Never>?
    private var timelineThumbnailGeneration = UUID()
    private var activeSharingPicker: NSSharingServicePicker?
    private var audioMixRefreshGeneration = 0
    private var cancellables: Set<AnyCancellable> = []
    private var isRestoringProject = false
    private var timelineUndoStack: [TimelineHistoryEntry] = []
    private var timelineRedoStack: [TimelineHistoryEntry] = []
    private var activeTimelineContinuousEdit: ActiveTimelineContinuousEdit?

    init(
        recordingHistoryCatalog: RecordingHistoryCatalog =
            RecordingHistoryCatalog(),
        persistence: ProjectPersistence = ProjectPersistence()
    ) {
        self.recordingHistoryCatalog = recordingHistoryCatalog
        self.persistence = persistence
        let storedLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        appLanguage = AppLanguage(rawValue: storedLanguage ?? "") ?? .system
        reduceMicrophoneNoise = UserDefaults.standard.object(
            forKey: "reduceMicrophoneNoise"
        ) as? Bool ?? true
        normalizeMicrophoneVolume = UserDefaults.standard.object(
            forKey: "normalizeMicrophoneVolume"
        ) as? Bool ?? true
        normalizeSystemAudioVolume = UserDefaults.standard.object(
            forKey: "normalizeSystemAudioVolume"
        ) as? Bool ?? true
        hideDockIconWhileRecording =
            UserDefaults.standard.object(
                forKey: "hideDockIconWhileRecording"
            ) as? Bool ?? true
        hideDesktopIconsWhileRecording =
            UserDefaults.standard.object(
                forKey: "hideDesktopIconsWhileRecording"
            ) as? Bool ?? false
        hideCameraPreview = UserDefaults.standard.object(
            forKey: "hideCameraPreview"
        ) as? Bool ?? false
        automaticallyCreateZooms = UserDefaults.standard.object(
            forKey: "automaticallyCreateZooms"
        ) as? Bool ?? true
        afterRecordingAction = AfterRecordingAction(
            rawValue: UserDefaults.standard.string(
                forKey: "afterRecordingAction"
            ) ?? ""
        ) ?? .edit
        SpeakerNotesMigration.run()
        recentScripts = RecentScriptsStore().load()
        prompterFontSize = UserDefaults.standard.object(
            forKey: "teleprompterFontSize"
        ) as? Double ?? 22
        prompterSpeed = UserDefaults.standard.object(
            forKey: "teleprompterSpeed"
        ) as? Double ?? 1
        teleprompterPanelSize = RecordingTeleprompterPresentation.clamped(
            size: CGSize(
                width: UserDefaults.standard.object(
                    forKey: "teleprompterPanelWidth"
                ) as? Double
                    ?? RecordingTeleprompterPresentation.defaultPanelSize.width,
                height: UserDefaults.standard.object(
                    forKey: "teleprompterPanelHeight"
                ) as? Double
                    ?? RecordingTeleprompterPresentation.defaultPanelSize.height
            )
        )
        pruneClipboardExports()
        installAutosave()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        recordingElapsedTimer?.invalidate()
        exportTask?.cancel()
    }

    func prepare() async {
        recordingWindowCoordinator.recoverDesktopIconsIfNeeded()
        installPlayerObserver()
        refreshRecordingHistory()
        await refreshPermissionState()
        await refreshAudioApplications()
        if selectedMicrophoneID == nil {
            selectedMicrophoneID = deviceMonitor.microphones.first(where: \.isDefault)?.id
                ?? deviceMonitor.microphones.first?.id
        }
    }

    func refreshPermissionState() async {
        inputMonitoringGranted = CGPreflightListenEventAccess()
        deviceMonitor.refresh()
        if CGPreflightScreenCaptureAccess() {
            capturePermissionIssue = false
            await refreshCaptureTargets()
        } else {
            capturePermissionIssue = true
            statusMessage = "Screen recording permission is required."
        }
    }

    func applicationWillTerminate() {
        pausePreviewPlayback()
        recordingWindowCoordinator.restoreDesktopIconsForTermination()
    }

    /// A `WindowGroup` can outlive its last visible window. Stop every preview
    /// player explicitly so closing the editor cannot leave audio running in
    /// the still-alive application process.
    func editorWindowDidClose() {
        pausePreviewPlayback()
    }

    func refreshCaptureTargets() async {
        do {
            captureTargets = try await recorder.availableTargets(for: captureMode)
            capturePermissionIssue = false
            if !captureTargets.contains(where: { $0.id == selectedTargetID }) {
                selectedTargetID = captureTargets.first?.id
            }
            captureThumbnails.removeAll()
            if captureMode != .window {
                for target in captureTargets {
                    if let image = try? await recorder.thumbnail(for: target.id) {
                        captureThumbnails[target.id] = NSImage(
                            cgImage: image,
                            size: NSSize(width: image.width, height: image.height)
                        )
                    }
                }
            }
        } catch {
            captureTargets = []
            capturePermissionIssue = true
            statusMessage = "Screen recording permission is required."
        }
    }

    func refreshAudioApplications() async {
        do {
            audioApplications = try await recorder.availableAudioApplications()
            selectedAudioApplicationIDs.formIntersection(
                Set(audioApplications.map(\.id))
            )
        } catch {
            audioApplications = []
        }
    }

    func startOrStopRecording() async {
        if isRecording {
            await stopRecording()
        } else if isPreparingRecording {
            cancelRecordingPreparation()
        } else {
            await startRecording()
        }
    }

    func startRecording(
        microphoneSelectionConfirmed: Bool = false
    ) async {
        guard !isRecording, !isPreparingRecording else { return }
        do {
            if capturePermissionIssue {
                await requestScreenRecordingPermission()
                return
            }
            if recordMicrophone {
                guard #available(macOS 15.0, *) else {
                    errorMessage = "Microphone recording requires macOS 15 or later."
                    return
                }
                deviceMonitor.refresh()
                if !deviceMonitor.microphones.contains(where: {
                    $0.id == selectedMicrophoneID
                }) {
                    selectedMicrophoneID =
                        deviceMonitor.microphones.first(where: \.isDefault)?.id
                        ?? deviceMonitor.microphones.first?.id
                }
                guard selectedMicrophoneID != nil else {
                    errorMessage = "No microphone was detected."
                    return
                }
                if MicrophoneSelectionPolicy.requiresPrompt(
                    recordsMicrophone: recordMicrophone,
                    availableMicrophoneCount:
                        deviceMonitor.microphones.count,
                    selectionWasConfirmed: microphoneSelectionConfirmed
                ) {
                    isMicrophoneSelectionPresented = true
                    return
                }
            }
            isMicrophoneSelectionPresented = false
            if recordMicrophone,
               deviceMonitor.microphoneAuthorization != .authorized,
               !(await deviceMonitor.requestMicrophoneAccess()) {
                errorMessage = "Microphone permission is required when microphone recording is enabled."
                return
            }
            if let selectedCameraID {
                if deviceMonitor.cameraAuthorization != .authorized,
                   !(await deviceMonitor.requestCameraAccess()) {
                    errorMessage = "Camera permission is required to record picture-in-picture video."
                    return
                }
                if deviceMonitor.previewingCameraID != selectedCameraID {
                    await deviceMonitor.showCameraPreview(deviceID: selectedCameraID)
                }
                guard deviceMonitor.previewingCameraID == selectedCameraID else {
                    errorMessage = deviceMonitor.deviceError
                        ?? DeviceMonitorError.cameraNotReady.localizedDescription
                    return
                }
            }
            if recordMicrophone, !deviceMonitor.isMonitoringMicrophone {
                deviceMonitor.startMicrophoneMeter()
            }
            isPreparingRecording = true
            isRecordingPaused = false
            isTransitioningRecording = false
            recordingSegments.removeAll()
            cameraRecordingSegments.removeAll()
            activeRecordingAudioLayout = .recording(
                systemAudioMode: systemAudioMode,
                recordMicrophone: recordMicrophone
            )
            recordedAudioLayout = nil
            systemAudioVolume = 1
            microphoneAudioVolume = 1
            microphoneAudioMuted = false
            recordingAccumulatedDuration = 0
            recordingCountdownRemaining = countdownSeconds
            recordingElapsed = 0
            player.pause()
            isPlaying = false
            try recordingWindowCoordinator.present(
                onDisplayID: selectedTargetID,
                hideDockIcon: hideDockIconWhileRecording,
                hideDesktopIcons: effectiveHideDesktopIconsWhileRecording
            )
            if countdownSeconds > 0 {
                for remaining in stride(from: countdownSeconds, through: 1, by: -1) {
                    guard isPreparingRecording else { return }
                    recordingCountdownRemaining = remaining
                    recordingWindowCoordinator.updateCountdown(
                        onDisplayID: selectedTargetID
                    )
                    statusMessage = "Recording starts in \(remaining)…"
                    try await Task.sleep(for: .seconds(1))
                }
            }
            guard isPreparingRecording else { return }
            recordingCountdownRemaining = 0
            recordingWindowCoordinator.updateCountdown(
                onDisplayID: selectedTargetID
            )
            try await recorder.start(
                mode: captureMode,
                targetID: selectedTargetID,
                systemAudioMode: systemAudioMode,
                selectedAudioApplicationIDs: selectedAudioApplicationIDs,
                recordMicrophone: recordMicrophone,
                microphoneDeviceID: selectedMicrophoneID,
                reduceMicrophoneNoise: reduceMicrophoneNoise,
                normalizeMicrophoneVolume: normalizeMicrophoneVolume,
                normalizeSystemAudioVolume: normalizeSystemAudioVolume,
                normalizedArea: selectedAreaNormalized
            )
            refreshRecordingHighlight()
            refreshRecordingDrawing()
            if selectedCameraID != nil {
                do {
                    try deviceMonitor.startCameraRecording()
                } catch {
                    _ = try? await recorder.stop()
                    throw error
                }
            }
            isPreparingRecording = false
            isRecording = true
            recordingStartUptime = ProcessInfo.processInfo.systemUptime
            beginRecordingElapsedTimer()
            clearTimelineHistory()
            project = TimelineProject()
            sourceURL = nil
            canvasAspectRatio = .source
            canvasContentMode = .fit
            playhead = 0
            beginMouseCapture()
            recordingScriptText = Self.normalizedScript(scriptText)
            prompterPaused = false
            persistLastRecordingSetup()
            recordRecentScriptIfNeeded()
            statusMessage = "Recording… click Stop when you are finished."
        } catch {
            isPreparingRecording = false
            recordingCountdownRemaining = 0
            recordingWindowCoordinator.dismissAndRestoreEditor()
            activeRecordingAudioLayout = nil
            errorMessage = error.localizedDescription
        }
    }

    private var effectiveHideDesktopIconsWhileRecording: Bool {
        #if APP_STORE
            false
        #else
            hideDesktopIconsWhileRecording
        #endif
    }

    func stopRecording() async {
        guard isRecording else {
            cancelRecordingPreparation()
            return
        }
        guard !isTransitioningRecording else { return }
        isTransitioningRecording = true
        defer { isTransitioningRecording = false }
        endMouseCapture()
        endRecordingElapsedTimer()
        do {
            if !isRecordingPaused {
                recordingAccumulatedDuration = currentRecordingElapsed
                recordingSegments.append(try await recorder.stop())
                if let cameraSegment = try? await deviceMonitor.stopCameraRecording() {
                    cameraRecordingSegments.append(cameraSegment)
                }
            }
            let url = try await segmentMerger.merge(
                recordingSegments,
                fileExtension: "mp4"
            )
            let recordedInteractions = RecordingInteractionArchive(
                project: project
            )
            try await RecordingInteractionMetadata.write(
                recordedInteractions,
                to: url
            )
            refreshRecordingHistory()
            let recordedCameraURL = afterRecordingAction == .edit
                && !cameraRecordingSegments.isEmpty
                ? try await segmentMerger.merge(
                    cameraRecordingSegments,
                    fileExtension: "mov"
                )
                : nil
            isRecording = false
            isRecordingPaused = false
            recordingWindowCoordinator.dismissAndRestoreEditor()
            appScreen = .editor
            switch afterRecordingAction {
            case .edit:
                statusMessage = "Recording saved. Preparing the timeline…"
                try await loadVideo(
                    url,
                    preservingCapturedMetadata: true
                )
                cameraURL = recordedCameraURL
                recordedAudioLayout = activeRecordingAudioLayout
                refreshSourceAudioMix()
                if let recordedCameraURL {
                    cameraPlayer.replaceCurrentItem(
                        with: AVPlayerItem(url: recordedCameraURL)
                    )
                    await cameraPlayer.seek(to: .zero)
                }
                if AutomaticZoomPolicy.shouldGenerate(
                    enabled: automaticallyCreateZooms,
                    clicks: project.clicks
                ) {
                    project.generateZoomsFromClicks(
                        scale: zoomScale,
                        duration: zoomDuration
                    )
                    selectedZoomID = project.zooms.first?.id
                }
                try saveRecordingProjectSidecarIfNeeded()
                inspectorPanel = .zoom
                statusMessage =
                    "Recording ready — trim, split, or edit cursor zooms."
            case .clipboard:
                try videoPasteboardWriter.write(fileURL: url)
                statusMessage =
                    "Copied the original recording to the clipboard."
            case .file:
                if let destination = try saveOriginalRecording(url) {
                    statusMessage =
                        "Saved original recording \(destination.lastPathComponent)"
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                } else {
                    statusMessage =
                        "Recording kept in ScreenFree because saving was cancelled."
                }
            }
            activeRecordingAudioLayout = nil
        } catch {
            _ = try? await deviceMonitor.stopCameraRecording()
            isRecording = false
            isRecordingPaused = false
            recordingWindowCoordinator.dismissAndRestoreEditor()
            activeRecordingAudioLayout = nil
            errorMessage = error.localizedDescription
        }
    }

    func toggleRecordingPause() async {
        guard isRecording, !isTransitioningRecording else { return }
        isTransitioningRecording = true
        defer { isTransitioningRecording = false }

        if isRecordingPaused {
            do {
                try await recorder.start(
                    mode: captureMode,
                    targetID: selectedTargetID,
                    systemAudioMode: systemAudioMode,
                    selectedAudioApplicationIDs: selectedAudioApplicationIDs,
                    recordMicrophone: recordMicrophone,
                    microphoneDeviceID: selectedMicrophoneID,
                    reduceMicrophoneNoise: reduceMicrophoneNoise,
                    normalizeMicrophoneVolume: normalizeMicrophoneVolume,
                    normalizeSystemAudioVolume: normalizeSystemAudioVolume,
                    normalizedArea: selectedAreaNormalized
                )
                refreshRecordingHighlight()
                refreshRecordingDrawing()
                if selectedCameraID != nil {
                    do {
                        try deviceMonitor.startCameraRecording()
                    } catch {
                        _ = try? await recorder.stop()
                        throw error
                    }
                }
                recordingStartUptime = ProcessInfo.processInfo.systemUptime
                isRecordingPaused = false
                beginRecordingElapsedTimer()
                beginMouseCapture()
                statusMessage = "Recording resumed."
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        endMouseCapture()
        endRecordingElapsedTimer()
        do {
            recordingAccumulatedDuration = currentRecordingElapsed
            recordingSegments.append(try await recorder.stop())
            if let cameraSegment = try? await deviceMonitor.stopCameraRecording() {
                cameraRecordingSegments.append(cameraSegment)
            }
            isRecordingPaused = true
            recordingElapsed = recordingAccumulatedDuration
            statusMessage = "Recording paused."
        } catch {
            beginRecordingElapsedTimer()
            beginMouseCapture()
            errorMessage = error.localizedDescription
        }
    }

    func cancelRecordingPreparation() {
        guard isPreparingRecording else { return }
        isPreparingRecording = false
        recordingCountdownRemaining = 0
        activeRecordingAudioLayout = nil
        statusMessage = "Recording cancelled."
        recordingWindowCoordinator.dismissAndRestoreEditor()
    }

    private func saveOriginalRecording(_ sourceURL: URL) throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "ScreenFree Recording.mp4"
        guard panel.runModal() == .OK, let destination = panel.url else {
            return nil
        }
        try originalRecordingDelivery.copy(
            sourceURL: sourceURL,
            destinationURL: destination
        )
        return destination
    }

    var formattedRecordingElapsed: String {
        let value = max(0, recordingElapsed)
        return String(
            format: "%02d:%02d",
            Int(value) / 60,
            Int(value).quotientAndRemainder(dividingBy: 60).remainder
        )
    }

    var localizedStatusMessage: String {
        func value(
            between prefix: String,
            and suffix: String = ""
        ) -> String? {
            guard statusMessage.hasPrefix(prefix),
                  suffix.isEmpty || statusMessage.hasSuffix(suffix) else {
                return nil
            }
            let start = statusMessage.index(
                statusMessage.startIndex,
                offsetBy: prefix.count
            )
            let end = suffix.isEmpty
                ? statusMessage.endIndex
                : statusMessage.index(
                    statusMessage.endIndex,
                    offsetBy: -suffix.count
                )
            return String(statusMessage[start..<end])
        }

        if statusMessage.hasPrefix("Recording starts in "),
           let value = statusMessage
            .split(separator: " ")
            .dropFirst(3)
            .first
            .flatMap({ Int($0.trimmingCharacters(in: .punctuationCharacters)) }) {
            return L10n.text(
                "Recording starts in %d…",
                language: appLanguage,
                value
            )
        }
        if let filename = value(between: "Added background music ") {
            return L10n.text(
                "Added background music %@",
                language: appLanguage,
                filename
            )
        }
        if let name = value(between: "Applied preset ") {
            return L10n.text(
                "Applied preset %@",
                language: appLanguage,
                localizedPresetName(name)
            )
        }
        if let name = value(between: "Imported preset ") {
            return L10n.text(
                "Imported preset %@",
                language: appLanguage,
                localizedPresetName(name)
            )
        }
        if let name = value(between: "Saved preset ") {
            return L10n.text(
                "Saved preset %@",
                language: appLanguage,
                localizedPresetName(name)
            )
        }
        if let filename = value(between: "Imported ") {
            return L10n.text("Imported %@", language: appLanguage, filename)
        }
        if let filename = value(between: "Opened ") {
            return L10n.text("Opened %@", language: appLanguage, filename)
        }
        if let filename = value(between: "Saved original recording ") {
            return L10n.text(
                "Saved original recording %@",
                language: appLanguage,
                filename
            )
        }
        if let filename = value(between: "Saved ") {
            return L10n.text("Saved %@", language: appLanguage, filename)
        }
        if let filename = value(between: "Exported ") {
            return L10n.text("Exported %@", language: appLanguage, filename)
        }
        if let timestamp = value(between: "Clip split at ", and: ".") {
            return L10n.text(
                "Clip split at %@.",
                language: appLanguage,
                timestamp
            )
        }
        if let percentage = value(
            between: "Audio normalized to ",
            and: "."
        ) {
            return L10n.text(
                "Audio normalized to %@.",
                language: appLanguage,
                percentage
            )
        }
        if let count = value(
            between: "Generated ",
            and: " caption segments."
        ).flatMap(Int.init) {
            return L10n.text(
                "Generated %d caption segments.",
                language: appLanguage,
                count
            )
        }
        if let count = value(
            between: "Generated ",
            and: " cursor-focused zooms."
        ).flatMap(Int.init) {
            return L10n.text(
                "Generated %d cursor-focused zooms.",
                language: appLanguage,
                count
            )
        }
        return L10n.text(statusMessage, language: appLanguage)
    }

    private func localizedPresetName(_ name: String) -> String {
        guard BuiltInStylePreset.allCases.contains(
            where: { $0.rawValue == name }
        ) else {
            return name
        }
        return L10n.text(name, language: appLanguage)
    }

    var localizedErrorMessage: String? {
        errorMessage.map { L10n.text($0, language: appLanguage) }
    }

    var localizedTimelineSummary: String {
        L10n.text(
            "%d clips · %d zooms",
            language: appLanguage,
            project.clips.count,
            project.zooms.count
        )
    }

    func importVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            do {
                try await loadVideo(url)
                appScreen = .editor
                statusMessage = "Imported \(url.lastPathComponent)"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshRecordingHistory() {
        recordingHistory = recordingHistoryCatalog.recordings()
    }

    func openRecordingFromHistory(_ item: RecordingHistoryItem) async {
        guard FileManager.default.fileExists(atPath: item.url.path) else {
            refreshRecordingHistory()
            errorMessage = "The selected recording could not be found."
            return
        }
        let wasRestoringProject = isRestoringProject
        isRestoringProject = true
        defer { isRestoringProject = wasRestoringProject }
        do {
            var recoveredArchiveWithoutSnapshot = false
            let sidecarURL = RecordingProjectSidecar.url(for: item.url)
            var snapshot = matchingSnapshot(
                at: sidecarURL,
                sourceURL: item.url
            )
            let recoveryCandidates = [
                RecordingProjectSidecar.backupURL(for: item.url),
                persistence.recoveryURL,
                persistence.previousRecoveryURL
            ].compactMap {
                matchingSnapshot(at: $0, sourceURL: item.url)
            }
            if snapshot == nil {
                snapshot = recoveryCandidates.first
            }
            if snapshot?.project.cursorSamples.isEmpty != false,
               let recoveredProject = recoveryCandidates
                    .map(\.project)
                    .max(by: {
                        $0.cursorSamples.count < $1.cursorSamples.count
                    }),
               !recoveredProject.cursorSamples.isEmpty {
                snapshot?.project.cursorSamples =
                    recoveredProject.cursorSamples
                snapshot?.project.clicks = recoveredProject.clicks
                snapshot?.project.shortcuts = recoveredProject.shortcuts
            }
            if let archive = try await RecordingInteractionMetadata.read(
                from: item.url
            ), !archive.isEmpty,
               snapshot?.project.cursorSamples.isEmpty != false {
                if snapshot == nil {
                    project = TimelineProject()
                    archive.applying(to: &project)
                    try await loadVideo(
                        item.url,
                        preservingCapturedMetadata: true
                    )
                    recoveredArchiveWithoutSnapshot = true
                } else {
                    var recoveredSnapshot = snapshot!
                    archive.applying(to: &recoveredSnapshot.project)
                    snapshot = recoveredSnapshot
                }
            }
            if let snapshot {
                try await restore(snapshot)
                try saveRecordingProjectSidecarIfNeeded()
            } else if recoveredArchiveWithoutSnapshot {
                try saveRecordingProjectSidecarIfNeeded()
            } else {
                try await loadVideo(item.url)
            }
            inspectorPanel = .clip
            appScreen = .editor
            statusMessage = "Recording opened for editing."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Permanently deletes recordings from disk and refreshes the history.
    func deleteRecordingsFromHistory(_ items: [RecordingHistoryItem]) {
        guard !items.isEmpty else { return }
        let deletedCurrentSource = items.contains {
            $0.url.standardizedFileURL == sourceURL?.standardizedFileURL
        }
        let deleted = recordingHistoryCatalog.delete(items)
        refreshRecordingHistory()
        guard deleted > 0 else {
            errorMessage = "The selected recordings could not be deleted."
            return
        }
        if deletedCurrentSource {
            statusMessage = "The open recording was deleted from disk."
        } else {
            statusMessage = "Deleted \(deleted) recording(s)."
        }
    }

    func importBackgroundMusic() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            do {
                try await loadBackgroundMusic(url)
                statusMessage = "Added background music \(url.lastPathComponent)"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func removeBackgroundMusic() {
        backgroundMusicPlayer.pause()
        backgroundMusicPlayer.replaceCurrentItem(with: nil)
        backgroundMusicURL = nil
        backgroundMusicDuration = 0
        statusMessage = "Background music removed."
    }

    func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backgroundImageURL = url
        backgroundMode = .image
    }

    func randomizeWallpaper() {
        let alternatives = WallpaperPreset.allCases.filter {
            $0 != wallpaperPreset
        }
        wallpaperPreset = alternatives.randomElement() ?? .aurora
        backgroundMode = .wallpaper
    }

    func applyBuiltInStylePreset(_ builtIn: BuiltInStylePreset) {
        applyStylePreset(builtIn.preset)
        statusMessage = "Applied preset \(builtIn.rawValue)"
    }

    func importStylePreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "screenfreepreset") ?? .json
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let preset = try stylePresetPersistence.load(from: url)
            applyStylePreset(preset)
            statusMessage = "Imported preset \(preset.name)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveStylePreset() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "screenfreepreset") ?? .json
        ]
        panel.nameFieldStringValue = "ScreenFree Style.screenfreepreset"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = url.deletingPathExtension().lastPathComponent
        do {
            try stylePresetPersistence.save(
                currentStylePreset(name: name),
                to: url
            )
            statusMessage = "Saved preset \(name)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func currentStylePreset(name: String) -> ScreenFreeStylePreset {
        ScreenFreeStylePreset(
            name: name,
            canvasAspectRatio: canvasAspectRatio,
            canvasContentMode: canvasContentMode,
            canvasPadding: canvasPadding,
            cornerRadius: cornerRadius,
            backgroundHue: backgroundHue,
            backgroundMode: backgroundMode,
            wallpaperPreset: wallpaperPreset,
            backgroundImagePath: backgroundImageURL?.path,
            backgroundBlur: backgroundBlur,
            shadowStrength: shadowStrength,
            cursorSize: cursorSize,
            cursorReplacement: cursorReplacement,
            showCursor: showCursor,
            hideCursorWhenIdle: hideCursorWhenIdle,
            cursorIdleTimeout: cursorIdleTimeout,
            cursorTailFreeze: cursorTailFreeze,
            cursorLoopToStart: cursorLoopToStart,
            removeCursorShakes: removeCursorShakes,
            cursorShakeThreshold: cursorShakeThreshold,
            optimizeRapidCursorChanges: optimizeRapidCursorChanges,
            smoothCursorMovement: smoothCursorMovement,
            clickEffectPreset: clickEffectPreset,
            showShortcutOverlay: showShortcutOverlay,
            showCaptions: showCaptions,
            captionFontSize: captionFontSize,
            zoomScale: zoomScale,
            zoomDuration: zoomDuration,
            zoomMotionPreset: zoomMotionPreset,
            zoomCustomTransitionDuration: zoomCustomTransitionDuration,
            zoomCustomX1: zoomCustomX1,
            zoomCustomY1: zoomCustomY1,
            zoomCustomX2: zoomCustomX2,
            zoomCustomY2: zoomCustomY2,
            motionBlurEnabled: motionBlurEnabled,
            motionBlurStrength: motionBlurStrength,
            cursorMotionBlur: cursorMotionBlur,
            zoomMotionBlur: zoomMotionBlur,
            panMotionBlur: panMotionBlur,
            cameraSize: cameraSize,
            cameraCornerRadius: cameraCornerRadius,
            cameraMirrored: cameraMirrored,
            cameraPosition: cameraPosition
        )
    }

    func applyStylePreset(_ preset: ScreenFreeStylePreset) {
        canvasAspectRatio = preset.canvasAspectRatio
        canvasContentMode = preset.canvasContentMode ?? .fit
        canvasPadding = preset.canvasPadding.clamped(to: 0...80)
        cornerRadius = preset.cornerRadius.clamped(to: 0...42)
        backgroundHue = preset.backgroundHue.clamped(to: 0...1)
        wallpaperPreset = preset.wallpaperPreset ?? .aurora
        backgroundBlur = preset.backgroundBlur.clamped(to: 0...40)
        shadowStrength = preset.shadowStrength.clamped(to: 0...1)
        if let path = preset.backgroundImagePath,
           FileManager.default.fileExists(atPath: path) {
            backgroundImageURL = URL(fileURLWithPath: path)
            backgroundMode = preset.backgroundMode
        } else {
            backgroundImageURL = nil
            backgroundMode = preset.backgroundMode == .image
                ? .gradient
                : preset.backgroundMode
        }
        cursorSize = preset.cursorSize.clamped(to: 0.6...2.5)
        cursorReplacement = preset.cursorReplacement ?? .arrow
        showCursor = preset.showCursor
        hideCursorWhenIdle = preset.hideCursorWhenIdle
        cursorIdleTimeout = preset.cursorIdleTimeout.clamped(to: 0.5...5)
        cursorTailFreeze = preset.cursorTailFreeze.clamped(to: 0...5)
        cursorLoopToStart = preset.cursorLoopToStart ?? false
        removeCursorShakes = preset.removeCursorShakes ?? false
        cursorShakeThreshold = (preset.cursorShakeThreshold ?? 0.012)
            .clamped(to: 0.002...0.08)
        optimizeRapidCursorChanges =
            preset.optimizeRapidCursorChanges ?? false
        smoothCursorMovement = preset.smoothCursorMovement ?? false
        clickEffectPreset = preset.clickEffectPreset
        showShortcutOverlay = preset.showShortcutOverlay
        showCaptions = preset.showCaptions
        captionFontSize = preset.captionFontSize.clamped(to: 18...60)
        zoomScale = preset.zoomScale.clamped(to: 1.1...3)
        zoomDuration = preset.zoomDuration.clamped(to: 0.1...10)
        zoomMotionPreset = preset.zoomMotionPreset
        zoomCustomTransitionDuration =
            (preset.zoomCustomTransitionDuration ?? 0.82)
            .clamped(to: 0.08...1.5)
        zoomCustomX1 = (preset.zoomCustomX1 ?? 0.25).clamped(to: 0...1)
        zoomCustomY1 = (preset.zoomCustomY1 ?? 0.1).clamped(to: 0...1)
        zoomCustomX2 = (preset.zoomCustomX2 ?? 0.25).clamped(to: 0...1)
        zoomCustomY2 = (preset.zoomCustomY2 ?? 1).clamped(to: 0...1)
        motionBlurEnabled = preset.motionBlurEnabled ?? false
        motionBlurStrength = (preset.motionBlurStrength ?? 0.42)
            .clamped(to: 0...1)
        cursorMotionBlur = (preset.cursorMotionBlur ?? 0.58)
            .clamped(to: 0...1)
        zoomMotionBlur = (preset.zoomMotionBlur ?? 0.45)
            .clamped(to: 0...1)
        panMotionBlur = (preset.panMotionBlur ?? 0.34)
            .clamped(to: 0...1)
        cameraSize = preset.cameraSize.clamped(to: 0.12...0.5)
        cameraCornerRadius = preset.cameraCornerRadius.clamped(to: 0...42)
        cameraMirrored = preset.cameraMirrored
        cameraPosition = preset.cameraPosition
    }

    func selectRecordingArea() {
        areaSelectionCoordinator.present(
            onDisplayID: selectedTargetID,
            initialSelection: selectedAreaNormalized
        ) { [weak self] selection in
            self?.selectedAreaNormalized = selection
            self?.statusMessage = "Recording area updated."
        }
    }

    func refreshRecordingHighlight() {
        recordingWindowCoordinator.updateHighlight(
            frame: recorder.sourceFrame,
            visible: highlightRecordingArea
                && (isPreparingRecording || isRecording)
        )
    }

    func refreshRecordingDrawing() {
        recordingWindowCoordinator.updateDrawingOverlay(
            frame: recorder.sourceFrame,
            visible: isPreparingRecording || isRecording
        )
    }

    var scriptHasText: Bool {
        !scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func resetTeleprompterPosition() {
        recordingWindowCoordinator.resetTeleprompterPosition()
    }

    /// 录制设置页入口：从首页或编辑器工具栏进入，开录前完成全部配置。
    /// 每次进入都按"上一次真正使用的配置"还原默认值；口播稿除外——
    /// 新录制默认空稿，复用走最近稿子列表（见 ADR 0002）。
    func presentRecordingSetup() {
        guard !isRecording, !isPreparingRecording else { return }
        applyLastRecordingSetup()
        if appScreen != .recordingSetup {
            screenBeforeSetup = appScreen
        }
        appScreen = .recordingSetup
    }

    func dismissRecordingSetup() {
        guard appScreen == .recordingSetup else { return }
        appScreen = screenBeforeSetup
    }

    private func applyLastRecordingSetup() {
        guard let setup = LastRecordingSetupStore().load() else { return }
        captureMode = setup.captureMode
        selectedTargetID = setup.selectedTargetID
        selectedAreaNormalized = setup.selectedAreaNormalized
        systemAudioMode = setup.systemAudioMode
        selectedAudioApplicationIDs = setup.selectedAudioApplicationIDs
        recordMicrophone = setup.recordMicrophone
        if let microphoneID = setup.selectedMicrophoneID {
            selectedMicrophoneID = microphoneID
        }
        selectedCameraID = setup.selectedCameraID
        countdownSeconds = setup.countdownSeconds
        highlightRecordingArea = setup.highlightRecordingArea
    }

    private func persistLastRecordingSetup() {
        LastRecordingSetupStore().save(
            LastRecordingSetup(
                captureMode: captureMode,
                selectedTargetID: selectedTargetID,
                selectedAreaNormalized: selectedAreaNormalized,
                systemAudioMode: systemAudioMode,
                selectedAudioApplicationIDs: selectedAudioApplicationIDs,
                recordMicrophone: recordMicrophone,
                selectedMicrophoneID: selectedMicrophoneID,
                selectedCameraID: selectedCameraID,
                countdownSeconds: countdownSeconds,
                highlightRecordingArea: highlightRecordingArea
            )
        )
    }

    private func recordRecentScriptIfNeeded() {
        guard
            !scriptText.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        else { return }
        recentScripts = RecentScriptsStore().record(
            title: RecentScriptsStore.title(for: scriptText),
            text: scriptText
        )
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "screenfree") ?? .json
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let snapshot = try persistence.load(from: url)
                try await restore(snapshot)
                appScreen = .editor
                statusMessage = "Opened \(url.lastPathComponent)"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func openExternalURL(_ url: URL) async {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            if url.pathExtension.lowercased() == "screenfree" {
                try await restore(persistence.load(from: url))
                appScreen = .editor
                statusMessage = "Opened \(url.lastPathComponent)"
            } else {
                try await loadVideo(url)
                appScreen = .editor
                inspectorPanel = .clip
                statusMessage = "Imported \(url.lastPathComponent)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveProject() {
        guard let snapshot = makeSnapshot() else {
            statusMessage = "Record or import a video before saving a project."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "screenfree") ?? .json
        ]
        panel.nameFieldStringValue = "Untitled.screenfree"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try persistence.save(snapshot, to: url)
            statusMessage = "Saved \(url.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveOriginalScreenMedia() {
        guard let sourceURL else { return }
        saveOriginalVideoMedia(
            sourceURL,
            suggestedBaseName: "Original Screen"
        )
    }

    func saveOriginalCameraMedia() {
        guard let cameraURL else { return }
        saveOriginalVideoMedia(
            cameraURL,
            suggestedBaseName: "Original Camera"
        )
    }

    func saveOriginalSystemAudio() {
        guard let trackIndex = recordedAudioLayout?.systemTrackIndex else {
            errorMessage =
                OriginalMediaExportError.missingAudioTrack.localizedDescription
            return
        }
        saveOriginalAudioMedia(
            trackIndex: trackIndex,
            suggestedName: "Original System Audio.m4a"
        )
    }

    func saveOriginalMicrophoneAudio() {
        guard let trackIndex = recordedAudioLayout?.microphoneTrackIndex else {
            errorMessage =
                OriginalMediaExportError.missingAudioTrack.localizedDescription
            return
        }
        saveOriginalAudioMedia(
            trackIndex: trackIndex,
            suggestedName: "Original Microphone.m4a"
        )
    }

    private func saveOriginalVideoMedia(
        _ mediaURL: URL,
        suggestedBaseName: String
    ) {
        let fileExtension = mediaURL.pathExtension.isEmpty
            ? "mp4"
            : mediaURL.pathExtension
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: fileExtension) ?? .movie
        ]
        panel.nameFieldStringValue =
            "\(suggestedBaseName).\(fileExtension)"
        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }
        do {
            try originalRecordingDelivery.copy(
                sourceURL: mediaURL,
                destinationURL: destination
            )
            statusMessage = "Saved \(destination.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveOriginalAudioMedia(
        trackIndex: Int,
        suggestedName: String
    ) {
        guard let sourceURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }
        isExporting = true
        isVideoExporting = false
        statusMessage = "Extracting original audio…"
        Task {
            defer { isExporting = false }
            do {
                try await originalMediaExporter.extractAudio(
                    sourceURL: sourceURL,
                    trackIndex: trackIndex,
                    destinationURL: destination
                )
                statusMessage = "Saved \(destination.lastPathComponent)"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
        statusMessage = "Enable ScreenFree in Screen & System Audio Recording, then relaunch."
    }

    func openMicrophoneSettings() {
        openPrivacySettings(anchor: "Privacy_Microphone")
    }

    func openCameraSettings() {
        openPrivacySettings(anchor: "Privacy_Camera")
    }

    func requestInputMonitoringPermission() {
        inputMonitoringGranted = CGRequestListenEventAccess()
        if inputMonitoringGranted {
            statusMessage =
                "Input Monitoring enabled for long-right-hold zooms."
        } else {
            openPrivacySettings(anchor: "Privacy_ListenEvent")
            statusMessage =
                "Enable ScreenFree in Input Monitoring for long-right-hold zooms."
        }
    }

    func requestScreenRecordingPermission() async {
        statusMessage = "Requesting screen recording permission…"
        if CGRequestScreenCaptureAccess() {
            capturePermissionIssue = false
            await refreshCaptureTargets()
            statusMessage = "Permission granted. Choose a source and record."
        } else {
            capturePermissionIssue = true
            statusMessage = "Permission was not granted. Enable ScreenFree in System Settings."
            openScreenRecordingSettings()
        }
    }

    func loadVideo(
        _ url: URL,
        preservingCapturedMetadata: Bool = false
    ) async throws {
        let embeddedInteractions = preservingCapturedMetadata
            ? nil
            : try await RecordingInteractionMetadata.read(from: url)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw VideoExportError.missingVideoTrack
        }

        sourceURL = url
        sourceDuration = duration
        if let videoTrack = try await asset.loadTracks(
            withMediaType: .video
        ).first {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(
                .preferredTransform
            )
            let transformed = CGRect(
                origin: .zero,
                size: naturalSize
            )
            .applying(preferredTransform)
            let width = abs(transformed.width)
            let height = abs(transformed.height)
            if width > 0, height > 0 {
                sourceAspectRatio = width / height
                sourcePixelSize = CGSize(width: width, height: height)
            }
            let nominalFrameRate = try await videoTrack.load(
                .nominalFrameRate
            )
            if nominalFrameRate.isFinite, nominalFrameRate > 0 {
                sourceFrameRate = Double(nominalFrameRate)
            }
        }
        if !url.path.contains("/Movies/ScreenFree/Recording-") {
            cameraURL = nil
            cameraPlayer.replaceCurrentItem(with: nil)
        }
        if !isRestoringProject {
            backgroundMusicPlayer.pause()
            backgroundMusicPlayer.replaceCurrentItem(with: nil)
            backgroundMusicURL = nil
            backgroundMusicDuration = 0
            recordedAudioLayout = nil
            systemAudioVolume = 1
            microphoneAudioVolume = 1
            microphoneAudioMuted = false
        }
        let existingCursor: [CursorSample]
        let existingClicks: [MouseClick]
        let existingShortcuts: [ShortcutEvent]
        let existingAnnotations: [Annotation]
        if preservingCapturedMetadata {
            existingCursor = project.cursorSamples
            existingClicks = project.clicks
            existingShortcuts = project.shortcuts
            existingAnnotations = project.annotations
        } else if let embeddedInteractions {
            existingCursor = embeddedInteractions.cursorSamples
            existingClicks = embeddedInteractions.clicks
            existingShortcuts = embeddedInteractions.shortcuts
            existingAnnotations = embeddedInteractions.annotations
        } else {
            existingCursor = []
            existingClicks = []
            existingShortcuts = []
            existingAnnotations = []
        }
        project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: duration)],
            cursorSamples: existingCursor,
            clicks: existingClicks,
            shortcuts: existingShortcuts,
            annotations: existingAnnotations
        )
        if preservingCapturedMetadata || embeddedInteractions?.isEmpty == false {
            // This checkpoint happens before thumbnail/audio analysis, which
            // can take minutes for a long recording. Quitting during analysis
            // must not lose the freshly captured cursor path.
            try saveRecordingProjectSidecarIfNeeded()
        }
        clearTimelineHistory()
        selectedClipID = project.clips.first?.id
        selectedZoomID = nil
        selectedRedactionID = nil
        selectedTransitionID = nil
        activeTimelineTool = .selection
        playhead = 0
        audioAnalysis = .empty
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        startTimelineThumbnailGeneration(for: url, duration: duration)
        refreshSourceAudioMix()
        await player.seek(to: .zero)
        isAnalyzingAudio = true
        audioAnalysis = (try? await audioAnalyzer.analyze(url: url)) ?? .empty
        refreshSourceAudioMix()
        isAnalyzingAudio = false
    }

    private func startTimelineThumbnailGeneration(
        for url: URL,
        duration: TimeInterval
    ) {
        timelineThumbnailTask?.cancel()
        timelineThumbnails = []
        let generation = UUID()
        timelineThumbnailGeneration = generation
        timelineThumbnailTask = Task { [weak self] in
            guard let self else { return }
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 192, height: 108)
            generator.requestedTimeToleranceBefore = CMTime(
                seconds: 0.2,
                preferredTimescale: 600
            )
            generator.requestedTimeToleranceAfter = CMTime(
                seconds: 0.2,
                preferredTimescale: 600
            )

            let targetSpacing: TimeInterval = 1.25
            let frameCount = min(
                180,
                max(12, Int(ceil(duration / targetSpacing)))
            )
            var frames: [TimelineThumbnailFrame] = []
            frames.reserveCapacity(frameCount)

            for index in 0..<frameCount {
                guard !Task.isCancelled,
                      self.timelineThumbnailGeneration == generation,
                      self.sourceURL == url else {
                    return
                }
                let sourceTime = duration
                    * (Double(index) + 0.5)
                    / Double(frameCount)
                let requestedTime = CMTime(
                    seconds: sourceTime,
                    preferredTimescale: 600
                )
                guard let result = try? await generator.image(
                    at: requestedTime
                ) else {
                    continue
                }
                frames.append(
                    TimelineThumbnailFrame(
                        id: index,
                        sourceTime: result.actualTime.seconds,
                        image: NSImage(
                            cgImage: result.image,
                            size: .zero
                        )
                    )
                )
                if frames.count.isMultiple(of: 8)
                    || index == frameCount - 1 {
                    self.timelineThumbnails = frames
                }
            }
        }
    }

    func togglePlayback() {
        if isPlaying {
            pausePreviewPlayback()
        } else {
            if playhead >= project.duration - 0.05 {
                seek(to: 0)
            }
            guard let context = clipContext(atTimelineTime: playhead) else {
                return
            }
            player.volume = 1
            player.playImmediately(atRate: Float(context.clip.playbackRate))
            if cameraURL != nil {
                cameraPlayer.playImmediately(atRate: Float(context.clip.playbackRate))
            }
            seekBackgroundMusic(to: playhead, force: true)
            backgroundMusicPlayer.playImmediately(atRate: 1)
            isPlaying = true
        }
    }

    private func pausePreviewPlayback() {
        player.pause()
        cameraPlayer.pause()
        backgroundMusicPlayer.pause()
        isPlaying = false
    }

    @discardableResult
    func handlePlaybackKey() -> Bool {
        guard sourceURL != nil,
              project.duration > 0,
              !isRecording,
              !isPreparingRecording else {
            return false
        }
        togglePlayback()
        return true
    }

    /// Relative jump (e.g. ⇧← / ⇧→ = ±1 s) that keeps the play/pause state.
    func skip(by seconds: TimeInterval) {
        guard sourceURL != nil, project.duration > 0 else { return }
        seek(to: playhead + seconds)
    }

    func stepFrame(_ direction: Int) {
        player.pause()
        cameraPlayer.pause()
        backgroundMusicPlayer.pause()
        isPlaying = false
        let frameDuration = 1 / sourceFrameRate.clamped(to: 15...120)
        seek(to: playhead + Double(direction.signum()) * frameDuration)
    }

    func zoomTimeline(by factor: Double) {
        setTimelineZoom(timelineZoom * factor)
    }

    func setTimelineZoom(_ zoom: Double) {
        timelineZoom = TimelineScale(zoom: zoom).zoom
    }

    func fitTimeline() {
        timelineZoom = TimelineScale.fitZoom
    }

    func seek(to time: TimeInterval) {
        let clamped = time.clamped(to: 0...max(0, project.duration))
        playhead = clamped
        guard let context = clipContext(atTimelineTime: clamped) else {
            return
        }
        let localTimeline = clamped - context.timelineStart
        let sourceTime = context.clip.sourceStart
            + localTimeline * context.clip.playbackRate
        player.volume = 1
        player.seek(
            to: CMTime(seconds: sourceTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        if cameraURL != nil {
            cameraPlayer.seek(
                to: CMTime(seconds: sourceTime, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
        seekBackgroundMusic(to: clamped, force: true)
        if isPlaying {
            player.playImmediately(atRate: Float(context.clip.playbackRate))
            cameraPlayer.playImmediately(atRate: Float(context.clip.playbackRate))
            backgroundMusicPlayer.playImmediately(atRate: 1)
        }
    }

    func seekAndPlay(to time: TimeInterval) {
        guard sourceURL != nil, project.duration > 0 else { return }
        let lastPlayableTime = max(0, project.duration - 1 / 120)
        isPlaying = true
        seek(to: min(time, lastPlayableTime))
    }

    /// Positions the playhead for an interactive timeline drag. Playback
    /// pauses so the periodic time observer cannot fight the drag, and it
    /// resumes on release when the drag interrupted playback. The line
    /// itself tracks the pointer on every event, while the underlying player
    /// seeks are deduplicated, throttled, and relaxed-tolerance — the preview
    /// frame catches up without decode churn at pointer-event rate.
    func scrub(to time: TimeInterval) {
        if !isScrubbing {
            isScrubbing = true
            wasPlayingBeforeScrub = isPlaying
        }
        if isPlaying {
            pausePreviewPlayback()
        }
        let clamped = time.clamped(to: 0...max(0, project.duration))
        if abs(clamped - playhead) <= 0.0005,
           lastScrubSeekTarget == clamped {
            // The line is already there and a seek to that exact time has
            // been dispatched — covers the two timeline drag gestures
            // double-firing each pointer event.
            return
        }
        playhead = clamped
        pendingScrubTime = clamped
        dispatchDueScrubSeek()
    }

    /// Finishes a drag at the pointer's release position with an exact seek
    /// so the paused frame matches what preview rendering and export produce.
    /// The seek bypasses the drag throttle: release always lands exactly.
    /// A drag that interrupted playback resumes playing from the release
    /// position, so scrubbing mid-playback never strands the user paused.
    func endScrub(at time: TimeInterval? = nil) {
        let target = (time ?? playhead).clamped(
            to: 0...max(0, project.duration)
        )
        pendingScrubTime = nil
        lastScrubSeekDispatchAt = nil
        lastScrubSeekTarget = target
        let shouldResume = isScrubbing && wasPlayingBeforeScrub
        isScrubbing = false
        wasPlayingBeforeScrub = false
        if shouldResume {
            seekAndPlay(to: target)
        } else {
            seek(to: target)
        }
    }

    private func dispatchDueScrubSeek() {
        guard let target = pendingScrubTime, !isScrubSeekInFlight else {
            return
        }
        let now = DispatchTime.now().uptimeNanoseconds
        if let last = lastScrubSeekDispatchAt,
           Double(now - last) / 1_000_000_000 < scrubSeekInterval {
            return
        }
        pendingScrubTime = nil
        lastScrubSeekDispatchAt = now
        lastScrubSeekTarget = target
        performScrubSeek(to: target)
    }

    private func performScrubSeek(to timelineTime: TimeInterval) {
        guard let context = clipContext(atTimelineTime: timelineTime) else {
            return
        }
        let localTimeline = timelineTime - context.timelineStart
        let sourceTime = context.clip.sourceStart
            + localTimeline * context.clip.playbackRate
        let cmTime = CMTime(seconds: sourceTime, preferredTimescale: 600)
        // Half a frame of tolerance lets the decoder land on a nearby frame
        // instead of decoding from the previous keyframe on every drag tick.
        let tolerance = CMTime(
            seconds: 0.5 / sourceFrameRate.clamped(to: 15...120),
            preferredTimescale: 600
        )
        isScrubSeekInFlight = true
        player.volume = 1
        player.seek(
            to: cmTime,
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isScrubSeekInFlight = false
                self.dispatchDueScrubSeek()
            }
        }
        if cameraURL != nil {
            cameraPlayer.seek(
                to: cmTime,
                toleranceBefore: tolerance,
                toleranceAfter: tolerance
            )
        }
        seekBackgroundMusic(to: timelineTime, force: false)
    }

    func toggleSplitTool() {
        activeTimelineTool = activeTimelineTool == .split
            ? .selection
            : .split
        statusMessage = activeTimelineTool == .split
            ? "Split tool active — click anywhere on a video or zoom block; press Esc to exit."
            : "Split tool closed."
    }

    func cancelTimelineTool() {
        guard activeTimelineTool != .selection else { return }
        activeTimelineTool = .selection
        statusMessage = "Editing tool closed."
    }

    @discardableResult
    func handleEscape() -> Bool {
        if selectedZoomIDs.count > 1 {
            clearZoomMultiSelection()
            return true
        }
        guard activeTimelineTool != .selection else { return false }
        cancelTimelineTool()
        return true
    }

    var canUndoTimelineEdit: Bool {
        timelineUndoTitle != nil
    }

    var canRedoTimelineEdit: Bool {
        timelineRedoTitle != nil
    }

    func beginContinuousTimelineEdit(_ kind: TimelineContinuousEditKind) {
        if activeTimelineContinuousEdit?.kind == kind {
            return
        }
        endContinuousTimelineEdit()
        activeTimelineContinuousEdit = ActiveTimelineContinuousEdit(
            kind: kind,
            snapshot: captureTimelineSnapshot()
        )
    }

    func endContinuousTimelineEdit() {
        guard let edit = activeTimelineContinuousEdit else { return }
        activeTimelineContinuousEdit = nil
        guard edit.hasChanges else { return }
        registerTimelineEdit(
            edit.kind.actionName,
            before: edit.snapshot
        )
    }

    func undoTimelineEdit() {
        endContinuousTimelineEdit()
        guard let entry = timelineUndoStack.popLast() else { return }
        timelineRedoStack.append(
            TimelineHistoryEntry(
                actionName: entry.actionName,
                snapshot: captureTimelineSnapshot()
            )
        )
        restoreTimelineSnapshot(entry.snapshot)
        updateTimelineHistoryTitles()
        statusMessage = "Undid \(entry.actionName.lowercased())."
    }

    func redoTimelineEdit() {
        endContinuousTimelineEdit()
        guard let entry = timelineRedoStack.popLast() else { return }
        timelineUndoStack.append(
            TimelineHistoryEntry(
                actionName: entry.actionName,
                snapshot: captureTimelineSnapshot()
            )
        )
        restoreTimelineSnapshot(entry.snapshot)
        updateTimelineHistoryTitles()
        statusMessage = "Redid \(entry.actionName.lowercased())."
    }

    func clearTimelineHistory() {
        activeTimelineContinuousEdit = nil
        timelineUndoStack.removeAll(keepingCapacity: true)
        timelineRedoStack.removeAll(keepingCapacity: true)
        updateTimelineHistoryTitles()
    }

    private func captureTimelineSnapshot() -> TimelineEditorSnapshot {
        TimelineEditorSnapshot(
            project: project,
            selectedClipID: selectedClipID,
            selectedZoomID: selectedZoomID,
            selectedRedactionID: selectedRedactionID,
            hoveredTimelineBlock: hoveredTimelineBlock,
            inspectorPanel: inspectorPanel,
            activeTimelineTool: activeTimelineTool,
            playhead: playhead
        )
    }

    private func registerTimelineEdit(
        _ actionName: String,
        before snapshot: TimelineEditorSnapshot
    ) {
        var registeredEdit = false
        if let pendingEdit = activeTimelineContinuousEdit {
            activeTimelineContinuousEdit = nil
            if pendingEdit.hasChanges,
               pendingEdit.snapshot.project != snapshot.project {
                appendTimelineHistory(
                    pendingEdit.kind.actionName,
                    snapshot: pendingEdit.snapshot
                )
                registeredEdit = true
            }
        }
        if snapshot.project != project {
            appendTimelineHistory(actionName, snapshot: snapshot)
            registeredEdit = true
        }
        guard registeredEdit else { return }
        timelineRedoStack.removeAll(keepingCapacity: true)
        updateTimelineHistoryTitles()
    }

    private func appendTimelineHistory(
        _ actionName: String,
        snapshot: TimelineEditorSnapshot
    ) {
        timelineUndoStack.append(
            TimelineHistoryEntry(
                actionName: actionName,
                snapshot: snapshot
            )
        )
        if timelineUndoStack.count > 100 {
            timelineUndoStack.removeFirst(
                timelineUndoStack.count - 100
            )
        }
    }

    private func registerTimelineMutation(
        _ kind: TimelineContinuousEditKind,
        before snapshot: TimelineEditorSnapshot
    ) {
        guard snapshot.project != project else { return }
        guard var edit = activeTimelineContinuousEdit else {
            registerTimelineEdit(kind.actionName, before: snapshot)
            return
        }
        guard edit.kind == kind else {
            registerTimelineEdit(kind.actionName, before: snapshot)
            return
        }
        edit.hasChanges = true
        activeTimelineContinuousEdit = edit
        if !timelineRedoStack.isEmpty {
            timelineRedoStack.removeAll(keepingCapacity: true)
            updateTimelineHistoryTitles()
        }
    }

    private func prepareTimelineMutation(
        _ kind: TimelineContinuousEditKind
    ) {
        if let edit = activeTimelineContinuousEdit,
           edit.kind != kind {
            endContinuousTimelineEdit()
        }
    }

    private func restoreTimelineSnapshot(
        _ snapshot: TimelineEditorSnapshot
    ) {
        project = snapshot.project
        selectedClipID = snapshot.selectedClipID
        selectedZoomID = snapshot.selectedZoomID
        selectedRedactionID = snapshot.selectedRedactionID
        // Undo/redo can remove or restore zooms; keep the multi-selection
        // limited to blocks that actually exist afterwards.
        let zoomIDs = Set(snapshot.project.zooms.map(\.id))
        selectedZoomIDs = selectedZoomIDs.intersection(zoomIDs)
        hoveredTimelineBlock = snapshot.hoveredTimelineBlock.flatMap {
            timelineContains($0)
                ? $0
                : nil
        }
        inspectorPanel = snapshot.inspectorPanel
        activeTimelineTool = snapshot.activeTimelineTool
        refreshSourceAudioMix()
        seek(to: snapshot.playhead)
    }

    private func timelineContains(_ target: TimelineBlockTarget) -> Bool {
        switch target {
        case let .clip(id):
            return project.clips.contains { $0.id == id }
        case let .zoom(id):
            return project.zooms.contains { $0.id == id }
        case let .redaction(id):
            return project.redactions.contains { $0.id == id }
        }
    }

    private func updateTimelineHistoryTitles() {
        timelineUndoTitle = timelineUndoStack.last.map {
            "Undo \($0.actionName)"
        }
        timelineRedoTitle = timelineRedoStack.last.map {
            "Redo \($0.actionName)"
        }
    }

    func setHoveredTimelineBlock(
        _ block: TimelineBlockTarget,
        hovering: Bool
    ) {
        if hovering {
            hoveredTimelineBlock = block
            if timelineContains(block) {
                selectTimelineBlock(block)
            }
        } else if hoveredTimelineBlock == block {
            hoveredTimelineBlock = nil
        }
    }

    private func selectTimelineBlock(_ block: TimelineBlockTarget) {
        switch block {
        case let .clip(id):
            selectedClipID = id
            inspectorPanel = .clip
        case let .zoom(id):
            selectedZoomID = id
            // Hovering must not destroy an explicit multi-selection.
            if selectedZoomIDs.count <= 1 {
                selectedZoomIDs = [id]
            }
            inspectorPanel = .zoom
        case let .redaction(id):
            selectedRedactionID = id
            inspectorPanel = .privacy
        }
    }

    func setHoveredClip(atTimelineTime time: TimeInterval?) {
        guard let time,
              let clipID = project.clipID(atTimelineTime: time) else {
            if case .clip = hoveredTimelineBlock {
                hoveredTimelineBlock = nil
            }
            return
        }
        setHoveredTimelineBlock(.clip(clipID), hovering: true)
    }

    @discardableResult
    func handleDeleteKey() -> Bool {
        guard let target = hoveredTimelineBlock ?? selectedTimelineBlock else {
            return false
        }
        deleteTimelineBlock(target)
        return true
    }

    private var selectedTimelineBlock: TimelineBlockTarget? {
        switch inspectorPanel {
        case .clip:
            return selectedClipID.map(TimelineBlockTarget.clip)
        case .zoom:
            return selectedZoomID.map(TimelineBlockTarget.zoom)
        case .privacy:
            return selectedRedactionID.map(TimelineBlockTarget.redaction)
        default:
            return nil
        }
    }

    func split(at timelineTime: TimeInterval) {
        let safeTime = timelineTime.clamped(to: 0...project.duration)
        let snapshot = captureTimelineSnapshot()
        guard let clipID = project.clipID(atTimelineTime: safeTime),
              project.split(clipID: clipID, atTimelineTime: safeTime) else {
            statusMessage = "Click farther inside a clip to split it."
            return
        }
        seek(to: safeTime)
        selectedClipID = project.clipID(atTimelineTime: safeTime + 0.01)
        registerTimelineEdit("Split Clip", before: snapshot)
        statusMessage = "Clip split at \(formatted(safeTime))."
    }

    func splitAtPlayhead() {
        split(at: playhead)
    }

    func deleteSelectedClip() {
        guard let selectedClipID else {
            statusMessage = "Select a clip to delete it."
            return
        }
        _ = deleteClip(id: selectedClipID)
    }

    @discardableResult
    func deleteClip(id: UUID) -> Bool {
        deleteClip(
            id: id,
            historySnapshot: captureTimelineSnapshot()
        )
    }

    @discardableResult
    private func deleteClip(
        id: UUID,
        historySnapshot snapshot: TimelineEditorSnapshot
    ) -> Bool {
        guard project.clips.count > 1,
              let index = project.clips.firstIndex(where: { $0.id == id }) else {
            statusMessage = "Split the recording first; the final clip cannot be deleted."
            return false
        }
        project.clips.remove(at: index)
        if hoveredTimelineBlock == .clip(id) {
            hoveredTimelineBlock = nil
        }
        self.selectedClipID = project.clips.indices.contains(index)
            ? project.clips[index].id
            : project.clips.last?.id
        project.clampTimedEventsToDuration()
        seek(to: min(playhead, project.duration))
        registerTimelineEdit("Delete Clip", before: snapshot)
        statusMessage = "Clip removed from the timeline."
        return true
    }

    func deleteCurrentSelection() {
        if let hoveredTimelineBlock {
            deleteTimelineBlock(hoveredTimelineBlock)
            return
        }
        switch inspectorPanel {
        case .zoom:
            guard selectedZoomID != nil else { return }
            deleteSelectedZoom()
            statusMessage = "Zoom removed."
        case .privacy:
            guard selectedRedactionID != nil else { return }
            deleteSelectedRedaction()
        case .clip:
            guard selectedClipID != nil else { return }
            deleteSelectedClip()
        default:
            statusMessage =
                "Select a clip, zoom, privacy block, or annotation to delete it."
        }
    }

    private func deleteTimelineBlock(_ block: TimelineBlockTarget) {
        let snapshot = captureTimelineSnapshot()
        switch block {
        case let .clip(id):
            _ = deleteClip(id: id, historySnapshot: snapshot)
        case let .zoom(id):
            inspectorPanel = .zoom
            deleteZoom(id: id)
            statusMessage = "Zoom removed."
        case let .redaction(id):
            selectedRedactionID = id
            inspectorPanel = .privacy
            deleteSelectedRedaction()
        }
        hoveredTimelineBlock = nil
    }

    func selectCanvasAspectRatio(_ ratio: CanvasAspectRatio) {
        canvasAspectRatio = ratio
        guard ratio != .source else {
            statusMessage = "Canvas follows the recording dimensions."
            return
        }
        canvasContentMode = .crop
        canvasPadding = 0
        cornerRadius = 0
        shadowStrength = 0
        statusMessage =
            "\(ratio.displayTitle) fills the complete canvas edge to edge."
    }

    func mergeSelectedClip(withNext: Bool) {
        guard let selectedClipID else { return }
        let snapshot = captureTimelineSnapshot()
        guard
              let mergedID = project.merge(
                  clipID: selectedClipID,
                  withNext: withNext
              ) else {
            statusMessage = "Only contiguous clips with matching speed and volume can be merged."
            return
        }
        self.selectedClipID = mergedID
        seek(to: min(playhead, project.duration))
        registerTimelineEdit("Merge Clips", before: snapshot)
        statusMessage = withNext
            ? "Merged with the next clip."
            : "Merged with the previous clip."
    }

    func trimSelected(start: Bool) {
        guard let selectedClipID else { return }
        let snapshot = captureTimelineSnapshot()
        let changed = start
            ? project.trimStart(clipID: selectedClipID, by: 0.25)
            : project.trimEnd(clipID: selectedClipID, by: 0.25)
        if changed {
            project.clampTimedEventsToDuration()
            seek(to: min(playhead, project.duration))
            registerTimelineEdit("Trim Clip", before: snapshot)
            statusMessage = start ? "Trimmed 0.25s from clip start." : "Trimmed 0.25s from clip end."
        }
    }

    var canTrimLeftAtPlayhead: Bool {
        guard let context = clipContext(atTimelineTime: playhead) else {
            return false
        }
        return playhead - context.timelineStart > 0.05
    }

    var canTrimRightAtPlayhead: Bool {
        guard let context = clipContext(atTimelineTime: playhead) else {
            return false
        }
        return context.timelineStart + context.clip.timelineDuration
            - playhead > 0.05
    }

    /// CapCut-style one-click edge edit. Removing the left side advances the
    /// source start to the playhead; removing the right side pulls the source
    /// end back to the playhead.
    func trimAtPlayhead(removingLeft: Bool) {
        endContinuousTimelineEdit()
        guard let context = clipContext(atTimelineTime: playhead) else {
            return
        }
        let elapsedTimelineTime = (
            playhead - context.timelineStart
        ).clamped(to: 0...context.clip.timelineDuration)
        let sourceTime = context.clip.sourceStart
            + elapsedTimelineTime * context.clip.playbackRate
        let snapshot = captureTimelineSnapshot()
        let changed = removingLeft
            ? project.setClipSourceStart(
                clipID: context.clip.id,
                to: sourceTime,
                sourceDuration: sourceDuration
            )
            : project.setClipSourceEnd(
                clipID: context.clip.id,
                to: sourceTime,
                sourceDuration: sourceDuration
            )
        guard changed else {
            statusMessage = "Move the playhead farther inside the clip."
            return
        }
        selectedClipID = context.clip.id
        project.clampTimedEventsToDuration()
        let newPlayhead = removingLeft
            ? context.timelineStart
            : min(playhead, project.duration)
        seek(to: newPlayhead)
        registerTimelineEdit(
            removingLeft ? "Trim Clip Left" : "Trim Clip Right",
            before: snapshot
        )
        statusMessage = removingLeft
            ? "Trimmed everything left of the playhead."
            : "Trimmed everything right of the playhead."
    }

    /// Updates one clip edge during a direct-manipulation timeline drag.
    /// `beginContinuousTimelineEdit(.clip)` / `endContinuousTimelineEdit()`
    /// group the entire gesture into a single undo operation.
    func setClipTrimEdge(
        clipID: UUID,
        isLeading: Bool,
        sourceTime: TimeInterval
    ) {
        guard project.clips.contains(where: { $0.id == clipID }) else {
            return
        }
        selectedClipID = clipID
        prepareTimelineMutation(.clip)
        let snapshot = captureTimelineSnapshot()
        let changed = isLeading
            ? project.setClipSourceStart(
                clipID: clipID,
                to: sourceTime,
                sourceDuration: sourceDuration
            )
            : project.setClipSourceEnd(
                clipID: clipID,
                to: sourceTime,
                sourceDuration: sourceDuration
            )
        guard changed else { return }
        project.clampTimedEventsToDuration()
        seek(to: min(playhead, project.duration))
        registerTimelineMutation(.clip, before: snapshot)
    }

    /// Current transition visual state for the preview, resolved through the
    /// same logic the export pipeline samples.
    func transitionFrame(at time: TimeInterval) -> ClipTransitionFrame {
        ClipTransitionResolver.frame(
            junctions: project.transitionJunctions(),
            at: time
        )
    }

    /// Places (or replaces) a transition on the junction between two
    /// adjacent clips, using the current template duration.
    func applyTransition(
        _ style: ClipTransitionStyle,
        toJunction junction: TransitionJunction
    ) {
        let snapshot = captureTimelineSnapshot()
        let transition = ClipTransition(
            leftClipID: junction.leftClipID,
            rightClipID: junction.rightClipID,
            style: style,
            duration: transitionDuration.clamped(
                to: ClipTransitionResolver.minimumDuration...ClipTransitionResolver.maximumDuration
            )
        )
        project.setTransition(transition)
        selectedTransitionID = project.transitionJunctions().first {
            $0.leftClipID == junction.leftClipID
                && $0.rightClipID == junction.rightClipID
        }?.transition?.id
        inspectorPanel = .transition
        registerTimelineEdit("Apply Transition", before: snapshot)
        statusMessage = "Transition applied."
    }

    func updateSelectedTransition(
        style: ClipTransitionStyle? = nil,
        duration: TimeInterval? = nil
    ) {
        guard let selectedTransitionID,
              let index = project.transitions.firstIndex(where: {
                  $0.id == selectedTransitionID
              }) else { return }
        let snapshot = captureTimelineSnapshot()
        if let style {
            project.transitions[index].style = style
        }
        if let duration {
            project.transitions[index].duration = duration.clamped(
                to: ClipTransitionResolver.minimumDuration...ClipTransitionResolver.maximumDuration
            )
        }
        registerTimelineEdit("Update Transition", before: snapshot)
    }

    func removeSelectedTransition() {
        guard let selectedTransitionID,
              project.transitions.contains(where: {
                  $0.id == selectedTransitionID
              }) else { return }
        let snapshot = captureTimelineSnapshot()
        project.transitions.removeAll { $0.id == selectedTransitionID }
        self.selectedTransitionID = nil
        registerTimelineEdit("Remove Transition", before: snapshot)
        statusMessage = "Transition removed."
    }

    /// Seeks just before a transition and plays so it can be previewed.
    func previewTransition() {
        let junctions = project.transitionJunctions()
        let target = junctions.first {
            $0.transition?.id == selectedTransitionID
        } ?? junctions.first { $0.transition != nil }
        guard let junction = target, junction.transition != nil else {
            statusMessage = "Drag a transition onto a cut between clips."
            return
        }
        let duration = junction.transition?.duration ?? transitionDuration
        seek(to: max(0, junction.time - max(1, duration)))
        if !isPlaying {
            togglePlayback()
        }
    }

    /// Removes silent footage from the start and end of the recording only.
    func smartTrimSilence() {
        guard !audioAnalysis.waveform.isEmpty else {
            statusMessage = "An audio track is required to smart trim."
            return
        }
        let snapshot = captureTimelineSnapshot()
        guard project.trimSilenceAtEdges(
            waveform: audioAnalysis.waveform,
            sourceDuration: sourceDuration
        ) else {
            statusMessage = "No silent footage at the start or end."
            return
        }
        seek(to: min(playhead, project.duration))
        registerTimelineEdit("Smart Trim", before: snapshot)
        statusMessage = "Removed silent footage from the start and end."
    }

    func resetSelectedTrim() {
        guard let selectedClipID else { return }
        let snapshot = captureTimelineSnapshot()
        guard
              project.resetTrim(
                  clipID: selectedClipID,
                  sourceDuration: sourceDuration
              ) else {
            statusMessage = "The selected clip is already using its available source range."
            return
        }
        project.clampTimedEventsToDuration()
        seek(to: min(playhead, project.duration))
        registerTimelineEdit("Reset Clip Trim", before: snapshot)
        statusMessage = "Clip trim reset."
    }

    func updateSelectedClip(playbackRate: Double? = nil, volume: Double? = nil) {
        guard let selectedClipID,
              let index = project.clips.firstIndex(where: { $0.id == selectedClipID }) else {
            return
        }
        prepareTimelineMutation(.clip)
        let snapshot = captureTimelineSnapshot()
        if let playbackRate {
            project.clips[index].playbackRate = playbackRate.clamped(to: 0.5...24)
        }
        if let volume {
            project.clips[index].volume = volume.clamped(to: 0...4)
            refreshSourceAudioMix()
        }
        project.clampTimedEventsToDuration()
        seek(to: min(playhead, project.duration))
        registerTimelineMutation(.clip, before: snapshot)
    }

    func normalizeAllAudio() {
        guard audioAnalysis.rms > 0 else {
            statusMessage = "No audio signal was found."
            return
        }
        let snapshot = captureTimelineSnapshot()
        let gain = audioAnalysis.recommendedGain
        for index in project.clips.indices {
            project.clips[index].volume = gain
        }
        refreshSourceAudioMix()
        registerTimelineEdit("Normalize Audio", before: snapshot)
        statusMessage = String(format: "Audio normalized to %.0f%%.", gain * 100)
        seek(to: playhead)
    }

    func generateCaptions() {
        guard let sourceURL, !audioAnalysis.waveform.isEmpty else {
            statusMessage = "An audio track is required to generate captions."
            return
        }
        isGeneratingCaptions = true
        statusMessage = "Generating captions on this Mac…"
        Task {
            do {
                project.captions = try await captionGenerator.generate(
                    from: sourceURL,
                    localeIdentifier: captionLanguage,
                    vocabulary: captionVocabulary
                )
                isGeneratingCaptions = false
                showCaptions = true
                statusMessage = "Generated \(project.captions.count) caption segments."
            } catch {
                isGeneratingCaptions = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func updateCaption(id: UUID, text: String) {
        guard let index = project.captions.firstIndex(where: { $0.id == id }) else {
            return
        }
        project.captions[index].text = text
    }

    func removeAllCaptions() {
        project.captions.removeAll()
        statusMessage = "Captions removed."
    }

    func removeAllShortcuts() {
        project.shortcuts.removeAll()
        statusMessage = "Shortcut labels removed."
    }

    func addZoom(
        start: TimeInterval,
        duration requestedDuration: TimeInterval
    ) {
        guard project.duration > 0 else { return }
        let snapshot = captureTimelineSnapshot()
        let safeStart = start.clamped(
            to: 0...max(0, project.duration - 0.1)
        )
        let safeDuration = requestedDuration.clamped(
            to: 0.1...max(0.1, project.duration - safeStart)
        )
        let cursor = project.nearestCursor(to: safeStart)
        let zoom = ZoomEvent(
            start: safeStart,
            duration: safeDuration,
            scale: zoomScale,
            focusX: cursor?.normalizedX ?? 0.5,
            focusY: cursor?.normalizedY ?? 0.5,
            followsCursor: true
        )
        guard project.insertZoom(zoom) else {
            if let occupied = project.zooms.first(where: {
                safeStart >= $0.start && safeStart < $0.end
            }) {
                selectedZoomID = occupied.id
                inspectorPanel = .zoom
            }
            statusMessage = "Zooms cannot overlap."
            return
        }
        selectedZoomID = zoom.id
        inspectorPanel = .zoom
        registerTimelineEdit("Add Zoom", before: snapshot)
        statusMessage = "Zoom added at the current cursor position."
    }

    func addZoomAtPlayhead() {
        addZoom(start: playhead, duration: zoomDuration)
    }

    func regenerateAutomaticZooms() {
        let snapshot = captureTimelineSnapshot()
        project.generateZoomsFromClicks(
            scale: zoomScale,
            duration: zoomDuration
        )
        selectedZoomID = project.zooms.first?.id
        registerTimelineEdit("Regenerate Zooms", before: snapshot)
        statusMessage = project.zooms.isEmpty
            ? "No long right-button holds were found; add a zoom manually."
            : "Generated \(project.zooms.count) cursor-focused zooms."
    }

    func updateSelectedZoom(scale: Double? = nil, duration: Double? = nil) {
        guard let selectedZoomID,
              let index = project.zooms.firstIndex(where: { $0.id == selectedZoomID }) else {
            return
        }
        prepareTimelineMutation(.zoom)
        let snapshot = captureTimelineSnapshot()
        if let scale { project.zooms[index].scale = scale }
        if let duration {
            project.setZoomRange(
                id: selectedZoomID,
                start: project.zooms[index].start,
                duration: duration,
                edit: .resizeTrailing
            )
        }
        registerTimelineMutation(.zoom, before: snapshot)
    }

    func updateSelectedZoom(followsCursor: Bool) {
        guard let selectedZoomID,
              let index = project.zooms.firstIndex(
                where: { $0.id == selectedZoomID }
              ) else {
            return
        }
        prepareTimelineMutation(.zoom)
        let snapshot = captureTimelineSnapshot()
        project.zooms[index].followsCursor = followsCursor
        registerTimelineMutation(.zoom, before: snapshot)
    }

    var isZoomedAtPlayhead: Bool {
        project.zooms.contains {
            playhead >= $0.start && playhead < $0.end - 0.001
        }
    }

    func toggleZoomAtPlayhead() {
        if let index = project.zooms.firstIndex(where: {
            playhead >= $0.start && playhead < $0.end - 0.001
        }) {
            let snapshot = captureTimelineSnapshot()
            let zoom = project.zooms[index]
            selectedZoomID = zoom.id
            if playhead - zoom.start <= 0.2 {
                project.zooms.remove(at: index)
                selectedZoomID = project.zooms.first?.id
                statusMessage = "Zoom cancelled."
            } else {
                project.zooms[index].duration = playhead - zoom.start
                statusMessage = "Zoom returns to the full view here."
            }
            registerTimelineEdit("Edit Zoom", before: snapshot)
            return
        }
        addZoomAtPlayhead()
    }

    func setZoomRange(
        id: UUID,
        start: TimeInterval,
        duration: TimeInterval,
        edit: ZoomRangeEdit
    ) {
        prepareTimelineMutation(.zoom)
        let snapshot = captureTimelineSnapshot()
        project.setZoomRange(
            id: id,
            start: start,
            duration: duration,
            edit: edit
        )
        registerTimelineMutation(.zoom, before: snapshot)
    }

    func splitZoom(
        id: UUID,
        at timelineTime: TimeInterval
    ) {
        let snapshot = captureTimelineSnapshot()
        guard let rightID = project.splitZoom(
            id: id,
            atTimelineTime: timelineTime
        ) else {
            statusMessage = "Click farther inside a zoom to split it."
            return
        }
        selectedZoomID = rightID
        inspectorPanel = .zoom
        playhead = timelineTime
        registerTimelineEdit("Split Zoom", before: snapshot)
        statusMessage = "Zoom split at current time."
    }

    func moveSelectedZoomFocus(x: CGFloat, y: CGFloat) {
        guard let selectedZoomID,
              let index = project.zooms.firstIndex(where: { $0.id == selectedZoomID }) else {
            return
        }
        prepareTimelineMutation(.zoom)
        let snapshot = captureTimelineSnapshot()
        project.zooms[index].focusX = x.clamped(to: 0...1)
        project.zooms[index].focusY = y.clamped(to: 0...1)
        registerTimelineMutation(.zoom, before: snapshot)
    }

    func deleteSelectedZoom() {
        deleteSelectedZooms()
    }

    /// Removes every zoom in the multi-selection (falling back to the single
    /// selection) as one undoable edit.
    func deleteSelectedZooms() {
        var ids = selectedZoomIDs
        if let selectedZoomID {
            ids.insert(selectedZoomID)
        }
        let removedCount = project.zooms.filter { ids.contains($0.id) }.count
        guard removedCount > 0 else { return }
        let snapshot = captureTimelineSnapshot()
        project.zooms.removeAll { ids.contains($0.id) }
        selectedZoomIDs = []
        selectedZoomID = project.zooms.first?.id
        registerTimelineEdit(
            removedCount > 1 ? "Delete Zooms" : "Delete Zoom",
            before: snapshot
        )
    }

    /// Collapses the zoom selection to a single block (plain click).
    func selectZoom(_ id: UUID) {
        selectedZoomID = id
        selectedZoomIDs = [id]
        inspectorPanel = .zoom
    }

    /// Deletes one specific zoom. When the block belongs to a larger
    /// multi-selection, the whole selection is removed instead.
    func deleteZoom(id: UUID) {
        if selectedZoomIDs.count > 1, selectedZoomIDs.contains(id) {
            deleteSelectedZooms()
            return
        }
        selectedZoomIDs = [id]
        selectedZoomID = id
        deleteSelectedZooms()
    }

    /// ⌘-click: adds or removes one zoom from the multi-selection.
    func toggleZoomSelection(_ id: UUID) {
        guard project.zooms.contains(where: { $0.id == id }) else { return }
        if selectedZoomIDs.isEmpty, let selectedZoomID {
            selectedZoomIDs = [selectedZoomID]
        }
        if selectedZoomIDs.contains(id) {
            selectedZoomIDs.remove(id)
        } else {
            selectedZoomIDs.insert(id)
        }
        selectedZoomID = selectedZoomIDs.contains(id)
            ? id
            : selectedZoomIDs.first
        if !selectedZoomIDs.isEmpty {
            inspectorPanel = .zoom
        }
    }

    /// Selects every zoom block on the timeline (⌘A).
    @discardableResult
    func selectAllZooms() -> Bool {
        guard !project.zooms.isEmpty else { return false }
        selectedZoomIDs = Set(project.zooms.map(\.id))
        selectedZoomID = project.zooms.first?.id
        inspectorPanel = .zoom
        statusMessage = "All zooms selected — press Delete to remove them."
        return true
    }

    /// Marquee selection: selects every zoom overlapping the dragged time
    /// range. Holding ⇧ keeps blocks that were already selected.
    func selectZooms(
        intersecting range: ClosedRange<TimeInterval>,
        extendingSelection: Bool = false
    ) {
        let hits = project.zooms
            .filter { $0.end > range.lowerBound && $0.start < range.upperBound }
            .map(\.id)
        var ids = extendingSelection ? selectedZoomIDs : []
        ids.formUnion(hits)
        selectedZoomIDs = ids
        selectedZoomID = hits.first ?? ids.first
        if !ids.isEmpty {
            inspectorPanel = .zoom
        }
    }

    /// Clears any zoom multi-selection without touching the single selection.
    func clearZoomMultiSelection() {
        guard !selectedZoomIDs.isEmpty else { return }
        selectedZoomIDs = []
    }

    func addRedactionAtPlayhead() {
        guard project.duration > 0 else { return }
        let snapshot = captureTimelineSnapshot()
        let start = min(playhead, max(0, project.duration - 0.1))
        let redaction = PrivacyRedaction(
            start: start,
            duration: min(3, max(0.1, project.duration - start)),
            effect: .blur
        )
        project.redactions.append(redaction)
        project.redactions.sort { $0.start < $1.start }
        selectedRedactionID = redaction.id
        inspectorPanel = .privacy
        registerTimelineEdit("Add Privacy Block", before: snapshot)
        statusMessage = "Privacy blur added."
    }

    func beginPrivacyTool() {
        guard sourceURL != nil, project.duration > 0 else {
            activeTimelineTool = .selection
            inspectorPanel = .privacy
            statusMessage = "Record or open a video before using Privacy mode."
            return
        }
        activeTimelineTool = activeTimelineTool == .redaction
            ? .selection
            : .redaction
        inspectorPanel = .privacy
        statusMessage = activeTimelineTool == .redaction
            ? "Privacy mode is active — drag on the video to blur any area."
            : "Privacy mode closed."
    }

    func addRedaction(
        startPoint: CGPoint,
        endPoint: CGPoint,
        start: TimeInterval? = nil,
        duration: TimeInterval = 3
    ) {
        guard project.duration > 0 else { return }
        let minX = min(startPoint.x, endPoint.x).clamped(to: 0...1)
        let maxX = max(startPoint.x, endPoint.x).clamped(to: 0...1)
        let minY = min(startPoint.y, endPoint.y).clamped(to: 0...1)
        let maxY = max(startPoint.y, endPoint.y).clamped(to: 0...1)
        guard maxX - minX >= 0.02, maxY - minY >= 0.02 else {
            statusMessage = "Drag a larger area to create a privacy blur."
            return
        }
        let snapshot = captureTimelineSnapshot()
        let safeStart = (start ?? playhead).clamped(
            to: 0...max(0, project.duration - 0.1)
        )
        let redaction = PrivacyRedaction(
            start: safeStart,
            duration: duration.clamped(
                to: 0.1...max(0.1, project.duration - safeStart)
            ),
            normalizedX: (minX + maxX) / 2,
            normalizedY: (minY + maxY) / 2,
            normalizedWidth: maxX - minX,
            normalizedHeight: maxY - minY,
            opacity: 0.92,
            effect: .blur
        )
        project.redactions.append(redaction)
        project.redactions.sort { $0.start < $1.start }
        selectedRedactionID = redaction.id
        inspectorPanel = .privacy
        registerTimelineEdit("Add Privacy Blur", before: snapshot)
        statusMessage = "Privacy blur added to the timeline."
    }

    func addSpotlightAtPlayhead() {
        guard project.duration > 0 else { return }
        let snapshot = captureTimelineSnapshot()
        let start = min(playhead, max(0, project.duration - 0.1))
        let spotlight = PrivacyRedaction(
            start: start,
            duration: min(3, max(0.1, project.duration - start)),
            normalizedWidth: 0.42,
            normalizedHeight: 0.28,
            opacity: 0.68,
            presentation: .spotlight,
            highlightHue: 0.13
        )
        project.redactions.append(spotlight)
        project.redactions.sort { $0.start < $1.start }
        selectedRedactionID = spotlight.id
        inspectorPanel = .privacy
        registerTimelineEdit("Add Spotlight", before: snapshot)
        statusMessage = "Spotlight highlight added."
    }

    func activeRedactions(
        at time: TimeInterval? = nil
    ) -> [PrivacyRedaction] {
        project.activeRedactions(atTimelineTime: time ?? playhead)
    }

    func setRedactionRange(
        id: UUID,
        start: TimeInterval,
        duration: TimeInterval
    ) {
        prepareTimelineMutation(.redaction)
        let snapshot = captureTimelineSnapshot()
        project.setRedactionRange(
            id: id,
            start: start,
            duration: duration
        )
        registerTimelineMutation(.redaction, before: snapshot)
    }

    func updateSelectedRedaction(
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        opacity: CGFloat? = nil,
        highlightHue: CGFloat? = nil,
        effect: PrivacyRedactionEffect? = nil,
        duration: TimeInterval? = nil
    ) {
        guard let selectedRedactionID,
              let index = project.redactions.firstIndex(
                  where: { $0.id == selectedRedactionID }
              ) else {
            return
        }
        prepareTimelineMutation(.redaction)
        let snapshot = captureTimelineSnapshot()
        if let width {
            project.redactions[index].normalizedWidth = width.clamped(
                to: 0.06...1
            )
        }
        if let height {
            project.redactions[index].normalizedHeight = height.clamped(
                to: 0.05...1
            )
        }
        if let opacity {
            project.redactions[index].opacity = opacity.clamped(to: 0.35...1)
        }
        if let highlightHue {
            project.redactions[index].highlightHue = highlightHue.clamped(
                to: 0...1
            )
        }
        if let effect {
            project.redactions[index].effect = effect
        }
        if let duration {
            project.setRedactionRange(
                id: selectedRedactionID,
                start: project.redactions[index].start,
                duration: duration
            )
        }
        clampSelectedRedactionCenter()
        registerTimelineMutation(.redaction, before: snapshot)
    }

    func moveSelectedRedaction(x: CGFloat, y: CGFloat) {
        guard let selectedRedactionID,
              let index = project.redactions.firstIndex(
                  where: { $0.id == selectedRedactionID }
              ) else {
            return
        }
        prepareTimelineMutation(.redaction)
        let snapshot = captureTimelineSnapshot()
        project.redactions[index].normalizedX = x
        project.redactions[index].normalizedY = y
        clampSelectedRedactionCenter()
        registerTimelineMutation(.redaction, before: snapshot)
    }

    func deleteSelectedRedaction() {
        guard let selectedRedactionID,
              project.redactions.contains(
                where: { $0.id == selectedRedactionID }
              ) else {
            return
        }
        let snapshot = captureTimelineSnapshot()
        let wasSpotlight = project.redactions.first {
            $0.id == selectedRedactionID
        }?.resolvedPresentation == .spotlight
        project.redactions.removeAll { $0.id == selectedRedactionID }
        self.selectedRedactionID = project.redactions.first?.id
        registerTimelineEdit(
            wasSpotlight ? "Delete Spotlight" : "Delete Privacy Block",
            before: snapshot
        )
        statusMessage = wasSpotlight
            ? "Spotlight highlight removed."
            : "Privacy redaction removed."
    }

    func activeAnnotations(
        at time: TimeInterval? = nil
    ) -> [Annotation] {
        let timelineTime = time ?? playhead
        guard let sourceTime = project.sourceTime(
            forTimelineTime: timelineTime
        ) else {
            return []
        }
        return project.activeAnnotations(atSourceTime: sourceTime)
    }

    // MARK: Recording-time drawing

    func toggleRecordingDrawingTool(_ kind: AnnotationKind) {
        recordingDrawingTool = recordingDrawingTool == kind ? nil : kind
    }

    /// Reads the global Quartz mouse position and normalizes it against the
    /// recorded source frame, matching `captureCursorSample` (Y flipped to
    /// bottom-up video-composition coordinates).
    func normalizedDrawingPoint() -> NormalizedPoint? {
        let frame = recorder.sourceFrame
        guard frame.width > 0, frame.height > 0,
              let point = CGEvent(source: nil)?.location else {
            return nil
        }
        let x = ((point.x - frame.minX) / frame.width).clamped(to: 0...1)
        let topDownY = ((point.y - frame.minY) / frame.height).clamped(to: 0...1)
        return NormalizedPoint(x: x, y: 1 - topDownY)
    }

    func commitRecordingAnnotation(
        kind: AnnotationKind,
        points: [NormalizedPoint],
        start: NormalizedPoint,
        end: NormalizedPoint,
        strokeBeganAt: TimeInterval,
        strokeEndedAt: TimeInterval
    ) {
        guard isRecording, !isRecordingPaused else { return }
        let annotation = Annotation(
            kind: kind,
            start: strokeBeganAt,
            duration: 3,
            drawDuration: max(0, strokeEndedAt - strokeBeganAt),
            points: kind == .brush ? points : [],
            normalizedStartX: start.x,
            normalizedStartY: start.y,
            normalizedEndX: end.x,
            normalizedEndY: end.y,
            lineWidth: recordingAnnotationLineWidth,
            color: recordingAnnotationColor
        )
        project.annotations.append(annotation)
    }

    func undoLastRecordingAnnotation() {
        guard !project.annotations.isEmpty else { return }
        project.annotations.removeLast()
    }

    func clearRecordingAnnotations() {
        project.annotations.removeAll()
    }

    private func clampSelectedRedactionCenter() {
        guard let selectedRedactionID,
              let index = project.redactions.firstIndex(
                  where: { $0.id == selectedRedactionID }
              ) else {
            return
        }
        let halfWidth = project.redactions[index].normalizedWidth / 2
        let halfHeight = project.redactions[index].normalizedHeight / 2
        project.redactions[index].normalizedX = project.redactions[index]
            .normalizedX.clamped(to: halfWidth...(1 - halfWidth))
        project.redactions[index].normalizedY = project.redactions[index]
            .normalizedY.clamped(to: halfHeight...(1 - halfHeight))
    }

    var resolvedExportDimensions: ExportDimensions {
        exportResolution.dimensions(
            sourceSize: sourcePixelSize,
            canvasAspectRatio: canvasAspectRatio,
            customDimensions: ExportDimensions(
                width: exportCustomWidth,
                height: exportCustomHeight
            )
        )
    }

    var exportEstimate: ExportEstimate {
        ExportEstimateCalculator.estimate(
            timelineDuration: project.duration,
            dimensions: resolvedExportDimensions,
            frameRate: exportFrameRate,
            format: exportFormat,
            quality: exportQuality
        )
    }

    func presentExportSheet(
        destination: ExportDestination? = nil
    ) {
        guard sourceURL != nil, !project.clips.isEmpty else {
            statusMessage = "Record or import a video before exporting."
            return
        }
        if let destination {
            exportDestination = destination
        }
        exportFrameRate = ExportFrameRateOptions.normalized(
            exportFrameRate,
            for: exportFormat
        )
        isExportSheetPresented = true
    }

    func exportVideo(destinationOverride: ExportDestination? = nil) {
        guard let sourceURL, !project.clips.isEmpty else {
            statusMessage = "Record or import a video before exporting."
            return
        }

        let selectedDestination = destinationOverride ?? exportDestination
        let destination: URL
        switch selectedDestination {
        case .file:
            let panel = NSSavePanel()
            panel.allowedContentTypes = exportFormat == .gif ? [.gif] : [.mpeg4Movie]
            panel.nameFieldStringValue = exportFormat == .gif
                ? "ScreenFree Export.gif"
                : "ScreenFree Export.mp4"
            guard panel.runModal() == .OK, let panelURL = panel.url else { return }
            destination = panelURL
        case .clipboard:
            do {
                destination = try makeClipboardExportURL(format: exportFormat)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        case .shareableLink:
            do {
                destination = try makeSharedExportURL(format: exportFormat)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        let exportProject = project
        let exportCanvasStyle = currentCanvasRenderStyle
        let exportCameraStyle = currentCameraOverlayStyle
        let exportBackgroundMusicURL = backgroundMusicURL
        let exportBackgroundMusicVolume = backgroundMusicVolume
        let exportRecordedAudioMix = currentRecordedAudioMix
        let selectedFormat = exportFormat
        let selectedFrameRate = ExportFrameRateOptions.normalized(
            exportFrameRate,
            for: selectedFormat
        )
        let presetName = exportQuality.presetName(for: exportResolution)
        let exportDimensions = resolvedExportDimensions
        let renderSizeOverride = exportResolution == .source
            ? nil
            : exportDimensions.size
        let maximumFileSizeBytes = ExportEstimateCalculator.targetFileLength(
            timelineDuration: exportProject.duration,
            dimensions: exportDimensions,
            frameRate: selectedFrameRate,
            format: selectedFormat,
            quality: exportQuality
        )

        exportProgress = 0
        isExporting = true
        isVideoExporting = true
        statusMessage = "Rendering cursor zooms and timeline edits…"
        exportTask = Task {
            do {
                try await exporter.export(
                    sourceURL: sourceURL,
                    cameraURL: cameraURL,
                    backgroundMusicURL: exportBackgroundMusicURL,
                    backgroundMusicVolume: exportBackgroundMusicVolume,
                    recordedAudioMix: exportRecordedAudioMix,
                    project: exportProject,
                    canvasStyle: exportCanvasStyle,
                    cameraStyle: exportCameraStyle,
                    destinationURL: destination,
                    format: selectedFormat,
                    frameRate: selectedFrameRate,
                    quality: exportQuality,
                    renderSizeOverride: renderSizeOverride,
                    presetName: presetName,
                    maximumFileSizeBytes: maximumFileSizeBytes,
                    progress: { [weak self] value in
                        self?.exportProgress = value.clamped(to: 0...1)
                    }
                )
                isExporting = false
                isVideoExporting = false
                exportProgress = 1
                exportTask = nil
                isExportSheetPresented = false
                switch selectedDestination {
                case .file:
                    statusMessage = "Exported \(destination.lastPathComponent)"
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                case .clipboard:
                    try videoPasteboardWriter.write(fileURL: destination)
                    statusMessage = "Copied the exported video to the clipboard."
                case .shareableLink:
                    statusMessage = "Export ready to share."
                    presentSharingOptions(for: destination)
                }
            } catch is CancellationError {
                isExporting = false
                isVideoExporting = false
                exportTask = nil
                statusMessage = "Export cancelled."
            } catch {
                isExporting = false
                isVideoExporting = false
                exportTask = nil
                if selectedDestination != .file {
                    try? FileManager.default.removeItem(at: destination)
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func setCustomExportWidth(_ width: Int) {
        exportCustomWidth = ExportDimensions.sanitized(width)
    }

    func setCustomExportHeight(_ height: Int) {
        exportCustomHeight = ExportDimensions.sanitized(height)
    }

    func cancelExport() {
        exportTask?.cancel()
    }

    private func makeClipboardExportURL(format: ExportFormat) throws -> URL {
        try makeTemporaryExportURL(
            directoryName: "Clipboard Exports",
            format: format
        )
    }

    private func makeSharedExportURL(format: ExportFormat) throws -> URL {
        try makeTemporaryExportURL(
            directoryName: "Shared Exports",
            format: format
        )
    }

    private func makeTemporaryExportURL(
        directoryName: String,
        format: ExportFormat
    ) throws -> URL {
        let cacheRoot = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = cacheRoot
            .appendingPathComponent("ScreenFree", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent(
            "ScreenFree-\(UUID().uuidString).\(format == .gif ? "gif" : "mp4")"
        )
    }

    private func presentSharingOptions(for url: URL) {
        isExportSheetPresented = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self else { return }
            guard let view = NSApp.mainWindow?.contentView
                ?? NSApp.keyWindow?.contentView else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return
            }
            let picker = NSSharingServicePicker(items: [url])
            activeSharingPicker = picker
            let anchor = CGRect(
                x: view.bounds.midX,
                y: view.bounds.midY,
                width: 1,
                height: 1
            )
            picker.show(
                relativeTo: anchor,
                of: view,
                preferredEdge: .minY
            )
        }
    }

    private func pruneClipboardExports() {
        guard let cacheRoot = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return
        }
        let expiration = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let screenFreeCache = cacheRoot
            .appendingPathComponent("ScreenFree", isDirectory: true)
        for directoryName in ["Clipboard Exports", "Shared Exports"] {
            let directory = screenFreeCache.appendingPathComponent(
                directoryName,
                isDirectory: true
            )
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for file in files {
                let date = try? file.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                if date.map({ $0 < expiration }) == true {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    func copyCurrentFrame() {
        guard sourceURL != nil, !project.clips.isEmpty else {
            statusMessage = "Record or import a video before exporting."
            return
        }
        isExporting = true
        statusMessage = "Rendering the current frame…"
        Task {
            do {
                let image = try await renderCurrentFrame()
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                let pasteboardImage = NSImage(
                    cgImage: image,
                    size: NSSize(width: image.width, height: image.height)
                )
                guard pasteboard.writeObjects([pasteboardImage]) else {
                    throw FrameExportError.cannotWritePasteboard
                }
                isExporting = false
                statusMessage = "Copied the current frame to the clipboard."
            } catch {
                isExporting = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func saveCurrentFrame() {
        guard sourceURL != nil, !project.clips.isEmpty else {
            statusMessage = "Record or import a video before exporting."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "ScreenFree Frame.png"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        isExporting = true
        statusMessage = "Rendering the current frame…"
        Task {
            do {
                let image = try await renderCurrentFrame()
                guard let data = NSBitmapImageRep(cgImage: image)
                    .representation(using: .png, properties: [:]) else {
                    throw FrameExportError.cannotEncodePNG
                }
                try data.write(to: destination, options: .atomic)
                isExporting = false
                statusMessage = "Saved \(destination.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                isExporting = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func renderCurrentFrame() async throws -> CGImage {
        guard let sourceURL else {
            throw VideoExportError.missingVideoTrack
        }
        return try await exporter.renderFrame(
            sourceURL: sourceURL,
            cameraURL: cameraURL,
            project: project,
            timelineTime: playhead,
            canvasStyle: currentCanvasRenderStyle,
            cameraStyle: currentCameraOverlayStyle,
            frameRate: exportFrameRate
        )
    }

    private var currentCanvasRenderStyle: CanvasRenderStyle {
        CanvasRenderStyle(
            aspectRatio: canvasAspectRatio,
            contentMode: canvasContentMode,
            padding: canvasPadding,
            cornerRadius: cornerRadius,
            backgroundHue: backgroundHue,
            backgroundMode: backgroundMode,
            wallpaperPreset: wallpaperPreset,
            backgroundImageURL: backgroundImageURL,
            backgroundBlur: backgroundBlur,
            shadowOpacity: shadowStrength,
            cursorSize: cursorSize,
            cursorReplacement: cursorReplacement,
            showCursor: showCursor,
            hideCursorWhenIdle: hideCursorWhenIdle,
            cursorIdleTimeout: cursorIdleTimeout,
            cursorTailFreeze: cursorTailFreeze,
            cursorLoopToStart: cursorLoopToStart,
            removeCursorShakes: removeCursorShakes,
            cursorShakeThreshold: cursorShakeThreshold,
            optimizeRapidCursorChanges: optimizeRapidCursorChanges,
            smoothCursorMovement: smoothCursorMovement,
            clickEffect: clickEffectPreset,
            showShortcuts: showShortcutOverlay,
            showCaptions: showCaptions,
            captionFontSize: captionFontSize,
            zoomMotion: currentZoomMotionStyle,
            motionBlur: currentMotionBlurStyle
        )
    }

    private var currentMotionBlurStyle: MotionBlurStyle {
        MotionBlurStyle(
            enabled: motionBlurEnabled,
            strength: motionBlurStrength,
            cursorAmount: cursorMotionBlur,
            zoomAmount: zoomMotionBlur,
            panAmount: panMotionBlur
        )
    }

    func resolvedMotionBlur(
        at time: TimeInterval? = nil,
        renderSize: CGSize
    ) -> ResolvedMotionBlur {
        MotionBlurResolver.resolve(
            at: time ?? playhead,
            project: project,
            zoomMotion: currentZoomMotionStyle,
            style: currentMotionBlurStyle,
            renderSize: renderSize,
            cursorTailFreeze: cursorTailFreeze,
            cursorLoopToStart: cursorLoopToStart,
            removeCursorShakes: removeCursorShakes,
            cursorShakeThreshold: cursorShakeThreshold,
            optimizeRapidCursorChanges: optimizeRapidCursorChanges,
            smoothCursorMovement: smoothCursorMovement
        )
    }

    private var currentZoomMotionStyle: ZoomMotionStyle {
        ZoomMotionStyle(
            preset: zoomMotionPreset,
            customTransitionDuration: zoomCustomTransitionDuration,
            customEasing: CubicBezierEasing(
                x1: zoomCustomX1,
                y1: zoomCustomY1,
                x2: zoomCustomX2,
                y2: zoomCustomY2
            )
        )
    }

    private var currentCameraOverlayStyle: CameraOverlayStyle {
        CameraOverlayStyle(
            position: cameraPosition,
            sizeFraction: cameraSize,
            mirrored: cameraMirrored,
            cornerRadius: cameraCornerRadius
        )
    }

    private var currentRecordedAudioMix: RecordedAudioMixStyle? {
        guard let recordedAudioLayout else { return nil }
        return RecordedAudioMixStyle(
            layout: recordedAudioLayout,
            systemVolume: systemAudioVolume,
            microphoneVolume: microphoneAudioVolume,
            microphoneMuted: microphoneAudioMuted,
            trackPeaks: audioAnalysis.trackPeaks,
            trackPeakEnvelopes: audioAnalysis.trackPeakEnvelopes,
            trackLoudness: audioAnalysis.trackLoudness
        )
    }

    private func refreshSourceAudioMix() {
        audioMixRefreshGeneration += 1
        let generation = audioMixRefreshGeneration
        guard let item = player.currentItem else { return }
        let mixStyle = currentRecordedAudioMix
        let previewClips = project.clips
        Task { [weak self, weak item] in
            guard let self, let item,
                  let tracks = try? await item.asset.loadTracks(
                    withMediaType: .audio
                  ),
                  generation == self.audioMixRefreshGeneration,
                  self.player.currentItem === item else {
                return
            }
            let parameters = tracks.enumerated().map { index, track in
                let parameters = AVMutableAudioMixInputParameters(track: track)
                parameters.setVolume(
                    Float(mixStyle?.gain(forTrackAt: index) ?? 1),
                    at: .zero
                )
                for clip in previewClips {
                    let gain = mixStyle?.gain(
                        forTrackAt: index,
                        clipVolume: clip.volume
                    ) ?? clip.volume.clamped(to: 0...2)
                    parameters.setVolume(
                        Float(gain),
                        at: CMTime(
                            seconds: clip.sourceStart,
                            preferredTimescale: 600
                        )
                    )
                }
                return parameters
            }
            guard !parameters.isEmpty else {
                item.audioMix = nil
                return
            }
            let mix = AVMutableAudioMix()
            mix.inputParameters = parameters
            item.audioMix = mix
        }
    }

    func activeZoomMotion(
        at time: TimeInterval? = nil
    ) -> ResolvedZoomMotion? {
        ZoomMotionResolver.state(
            at: time ?? playhead,
            zooms: project.zooms,
            totalDuration: project.duration,
            motion: currentZoomMotionStyle
        )
    }

    func activeClick(
        at time: TimeInterval? = nil
    ) -> (click: MouseClick, progress: Double)? {
        let time = time ?? playhead
        let duration = clickEffectPreset.duration
        guard duration > 0 else { return nil }
        for click in project.clicks.reversed() {
            guard let clickTime = project.timelineTime(forSourceTime: click.time) else {
                continue
            }
            let progress = (time - clickTime) / duration
            if progress >= 0, progress <= 1 {
                return (click, progress)
            }
        }
        return nil
    }

    func activeShortcut(at time: TimeInterval? = nil) -> ShortcutEvent? {
        guard showShortcutOverlay else { return nil }
        let time = time ?? playhead
        return project.shortcuts.reversed().first { shortcut in
            guard let start = project.timelineTime(
                forSourceTime: shortcut.time
            ) else {
                return false
            }
            return time >= start
                && time <= start + ShortcutEvent.displayDuration
        }
    }

    func cursorIsVisible(at time: TimeInterval? = nil) -> Bool {
        guard showCursor else { return false }
        let timelineTime = time ?? playhead
        let returnStart = project.duration
            - TimelineProject.cursorReturnDuration(for: project.duration)
        if cursorLoopToStart, timelineTime >= returnStart {
            return true
        }
        guard hideCursorWhenIdle,
              let sourceTime = project.sourceTime(
                  forTimelineTime: timelineTime
              ) else {
            return true
        }
        let samples = project.cursorSamples
            .filter { $0.time <= sourceTime }
            .sorted { $0.time < $1.time }
        guard let first = samples.first else { return false }
        var previous = first
        var lastMovement = first.time
        for sample in samples.dropFirst() {
            let distance = hypot(
                sample.normalizedX - previous.normalizedX,
                sample.normalizedY - previous.normalizedY
            )
            if distance > 0.0015 {
                lastMovement = sample.time
            }
            previous = sample
        }
        return sourceTime - lastMovement <= cursorIdleTimeout
    }

    func activeCaption(at time: TimeInterval? = nil) -> CaptionCue? {
        guard showCaptions,
              let sourceTime = project.sourceTime(
                forTimelineTime: time ?? playhead
              ) else {
            return nil
        }
        return project.captions.last {
            sourceTime >= $0.sourceStart
                && sourceTime <= $0.sourceStart + $0.duration
        }
    }

    func formatted(_ time: TimeInterval) -> String {
        let seconds = max(0, time)
        return String(format: "%02d:%05.2f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }

    private func installPlayerObserver() {
        guard timeObserver == nil else { return }
        // 60 Hz: the playhead line and the playhead-driven zoom/pan preview
        // animate at display rate instead of a visibly stepped 30 Hz.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 60),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.updatePlayhead(fromSourceTime: time.seconds)
            }
        }
    }

    private func updatePlayhead(fromSourceTime sourceTime: TimeInterval) {
        guard isPlaying,
              !isScrubbing,
              let context = clipContext(atTimelineTime: playhead) else {
            return
        }

        if sourceTime >= context.clip.sourceEnd - 0.015 {
            let nextIndex = context.index + 1
            guard project.clips.indices.contains(nextIndex) else {
                player.pause()
                cameraPlayer.pause()
                backgroundMusicPlayer.pause()
                isPlaying = false
                playhead = project.duration
                return
            }
            let nextStart = project.clips[..<nextIndex].reduce(0) {
                $0 + $1.timelineDuration
            }
            let nextClip = project.clips[nextIndex]
            if Self.playbackBoundaryAction(
                from: context.clip,
                to: nextClip
            ) == .continueTransport {
                let localSource = max(
                    0,
                    sourceTime - nextClip.sourceStart
                )
                playhead = (
                    nextStart
                        + localSource / nextClip.playbackRate
                ).clamped(to: 0...project.duration)
                player.volume = 1
                if abs(player.rate - Float(nextClip.playbackRate)) > 0.001 {
                    player.playImmediately(
                        atRate: Float(nextClip.playbackRate)
                    )
                }
                if cameraURL != nil,
                   abs(cameraPlayer.rate - Float(nextClip.playbackRate)) > 0.001 {
                    cameraPlayer.playImmediately(
                        atRate: Float(nextClip.playbackRate)
                    )
                }
                seekBackgroundMusic(to: playhead, force: false)
                return
            }

            playhead = nextStart
            player.volume = 1
            player.seek(
                to: CMTime(
                    seconds: nextClip.sourceStart,
                    preferredTimescale: 600
                ),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isPlaying else { return }
                    self.player.playImmediately(
                        atRate: Float(nextClip.playbackRate)
                    )
                    if self.cameraURL != nil {
                        self.cameraPlayer.seek(
                            to: CMTime(
                                seconds: nextClip.sourceStart,
                                preferredTimescale: 600
                            ),
                            toleranceBefore: .zero,
                            toleranceAfter: .zero
                        )
                        self.cameraPlayer.playImmediately(
                            atRate: Float(nextClip.playbackRate)
                        )
                    }
                }
            }
            return
        }

        let localSource = max(0, sourceTime - context.clip.sourceStart)
        playhead = (
            context.timelineStart
                + localSource / context.clip.playbackRate
        ).clamped(to: 0...project.duration)
        seekBackgroundMusic(to: playhead, force: false)
    }

    static func playbackBoundaryAction(
        from currentClip: TimelineClip,
        to nextClip: TimelineClip
    ) -> PlaybackBoundaryAction {
        let sourceContinuityTolerance = 1.0 / 600.0
        return abs(currentClip.sourceEnd - nextClip.sourceStart)
            <= sourceContinuityTolerance
            ? .continueTransport
            : .seek
    }

    private func loadBackgroundMusic(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard try await asset.loadTracks(withMediaType: .audio).first != nil else {
            throw AudioBackgroundError.missingAudioTrack
        }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0.02 else {
            throw AudioBackgroundError.missingAudioTrack
        }
        backgroundMusicPlayer.pause()
        backgroundMusicURL = url
        backgroundMusicDuration = duration
        backgroundMusicPlayer.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        backgroundMusicPlayer.volume = Float(
            backgroundMusicVolume.clamped(to: 0...1)
        )
        seekBackgroundMusic(to: playhead, force: true)
    }

    private func seekBackgroundMusic(
        to timelineTime: TimeInterval,
        force: Bool
    ) {
        guard backgroundMusicURL != nil,
              backgroundMusicDuration > 0.02 else {
            return
        }
        let target = timelineTime
            .truncatingRemainder(dividingBy: backgroundMusicDuration)
        let current = backgroundMusicPlayer.currentTime().seconds
        let directDistance = abs(current - target)
        guard force || !current.isFinite || directDistance > 0.15 else {
            return
        }
        backgroundMusicPlayer.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func clipContext(
        atTimelineTime time: TimeInterval
    ) -> (index: Int, clip: TimelineClip, timelineStart: TimeInterval)? {
        guard !project.clips.isEmpty else { return nil }
        let clamped = time.clamped(to: 0...project.duration)
        var timelineStart: TimeInterval = 0
        for (index, clip) in project.clips.enumerated() {
            let timelineEnd = timelineStart + clip.timelineDuration
            if clamped < timelineEnd || index == project.clips.count - 1 {
                return (index, clip, timelineStart)
            }
            timelineStart = timelineEnd
        }
        return nil
    }

    private func beginMouseCapture() {
        let sessionID = UUID()
        activeCursorCaptureSessionID = sessionID
        inputMonitoringGranted = CGPreflightListenEventAccess()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                guard let self,
                      CursorCaptureGate.allows(
                          callbackSessionID: sessionID,
                          activeSessionID: self.activeCursorCaptureSessionID,
                          isRecording: self.isRecording,
                          isPaused: self.isRecordingPaused,
                          isTransitioning: self.isTransitioningRecording
                      ) else {
                    return
                }
                self.captureCursorSample(isClick: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cursorTimer = timer

        if inputMonitoringGranted {
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .rightMouseUp]
            ) { [weak self] event in
                Task { @MainActor in
                    guard let self,
                          CursorCaptureGate.allows(
                              callbackSessionID: sessionID,
                              activeSessionID:
                                  self.activeCursorCaptureSessionID,
                              isRecording: self.isRecording,
                              isPaused: self.isRecordingPaused,
                              isTransitioning: self.isTransitioningRecording
                          ) else {
                        return
                    }
                    switch event.type {
                    case .leftMouseDown:
                        self.captureCursorSample(
                            isClick: true,
                            button: .left
                        )
                    case .rightMouseDown:
                        self.finishRightMouseCapture()
                        self.pendingRightClickID = self.captureCursorSample(
                            isClick: true,
                            button: .right
                        )?.id
                    case .rightMouseUp:
                        self.finishRightMouseCapture()
                    default:
                        break
                    }
                }
            }
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: .keyDown
            ) { [weak self] event in
                Task { @MainActor in
                    guard let self,
                          CursorCaptureGate.allows(
                              callbackSessionID: sessionID,
                              activeSessionID:
                                  self.activeCursorCaptureSessionID,
                              isRecording: self.isRecording,
                              isPaused: self.isRecordingPaused,
                              isTransitioning: self.isTransitioningRecording
                          ) else {
                        return
                    }
                    self.captureShortcut(event)
                }
            }
        }
    }

    private func beginRecordingElapsedTimer() {
        recordingElapsedTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.recordingElapsed = self.currentRecordingElapsed
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        recordingElapsedTimer = timer
    }

    private func endRecordingElapsedTimer() {
        recordingElapsedTimer?.invalidate()
        recordingElapsedTimer = nil
    }

    private func installAutosave() {
        let changes: [AnyPublisher<Void, Never>] = [
            $project.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $sourceURL.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $cameraURL.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $canvasAspectRatio.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $canvasContentMode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $canvasPadding.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $cornerRadius.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $backgroundHue.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $backgroundMode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $wallpaperPreset.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $backgroundImageURL.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $backgroundBlur.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $shadowStrength.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $cursorSize.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $cursorReplacement.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $showCursor.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $hideCursorWhenIdle.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $cursorIdleTimeout.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $cursorTailFreeze.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $cursorLoopToStart.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $removeCursorShakes.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $cursorShakeThreshold.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $optimizeRapidCursorChanges.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $smoothCursorMovement.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $backgroundMusicURL.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $backgroundMusicVolume.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $recordedAudioLayout.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $systemAudioVolume.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $microphoneAudioVolume.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $microphoneAudioMuted.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $clickEffectPreset.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $showShortcutOverlay.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $zoomMotionPreset.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $zoomCustomTransitionDuration.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $zoomCustomX1.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $zoomCustomY1.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $zoomCustomX2.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $zoomCustomY2.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $motionBlurEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $motionBlurStrength.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $cursorMotionBlur.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $zoomMotionBlur.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $panMotionBlur.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $showCaptions.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $captionFontSize.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $captionVocabulary.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $cameraSize.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $cameraCornerRadius.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $cameraMirrored.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $cameraPosition.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(changes)
            .debounce(for: .milliseconds(650), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self, !self.isRestoringProject,
                      let snapshot = self.makeSnapshot() else {
                    return
                }
                try? self.persistence.saveRecovery(snapshot)
                try? self.saveRecordingProjectSidecarIfNeeded(snapshot)
            }
            .store(in: &cancellables)
    }

    private func saveRecordingProjectSidecarIfNeeded(
        _ suppliedSnapshot: ScreenFreeProjectSnapshot? = nil
    ) throws {
        guard let sourceURL else { return }
        let source = sourceURL.standardizedFileURL
        guard source.deletingLastPathComponent()
            == recordingHistoryCatalog.directory.standardizedFileURL else {
            return
        }
        guard let snapshot = suppliedSnapshot ?? makeSnapshot() else { return }
        try persistence.savePreservingRecordedInteractions(
            snapshot,
            to: RecordingProjectSidecar.url(for: source),
            backupURL: RecordingProjectSidecar.backupURL(for: source)
        )
    }

    private func matchingSnapshot(
        at url: URL,
        sourceURL: URL
    ) -> ScreenFreeProjectSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path),
              let snapshot = try? persistence.load(from: url),
              URL(fileURLWithPath: snapshot.sourcePath).standardizedFileURL
                == sourceURL.standardizedFileURL else {
            return nil
        }
        return snapshot
    }

    private func makeSnapshot() -> ScreenFreeProjectSnapshot? {
        guard let sourceURL, !project.clips.isEmpty else { return nil }
        return ScreenFreeProjectSnapshot(
            version: ScreenFreeProjectSnapshot.currentVersion,
            sourcePath: sourceURL.path,
            cameraPath: cameraURL?.path,
            project: project,
            canvasAspectRatio: canvasAspectRatio,
            canvasContentMode: canvasContentMode,
            canvasPadding: canvasPadding,
            cornerRadius: cornerRadius,
            backgroundHue: backgroundHue,
            backgroundMode: backgroundMode,
            wallpaperPreset: wallpaperPreset,
            backgroundImagePath: backgroundImageURL?.path,
            backgroundBlur: backgroundBlur,
            shadowStrength: shadowStrength,
            cursorSize: cursorSize,
            cursorReplacement: cursorReplacement,
            showCursor: showCursor,
            hideCursorWhenIdle: hideCursorWhenIdle,
            cursorIdleTimeout: cursorIdleTimeout,
            cursorTailFreeze: cursorTailFreeze,
            cursorLoopToStart: cursorLoopToStart,
            removeCursorShakes: removeCursorShakes,
            cursorShakeThreshold: cursorShakeThreshold,
            optimizeRapidCursorChanges: optimizeRapidCursorChanges,
            smoothCursorMovement: smoothCursorMovement,
            backgroundMusicPath: backgroundMusicURL?.path,
            backgroundMusicVolume: backgroundMusicVolume,
            recordedAudioLayout: recordedAudioLayout,
            systemAudioVolume: systemAudioVolume,
            microphoneAudioVolume: microphoneAudioVolume,
            microphoneAudioMuted: microphoneAudioMuted,
            showClickRipple: clickEffectPreset != .none,
            clickEffectPreset: clickEffectPreset,
            showShortcutOverlay: showShortcutOverlay,
            showCaptions: showCaptions,
            captionFontSize: captionFontSize,
            captionLanguage: captionLanguage,
            captionVocabulary: captionVocabulary,
            zoomScale: zoomScale,
            zoomDuration: zoomDuration,
            zoomMotionPreset: zoomMotionPreset,
            zoomCustomTransitionDuration: zoomCustomTransitionDuration,
            zoomCustomX1: zoomCustomX1,
            zoomCustomY1: zoomCustomY1,
            zoomCustomX2: zoomCustomX2,
            zoomCustomY2: zoomCustomY2,
            motionBlurEnabled: motionBlurEnabled,
            motionBlurStrength: motionBlurStrength,
            cursorMotionBlur: cursorMotionBlur,
            zoomMotionBlur: zoomMotionBlur,
            panMotionBlur: panMotionBlur,
            cameraSize: cameraSize,
            cameraCornerRadius: cameraCornerRadius,
            cameraMirrored: cameraMirrored,
            cameraPosition: cameraPosition,
            transitionStyle: transitionStyle,
            transitionDuration: transitionDuration,
            script: Self.normalizedScript(recordingScriptText),
            updatedAt: Date()
        )
    }

    /// 空白稿件存 nil：旧版项目缺 key、无稿新项目、有稿项目三者在磁盘上
    /// 保持同一形态，读回时 `?? ""` 即可。
    private static func normalizedScript(_ text: String?) -> String? {
        guard
            let text,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }

    private func restore(_ snapshot: ScreenFreeProjectSnapshot) async throws {
        let wasRestoringProject = isRestoringProject
        isRestoringProject = true
        defer { isRestoringProject = wasRestoringProject }
        let source = URL(fileURLWithPath: snapshot.sourcePath)
        try await loadVideo(source)
        project = snapshot.project
        selectedClipID = project.clips.first?.id
        selectedZoomID = project.zooms.first?.id
        selectedRedactionID = project.redactions.first?.id
        scriptText = snapshot.script ?? ""
        recordingScriptText = Self.normalizedScript(snapshot.script)
        canvasAspectRatio = snapshot.canvasAspectRatio ?? .source
        canvasContentMode = snapshot.canvasContentMode ?? .fit
        canvasPadding = snapshot.canvasPadding
        cornerRadius = snapshot.cornerRadius
        backgroundHue = snapshot.backgroundHue
        backgroundMode = snapshot.backgroundMode
        wallpaperPreset = snapshot.wallpaperPreset ?? .aurora
        backgroundImageURL = snapshot.backgroundImagePath.map {
            URL(fileURLWithPath: $0)
        }
        backgroundBlur = snapshot.backgroundBlur ?? 0
        shadowStrength = snapshot.shadowStrength
        cursorSize = snapshot.cursorSize
        cursorReplacement = snapshot.cursorReplacement ?? .arrow
        showCursor = snapshot.showCursor
        hideCursorWhenIdle = snapshot.hideCursorWhenIdle
        cursorIdleTimeout = snapshot.cursorIdleTimeout
        cursorTailFreeze = snapshot.cursorTailFreeze ?? 0
        cursorLoopToStart = snapshot.cursorLoopToStart ?? false
        removeCursorShakes = snapshot.removeCursorShakes ?? false
        cursorShakeThreshold = (snapshot.cursorShakeThreshold ?? 0.012)
            .clamped(to: 0.002...0.08)
        optimizeRapidCursorChanges =
            snapshot.optimizeRapidCursorChanges ?? false
        smoothCursorMovement = snapshot.smoothCursorMovement ?? false
        backgroundMusicVolume = snapshot.backgroundMusicVolume ?? 0.2
        recordedAudioLayout = snapshot.recordedAudioLayout
        systemAudioVolume = (snapshot.systemAudioVolume ?? 1)
            .clamped(to: 0...2)
        microphoneAudioVolume = (snapshot.microphoneAudioVolume ?? 1)
            .clamped(to: 0...2)
        microphoneAudioMuted = snapshot.microphoneAudioMuted ?? false
        refreshSourceAudioMix()
        clickEffectPreset = snapshot.clickEffectPreset
            ?? (snapshot.showClickRipple ? .ripple : .none)
        showShortcutOverlay = snapshot.showShortcutOverlay ?? true
        showCaptions = snapshot.showCaptions
        captionFontSize = snapshot.captionFontSize
        captionLanguage = snapshot.captionLanguage
        captionVocabulary = snapshot.captionVocabulary ?? ""
        zoomScale = snapshot.zoomScale
        zoomDuration = snapshot.zoomDuration
        zoomMotionPreset = snapshot.zoomMotionPreset ?? .mellow
        zoomCustomTransitionDuration =
            (snapshot.zoomCustomTransitionDuration ?? 0.82)
            .clamped(to: 0.08...1.5)
        zoomCustomX1 = (snapshot.zoomCustomX1 ?? 0.25).clamped(to: 0...1)
        zoomCustomY1 = (snapshot.zoomCustomY1 ?? 0.1).clamped(to: 0...1)
        zoomCustomX2 = (snapshot.zoomCustomX2 ?? 0.25).clamped(to: 0...1)
        zoomCustomY2 = (snapshot.zoomCustomY2 ?? 1).clamped(to: 0...1)
        motionBlurEnabled = snapshot.motionBlurEnabled ?? false
        motionBlurStrength = (snapshot.motionBlurStrength ?? 0.42)
            .clamped(to: 0...1)
        cursorMotionBlur = (snapshot.cursorMotionBlur ?? 0.58)
            .clamped(to: 0...1)
        zoomMotionBlur = (snapshot.zoomMotionBlur ?? 0.45)
            .clamped(to: 0...1)
        panMotionBlur = (snapshot.panMotionBlur ?? 0.34)
            .clamped(to: 0...1)
        cameraSize = snapshot.cameraSize
        cameraCornerRadius = snapshot.cameraCornerRadius
        cameraMirrored = snapshot.cameraMirrored
        cameraPosition = snapshot.cameraPosition
        transitionStyle = snapshot.transitionStyle ?? .fade
        transitionDuration = (snapshot.transitionDuration ?? 0.4)
            .clamped(to: 0.2...1.2)
        cameraPlayer.pause()
        cameraPlayer.replaceCurrentItem(with: nil)
        cameraURL = nil
        if let cameraPath = snapshot.cameraPath,
           FileManager.default.fileExists(atPath: cameraPath) {
            let url = URL(fileURLWithPath: cameraPath)
            cameraURL = url
            cameraPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
            await cameraPlayer.seek(to: .zero)
        }
        backgroundMusicPlayer.pause()
        backgroundMusicPlayer.replaceCurrentItem(with: nil)
        backgroundMusicURL = nil
        backgroundMusicDuration = 0
        if let musicPath = snapshot.backgroundMusicPath,
           FileManager.default.fileExists(atPath: musicPath) {
            try await loadBackgroundMusic(URL(fileURLWithPath: musicPath))
        }
        seek(to: 0)
    }

    private func endMouseCapture() {
        activeCursorCaptureSessionID = nil
        finishRightMouseCapture()
        cursorTimer?.invalidate()
        cursorTimer = nil
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    private func captureCursorSample(
        isClick: Bool,
        button: MouseButtonKind? = nil
    ) -> MouseClick? {
        guard let start = recordingStartUptime else { return nil }
        let elapsed = recordingAccumulatedDuration
            + ProcessInfo.processInfo.systemUptime - start
        let frame = recorder.sourceFrame
        guard frame.width > 0, frame.height > 0 else { return nil }

        // ScreenCaptureKit and CGEvent both use the global Quartz coordinate
        // space (origin at the top-left of the primary display). The editor
        // stores Y bottom-up to match video-composition coordinates.
        guard let point = CGEvent(source: nil)?.location else { return nil }
        let x = ((point.x - frame.minX) / frame.width).clamped(to: 0...1)
        let topDownY = ((point.y - frame.minY) / frame.height).clamped(to: 0...1)
        let y = 1 - topDownY

        project.cursorSamples.append(
            CursorSample(time: elapsed, normalizedX: x, normalizedY: y)
        )
        if isClick {
            let click = MouseClick(
                time: elapsed,
                normalizedX: x,
                normalizedY: y,
                button: button
            )
            project.clicks.append(click)
            return click
        }
        return nil
    }

    private func finishRightMouseCapture() {
        guard let pendingRightClickID,
              let index = project.clicks.firstIndex(
                  where: { $0.id == pendingRightClickID }
              ) else {
            self.pendingRightClickID = nil
            return
        }
        project.clicks[index].holdDuration = max(
            0,
            currentRecordingElapsed - project.clicks[index].time
        )
        self.pendingRightClickID = nil
    }

    private func captureShortcut(_ event: NSEvent) {
        guard showShortcutOverlay, !event.isARepeat else { return }
        guard let label = ShortcutLabelFormatter.label(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers,
            modifiers: event.modifierFlags
        ) else {
            return
        }

        let elapsed = currentRecordingElapsed
        if let last = project.shortcuts.last,
           last.label == label,
           elapsed - last.time < 0.12 {
            return
        }
        project.shortcuts.append(
            ShortcutEvent(time: elapsed, label: label)
        )
    }

    var currentRecordingElapsed: TimeInterval {
        guard !isRecordingPaused, let recordingStartUptime else {
            return recordingAccumulatedDuration
        }
        return recordingAccumulatedDuration
            + ProcessInfo.processInfo.systemUptime - recordingStartUptime
    }
}
