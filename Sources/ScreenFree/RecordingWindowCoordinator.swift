import AppKit
import SwiftUI

@MainActor
final class RecordingWindowCoordinator {
    private weak var store: EditorStore?
    private var panel: RecordingControlPanel?
    private var countdownPanel: RecordingCountdownPanel?
    private var highlightPanel: RecordingHighlightPanel?
    private var speakerNotesPanel: RecordingSpeakerNotesPanel?
    private var hiddenWindows: [NSWindow] = []
    private var applicationPresentation = RecordingApplicationPresentation()
    private let desktopIconController = FinderDesktopIconController()

    init(store: EditorStore) {
        self.store = store
    }

    func present(
        onDisplayID displayID: UInt32?,
        hideDockIcon: Bool,
        hideDesktopIcons: Bool
    ) throws {
        guard let store else { return }
        try desktopIconController.begin(
            hideDesktopIcons: hideDesktopIcons
        )
        if panel == nil {
            let rootView = RecordingControlView(store: store)
                .environment(\.locale, store.appLanguage.locale)
            let panel = RecordingControlPanel(
                contentRect: NSRect(x: 0, y: 0, width: 470, height: 72),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = NSHostingView(rootView: rootView)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.animationBehavior = .utilityWindow
            self.panel = panel
        }

        let panel = panel!
        hiddenWindows = NSApp.windows.filter {
            $0 !== panel && $0.isVisible && !($0 is NSPanel)
        }
        hiddenWindows.forEach { $0.orderOut(nil) }
        if let policy = applicationPresentation.begin(
            currentPolicy: NSApp.activationPolicy(),
            hideDockIcon: hideDockIcon
        ) {
            _ = NSApp.setActivationPolicy(policy)
        }

        let screen = screen(for: displayID) ?? NSScreen.main ?? NSScreen.screens.first
        if let visibleFrame = screen?.visibleFrame {
            let panelFrame = panel.frame
            let origin = CGPoint(
                x: visibleFrame.midX - panelFrame.width / 2,
                y: visibleFrame.maxY - panelFrame.height - 14
            )
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
        updateCountdown(onDisplayID: displayID)
        updateSpeakerNotes(onDisplayID: displayID)
    }

    func dismissAndRestoreEditor() {
        panel?.orderOut(nil)
        countdownPanel?.orderOut(nil)
        highlightPanel?.orderOut(nil)
        speakerNotesPanel?.orderOut(nil)
        desktopIconController.finish()
        if let policy = applicationPresentation.finish() {
            _ = NSApp.setActivationPolicy(policy)
        }
        if let window = hiddenWindows.first {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.windows.first(where: { !($0 is NSPanel) })?.makeKeyAndOrderFront(nil)
        }
        hiddenWindows.removeAll()
        NSApp.activate(ignoringOtherApps: true)
    }

    func recoverDesktopIconsIfNeeded() {
        desktopIconController.recoverIfNeeded()
    }

    func restoreDesktopIconsForTermination() {
        desktopIconController.finish()
    }

    func showEditorWithoutStopping() {
        hiddenWindows.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateSpeakerNotes(onDisplayID displayID: UInt32?) {
        guard let store,
              RecordingSpeakerNotesPresentation.shouldShow(
                  enabled: store.showSpeakerNotes,
                  text: store.speakerNotesText
              ) else {
            speakerNotesPanel?.orderOut(nil)
            return
        }
        if speakerNotesPanel == nil {
            let rootView = RecordingSpeakerNotesView(store: store)
                .environment(\.locale, store.appLanguage.locale)
            let panel = RecordingSpeakerNotesPanel(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: 560,
                    height: 170
                ),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = NSHostingView(rootView: rootView)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            speakerNotesPanel = panel
        }
        let visibleFrame = (
            screen(for: displayID) ?? NSScreen.main ?? NSScreen.screens.first
        )?.visibleFrame ?? .zero
        let frame = RecordingSpeakerNotesPresentation.frame(
            in: visibleFrame,
            size: speakerNotesPanel?.frame.size
                ?? CGSize(width: 560, height: 170)
        )
        speakerNotesPanel?.setFrame(frame, display: true)
        speakerNotesPanel?.orderFrontRegardless()
    }

    func updateCountdown(onDisplayID displayID: UInt32?) {
        guard let store,
              RecordingCountdownPresentation.shouldShow(
                  remaining: store.recordingCountdownRemaining
              ) else {
            countdownPanel?.orderOut(nil)
            return
        }
        if countdownPanel == nil {
            let rootView = RecordingCountdownView(store: store)
                .environment(\.locale, store.appLanguage.locale)
            let panel = RecordingCountdownPanel(
                contentRect: CGRect(
                    origin: .zero,
                    size: RecordingCountdownPresentation.panelSize
                ),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = NSHostingView(rootView: rootView)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary
            ]
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            countdownPanel = panel
        }

        let screenFrame = (
            screen(for: displayID) ?? NSScreen.main ?? NSScreen.screens.first
        )?.frame ?? .zero
        let frame = RecordingCountdownPresentation.frame(
            in: screenFrame,
            size: countdownPanel?.frame.size
                ?? RecordingCountdownPresentation.panelSize
        )
        countdownPanel?.setFrame(frame, display: true)
        countdownPanel?.orderFrontRegardless()
    }

    func updateHighlight(frame: CGRect, visible: Bool) {
        guard visible, frame.width > 1, frame.height > 1, let store else {
            highlightPanel?.orderOut(nil)
            return
        }
        if highlightPanel == nil {
            let rootView = RecordingHighlightView(store: store)
                .environment(\.locale, store.appLanguage.locale)
            let panel = RecordingHighlightPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = NSHostingView(rootView: rootView)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            highlightPanel = panel
        }
        let mainDisplayHeight = NSScreen.screens.first(where: {
            ($0.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber)?.uint32Value == CGMainDisplayID()
        })?.frame.height ?? NSScreen.screens.first?.frame.height ?? frame.height
        let appKitFrame = RecordingHighlightGeometry.appKitFrame(
            forQuartzFrame: frame,
            mainDisplayHeight: mainDisplayHeight
        ).insetBy(dx: -3, dy: -3)
        highlightPanel?.setFrame(appKitFrame, display: true)
        highlightPanel?.orderFrontRegardless()
    }

    private func screen(for displayID: UInt32?) -> NSScreen? {
        guard let displayID else { return nil }
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == displayID
        }
    }
}

struct RecordingSpeakerNotesPresentation {
    static func shouldShow(enabled: Bool, text: String) -> Bool {
        enabled && !text.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    static func frame(
        in visibleFrame: CGRect,
        size: CGSize
    ) -> CGRect {
        CGRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 24,
            width: size.width,
            height: size.height
        )
    }
}

struct RecordingCountdownPresentation {
    static let panelSize = CGSize(width: 320, height: 280)

    static func shouldShow(remaining: Int) -> Bool {
        remaining > 0
    }

    static func frame(
        in screenFrame: CGRect,
        size: CGSize = panelSize
    ) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

struct RecordingCameraPreviewPresentation {
    static func shouldShow(
        cameraSelected: Bool,
        hidden: Bool
    ) -> Bool {
        cameraSelected && !hidden
    }
}

struct RecordingApplicationPresentation {
    private(set) var isPresenting = false
    private var previousPolicy: NSApplication.ActivationPolicy?

    mutating func begin(
        currentPolicy: NSApplication.ActivationPolicy,
        hideDockIcon: Bool
    ) -> NSApplication.ActivationPolicy? {
        guard !isPresenting else { return nil }
        isPresenting = true
        guard hideDockIcon, currentPolicy != .accessory else {
            previousPolicy = nil
            return nil
        }
        previousPolicy = currentPolicy
        return .accessory
    }

    mutating func finish() -> NSApplication.ActivationPolicy? {
        guard isPresenting else { return nil }
        isPresenting = false
        defer { previousPolicy = nil }
        return previousPolicy
    }
}

private final class RecordingControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class RecordingCountdownPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

struct RecordingHighlightGeometry {
    static func appKitFrame(
        forQuartzFrame frame: CGRect,
        mainDisplayHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: frame.minX,
            y: mainDisplayHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}

private final class RecordingHighlightPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

private final class RecordingSpeakerNotesPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

private struct RecordingSpeakerNotesView: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Speaker Notes", systemImage: "text.bubble")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(store.speakerNotesText)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.disabled)
            }
        }
        .padding(16)
        .background(
            .black.opacity(0.84),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .padding(5)
    }
}

private struct RecordingHighlightView: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        RoundedRectangle(cornerRadius: 9)
            .stroke(
                store.isRecordingPaused ? Color.orange : Color.red,
                style: StrokeStyle(lineWidth: 3, dash: [10, 6])
            )
            .shadow(
                color: (store.isRecordingPaused ? Color.orange : Color.red)
                    .opacity(0.7),
                radius: 4
            )
            .padding(3)
            .background(.clear)
    }
}

