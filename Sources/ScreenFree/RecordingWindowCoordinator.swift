import AppKit
import Combine
import ScreenFreeCore
import SwiftUI

@MainActor
final class RecordingWindowCoordinator {
    private weak var store: EditorStore?
    private var panel: RecordingControlPanel?
    private var countdownPanel: RecordingCountdownPanel?
    private var highlightPanel: RecordingHighlightPanel?
    private var drawingPanel: RecordingDrawingPanel?
    private var teleprompterPanel: RecordingTeleprompterPanel?
    private let teleprompterDelegate = TeleprompterPanelDelegate()
    private var prompterKeyMonitors: [Any] = []
    private var cancellables: Set<AnyCancellable> = []
    private var hiddenWindows: [NSWindow] = []
    private var applicationPresentation = RecordingApplicationPresentation()
    private let desktopIconController = FinderDesktopIconController()

    init(store: EditorStore) {
        self.store = store
        store.$teleprompterPanelSize
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.applyTeleprompterFrame()
            }
            .store(in: &cancellables)
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
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 110),
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
        updateTeleprompter(onDisplayID: displayID)
        installPrompterKeyMonitors()
    }

    func dismissAndRestoreEditor() {
        panel?.orderOut(nil)
        removePrompterKeyMonitors()
        countdownPanel?.orderOut(nil)
        highlightPanel?.orderOut(nil)
        drawingPanel?.orderOut(nil)
        teleprompterPanel?.orderOut(nil)
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

    func updateTeleprompter(onDisplayID displayID: UInt32?) {
        guard let store,
              RecordingTeleprompterPresentation.shouldShow(
                  text: store.scriptText
              ) else {
            teleprompterPanel?.orderOut(nil)
            return
        }
        if teleprompterPanel == nil {
            let rootView = RecordingTeleprompterView(store: store)
                .environment(\.locale, store.appLanguage.locale)
            let panel = RecordingTeleprompterPanel(
                contentRect: CGRect(
                    origin: .zero,
                    size: store.teleprompterPanelSize
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
            panel.delegate = teleprompterDelegate
            teleprompterDelegate.onFrameChange = { [weak self] panel in
                guard panel === self?.teleprompterPanel else { return }
                let origin = panel.frame.origin
                UserDefaults.standard.set(
                    Double(origin.x),
                    forKey: "teleprompterPanelOriginX"
                )
                UserDefaults.standard.set(
                    Double(origin.y),
                    forKey: "teleprompterPanelOriginY"
                )
            }
            teleprompterDelegate.onMove = { [weak self] panel in
                guard panel === self?.teleprompterPanel,
                      self?.store?.isRecording == true else { return }
                self?.store?.prompterPaused = true
            }
            teleprompterPanel = panel
        }
        applyTeleprompterFrame(onDisplayID: displayID)
        teleprompterPanel?.orderFrontRegardless()
    }

    private func applyTeleprompterFrame(onDisplayID displayID: UInt32? = nil) {
        guard let store else { return }
        let visibleFrame = (
            screen(for: displayID ?? store.selectedTargetID)
                ?? NSScreen.main ?? NSScreen.screens.first
        )?.visibleFrame ?? .zero
        let frame = RecordingTeleprompterPresentation.frame(
            in: visibleFrame,
            size: store.teleprompterPanelSize,
            savedOrigin: Self.savedTeleprompterOrigin()
        )
        teleprompterPanel?.setFrame(frame, display: true)
    }

    private static func savedTeleprompterOrigin() -> CGPoint? {
        let defaults = UserDefaults.standard
        guard
            defaults.object(forKey: "teleprompterPanelOriginX") != nil,
            defaults.object(forKey: "teleprompterPanelOriginY") != nil
        else { return nil }
        return CGPoint(
            x: defaults.double(forKey: "teleprompterPanelOriginX"),
            y: defaults.double(forKey: "teleprompterPanelOriginY")
        )
    }

    func resetTeleprompterPosition() {
        UserDefaults.standard.removeObject(forKey: "teleprompterPanelOriginX")
        UserDefaults.standard.removeObject(forKey: "teleprompterPanelOriginY")
        guard teleprompterPanel != nil else { return }
        applyTeleprompterFrame()
    }

    /// ⌥空格 暂停/继续、⌥↑/⌥↓ 调速。全局监听需要辅助功能授权；
    /// 未授权时只有本应用在前台生效，面板上的控件始终可用。
    private func installPrompterKeyMonitors() {
        removePrompterKeyMonitors()
        prompterKeyMonitors.append(
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                self?.handlePrompterKeyEvent(event) == true ? nil : event
            }
        )
        prompterKeyMonitors.append(
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                _ = self?.handlePrompterKeyEvent(event)
            }
        )
    }

    private func removePrompterKeyMonitors() {
        prompterKeyMonitors.forEach { NSEvent.removeMonitor($0) }
        prompterKeyMonitors.removeAll()
    }

    private func handlePrompterKeyEvent(_ event: NSEvent) -> Bool {
        guard let store,
              store.isRecording,
              event.modifierFlags.contains(.option),
              !event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.control) else {
            return false
        }
        switch event.keyCode {
        case 49:
            store.prompterPaused.toggle()
            return true
        case 126:
            store.prompterSpeed = min(2.5, store.prompterSpeed + 0.25)
            return true
        case 125:
            store.prompterSpeed = max(0.5, store.prompterSpeed - 0.25)
            return true
        default:
            return false
        }
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

    func updateDrawingOverlay(frame: CGRect, visible: Bool) {
        guard visible, frame.width > 1, frame.height > 1, let store else {
            drawingPanel?.orderOut(nil)
            return
        }
        if drawingPanel == nil {
            let drawingView = RecordingDrawingView(store: store)
            let panel = RecordingDrawingPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = drawingView
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            drawingPanel = panel
        }
        let mainDisplayHeight = NSScreen.screens.first(where: {
            ($0.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber)?.uint32Value == CGMainDisplayID()
        })?.frame.height ?? NSScreen.screens.first?.frame.height ?? frame.height
        let appKitFrame = RecordingHighlightGeometry.appKitFrame(
            forQuartzFrame: frame,
            mainDisplayHeight: mainDisplayHeight
        )
        drawingPanel?.setFrame(appKitFrame, display: true)
        drawingPanel?.orderFrontRegardless()
        updateDrawingInteraction()
    }

    func updateDrawingInteraction() {
        drawingPanel?.ignoresMouseEvents = (store?.recordingDrawingTool == nil)
    }

    private func screen(for displayID: UInt32?) -> NSScreen? {
        guard let displayID else { return nil }
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == displayID
        }
    }
}