private struct RecordingCountdownView: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        VStack(spacing: 10) {
            Text("Recording starts in")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))

            Text("\(store.recordingCountdownRemaining)")
                .font(
                    .system(
                        size: 132,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .frame(width: 210, height: 190)
                .background(
                    .black.opacity(0.84),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(
                            StudioTheme.accentGradient,
                            lineWidth: 7
                        )
                }
                .shadow(color: .black.opacity(0.55), radius: 24, y: 12)
                .animation(
                    .spring(response: 0.28, dampingFraction: 0.72),
                    value: store.recordingCountdownRemaining
                )
        }
        .frame(
            width: RecordingCountdownPresentation.panelSize.width,
            height: RecordingCountdownPresentation.panelSize.height
        )
    }
}

private struct RecordingControlView: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    store.isRecordingPaused
                        ? Color.orange
                        : store.isRecording ? Color.red : Color.orange
                )
                .frame(width: 10, height: 10)
                .shadow(color: .red.opacity(0.5), radius: 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    LocalizedStringKey(
                        store.recordingCountdownRemaining > 0
                            ? "Start Recording"
                            : store.isRecordingPaused ? "Paused" : "Recording…"
                    )
                )
                    .font(.system(size: 12, weight: .semibold))
                Text(
                    store.recordingCountdownRemaining > 0
                        ? "\(store.recordingCountdownRemaining)"
                        : store.formattedRecordingElapsed
                )
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            if store.recordMicrophone {
                MiniAudioLevelView(monitor: store.deviceMonitor)
                .frame(width: 76)
            }

            if RecordingCameraPreviewPresentation.shouldShow(
                cameraSelected: store.selectedCameraID != nil,
                hidden: store.hideCameraPreview
            ) {
                CameraPreviewView(session: store.deviceMonitor.cameraSession)
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.55), lineWidth: 1.5)
                    }
            }

            Spacer(minLength: 4)

            Button {
                store.recordingWindowCoordinator.showEditorWithoutStopping()
            } label: {
                Label("Show editor", systemImage: "rectangle.on.rectangle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Show editor")

            Button {
                Task { await store.toggleRecordingPause() }
            } label: {
                Label(
                    store.isRecordingPaused ? "Resume" : "Pause",
                    systemImage: store.isRecordingPaused ? "play.fill" : "pause.fill"
                )
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(store.isRecordingPaused ? "Resume" : "Pause")
            .disabled(!store.isRecording || store.isTransitioningRecording)

            Button {
                Task { await store.stopRecording() }
            } label: {
                Label("Finish", systemImage: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .foregroundStyle(.white)
                    .background(
                        StudioTheme.recordGradient,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!store.isRecording || store.isTransitioningRecording)
        }
        .padding(.horizontal, 16)
        .frame(width: 470, height: 72)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }
}

private struct MiniAudioLevelView: View {
    @ObservedObject var monitor: DeviceMonitor

    var body: some View {
        AudioLevelCapsule(
            level: monitor.microphoneLevel,
            isActive: monitor.isMonitoringMicrophone
        )
    }
}

struct AudioLevelCapsule: View {
    let level: Double
    let isActive: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.09))
                Capsule()
                    .fill(level > 0.92 ? Color.red : level > 0.65 ? Color.orange : Color.green)
                    .frame(width: geometry.size.width * (isActive ? level : 0))
            }
        }
        .frame(height: 8)
        .animation(.linear(duration: 0.08), value: level)
    }
}