struct RecordingTeleprompterPresentation {
    static let defaultPanelSize = CGSize(width: 560, height: 190)
    static let minPanelSize = CGSize(width: 320, height: 120)
    static let maxPanelSize = CGSize(width: 1000, height: 600)

    /// 有稿即显示：空白稿件不弹面板，没有独立开关（ADR 0002）。
    static func shouldShow(text: String) -> Bool {
        !text.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    static func clamped(size: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, minPanelSize.width), maxPanelSize.width),
            height: min(max(size.height, minPanelSize.height), maxPanelSize.height)
        )
    }

    /// 无记忆位置时底部居中（距底 24pt）；有记忆位置时钳制在可视区内。
    static func frame(
        in visibleFrame: CGRect,
        size: CGSize,
        savedOrigin: CGPoint? = nil
    ) -> CGRect {
        let clampedSize = clamped(size: size)
        let origin: CGPoint
        if let savedOrigin {
            origin = clamped(
                origin: savedOrigin,
                in: visibleFrame,
                size: clampedSize
            )
        } else {
            origin = CGPoint(
                x: visibleFrame.midX - clampedSize.width / 2,
                y: visibleFrame.minY + 24
            )
        }
        return CGRect(origin: origin, size: clampedSize)
    }

    static func clamped(
        origin: CGPoint,
        in visibleFrame: CGRect,
        size: CGSize
    ) -> CGPoint {
        CGPoint(
            x: min(
                max(origin.x, visibleFrame.minX),
                visibleFrame.maxX - size.width
            ),
            y: min(
                max(origin.y, visibleFrame.minY),
                visibleFrame.maxY - size.height
            )
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

/// 记住用户拖出的提词器位置；录制中拖动面板 = 手动接管（ADR 0002）。
private final class TeleprompterPanelDelegate: NSObject, NSWindowDelegate {
    var onFrameChange: ((NSPanel) -> Void)?
    var onMove: ((NSPanel) -> Void)?

    func windowDidChangeFrame(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        onFrameChange?(panel)
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        onMove?(panel)
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

private final class RecordingDrawingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

/// A transparent click-through canvas over the recorded area. While a drawing
/// tool is armed it captures one drag (a single stroke), then returns to
/// click-through on mouse-up. It renders the in-progress draft and any
/// annotation still inside its fade window so the user sees exactly what will
/// be composited into the output.
private final class RecordingDrawingView: NSView {
    weak var store: EditorStore?

    private var draftKind: AnnotationKind?
    private var draftStart: NormalizedPoint?
    private var draftEnd: NormalizedPoint?
    private var draftPoints: [NormalizedPoint] = []
    private var strokeBeganAt: TimeInterval?
    private var fadeTimer: Timer?

    init(store: EditorStore) {
        self.store = store
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard fadeTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) {
            [weak self] _ in
            self?.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    deinit {
        fadeTimer?.invalidate()
    }

    override func mouseDown(with event: NSEvent) {
        guard let store, let kind = store.recordingDrawingTool,
              let point = store.normalizedDrawingPoint() else {
            return
        }
        draftKind = kind
        draftStart = point
        draftEnd = point
        draftPoints = [point]
        strokeBeganAt = store.currentRecordingElapsed
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let store, draftKind != nil,
              let point = store.normalizedDrawingPoint() else {
            return
        }
        if draftKind == .brush {
            draftPoints.append(point)
        } else {
            draftEnd = point
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let store, let kind = draftKind else { return }
        let start = draftStart
            ?? store.normalizedDrawingPoint()
            ?? NormalizedPoint(x: 0.5, y: 0.5)
        let end = draftEnd ?? start
        let beganAt = strokeBeganAt ?? store.currentRecordingElapsed
        store.commitRecordingAnnotation(
            kind: kind,
            points: kind == .brush ? draftPoints : [],
            start: start,
            end: end,
            strokeBeganAt: beganAt,
            strokeEndedAt: store.currentRecordingElapsed
        )
        resetDraft()
        store.recordingDrawingTool = nil
        needsDisplay = true
    }

    private func resetDraft() {
        draftKind = nil
        draftStart = nil
        draftEnd = nil
        draftPoints = []
        strokeBeganAt = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let store,
              let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        context.clear(bounds)

        let now = store.recordingElapsed
        for annotation in store.project.annotations {
            guard now >= annotation.start, now <= annotation.end else {
                continue
            }
            stroke(
                annotation,
                progress: annotation.drawProgress(atSourceTime: now),
                in: context
            )
        }

        if let kind = draftKind {
            stroke(
                Annotation(
                    kind: kind,
                    start: now,
                    points: kind == .brush ? draftPoints : [],
                    normalizedStartX: draftStart?.x ?? 0,
                    normalizedStartY: draftStart?.y ?? 0,
                    normalizedEndX: draftEnd?.x ?? draftStart?.x ?? 0,
                    normalizedEndY: draftEnd?.y ?? draftStart?.y ?? 0,
                    lineWidth: store.recordingAnnotationLineWidth,
                    color: store.recordingAnnotationColor
                ),
                in: context
            )
        }
    }

    private func stroke(
        _ annotation: Annotation,
        progress: Double = 1,
        in context: CGContext
    ) {
        let path = annotationCGPath(for: annotation, progress: progress) {
            x, y in
            CGPoint(x: bounds.width * x, y: bounds.height * y)
        }
        context.saveGState()
        context.setStrokeColor(annotation.color.nsColor.cgColor)
        context.setLineWidth(annotation.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setShadow(
            offset: .zero,
            blur: 2,
            color: NSColor.black.withAlphaComponent(0.7).cgColor
        )
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }
}

private final class RecordingTeleprompterPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

/// 录制中的提词器：按 `prompterSpeed` 自动滚动稿件，当前段高亮。
/// 暂停/调速/字号/重置位置都在面板控件行上，⌥ 快捷键是增强路径。
private struct RecordingTeleprompterView: View {
    @ObservedObject var store: EditorStore
    @State private var scrollProgress: Double = 0
    @State private var resizeBase: CGSize?
    @State private var isHovering = false
    // 录制期间光标采样与录制计时以 10–30 Hz 重建本视图；实例属性的 timer
    // 每次重建都会被换成新发布者，且在首次触发（0.1s）前就被下一次重建
    // 替换——自动滚动因此永远不启动。static 让发布者身份稳定，重订阅
    // 不会重置计时。
    private static let tick = Timer.publish(
        every: 0.1,
        on: .main,
        in: .common
    ).autoconnect()

    private var paragraphs: [String] {
        store.scriptText
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var currentIndex: Int {
        let count = max(paragraphs.count, 1)
        return min(Int(scrollProgress * Double(count)), count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controlsRow

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(
                            Array(paragraphs.enumerated()),
                            id: \.offset
                        ) { index, paragraph in
                            Text(paragraph)
                                .font(
                                    .system(
                                        size: store.prompterFontSize,
                                        weight: .medium
                                    )
                                )
                                .foregroundStyle(
                                    index == currentIndex
                                        ? .white
                                        : .white.opacity(0.42)
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.disabled)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
                .onReceive(Self.tick) { _ in
                    advanceAutoScroll()
                    guard !store.prompterPaused,
                          !store.isRecordingPaused,
                          !paragraphs.isEmpty else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(currentIndex, anchor: .top)
                    }
                }
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.08),
                        .init(color: .black, location: 0.92),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .padding(14)
        .frame(
            width: store.teleprompterPanelSize.width,
            height: store.teleprompterPanelSize.height
        )
        .background(
            .black.opacity(0.84),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            resizeGrabber
        }
        .onAppear {
            scrollProgress = 0
        }
        .onHover { isHovering = $0 }
    }

    private func advanceAutoScroll() {
        guard store.isRecording,
              !store.isRecordingPaused,
              !store.prompterPaused,
              !paragraphs.isEmpty else { return }
        scrollProgress = min(
            1,
            scrollProgress + 0.008 * store.prompterSpeed
        )
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            Label("Teleprompter", systemImage: "text.bubble")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(String(format: "×%.2f", store.prompterSpeed))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            controlButton(
                symbol: store.prompterPaused ? "play.fill" : "pause.fill",
                help: store.prompterPaused
                    ? "Resume scrolling"
                    : "Pause scrolling"
            ) {
                store.prompterPaused.toggle()
            }
            controlButton(symbol: "tortoise", help: "Scroll slower") {
                store.prompterSpeed = max(0.5, store.prompterSpeed - 0.25)
            }
            controlButton(symbol: "hare", help: "Scroll faster") {
                store.prompterSpeed = min(2.5, store.prompterSpeed + 0.25)
            }
            controlButton(symbol: "textformat.smaller", help: "Smaller text") {
                store.prompterFontSize = max(16, store.prompterFontSize - 2)
            }
            controlButton(symbol: "textformat.larger", help: "Larger text") {
                store.prompterFontSize = min(48, store.prompterFontSize + 2)
            }
            controlButton(
                symbol: "scope",
                help: "Reset teleprompter position"
            ) {
                store.resetTeleprompterPosition()
            }
        }
        .opacity(isHovering ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }

    private func controlButton(
        symbol: String,
        help: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(help))
    }

    private var resizeGrabber: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.55))
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .padding(3)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let base = resizeBase ?? store.teleprompterPanelSize
                        resizeBase = base
                        store.teleprompterPanelSize =
                            RecordingTeleprompterPresentation.clamped(
                                size: CGSize(
                                    width: base.width + value.translation.width,
                                    height: base.height + value.translation.height
                                )
                            )
                    }
                    .onEnded { _ in resizeBase = nil }
            )
            .help(Text("Drag to resize"))
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
        VStack(spacing: 8) {
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

            if store.isRecording, !store.isRecordingPaused {
                Divider().opacity(0.25)
                drawingToolbar
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 640, height: 110)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var drawingToolbar: some View {
        HStack(spacing: 8) {
            drawingToolButton(.brush, symbol: "scribble", help: "Brush")
            drawingToolButton(.rectangle, symbol: "rectangle", help: "Rectangle")
            drawingToolButton(.ellipse, symbol: "oval", help: "Ellipse")
            drawingToolButton(.arrow, symbol: "arrow.right", help: "Arrow")
            drawingToolButton(.line, symbol: "line.diagonal", help: "Line")

            Spacer(minLength: 6)

            ForEach(Array(AnnotationColor.palette.enumerated()), id: \.offset) {
                index, color in
                Button {
                    store.recordingAnnotationColor = color
                } label: {
                    Circle()
                        .fill(color.swiftUIColor)
                        .frame(width: 16, height: 16)
                        .overlay {
                            Circle().stroke(
                                store.recordingAnnotationColor == color
                                    ? Color.white
                                    : Color.white.opacity(0.25),
                                lineWidth: store.recordingAnnotationColor == color
                                    ? 2 : 1
                            )
                        }
                }
                .buttonStyle(.borderless)
                .help("Annotation color")
            }

            ForEach(Array(recordingWidthPresets.enumerated()), id: \.offset) {
                index, preset in
                Button {
                    store.recordingAnnotationLineWidth = preset.width
                } label: {
                    Capsule()
                        .fill(
                            store.recordingAnnotationLineWidth == preset.width
                                ? Color.white
                                : Color.white.opacity(0.55)
                        )
                        .frame(width: 18, height: preset.capsuleHeight)
                }
                .buttonStyle(.borderless)
                .help("Line width")
            }

            Button {
                store.undoLastRecordingAnnotation()
            } label: {
                Label("Undo annotation", systemImage: "arrow.uturn.backward")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Undo last annotation")

            Button {
                store.clearRecordingAnnotations()
            } label: {
                Label("Clear annotations", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Clear annotations")
        }
    }

    private func drawingToolButton(
        _ kind: AnnotationKind,
        symbol: String,
        help: LocalizedStringKey
    ) -> some View {
        let armed = store.recordingDrawingTool == kind
        return Button {
            store.toggleRecordingDrawingTool(kind)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(armed ? Color.black : Color.primary)
                .frame(width: 26, height: 26)
                .background(
                    armed ? Color.white : Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 7)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var recordingWidthPresets: [(width: CGFloat, capsuleHeight: CGFloat)] {
        [(3, 2), (5, 3.5), (9, 5.5)]
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
