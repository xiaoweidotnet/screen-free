import AppKit
import AVKit
import ScreenFreeCore
import SwiftUI

struct MainView: View {
    @ObservedObject var store: EditorStore
    @State private var showCanvasSizePicker = false
    @State private var showRecordingHistory = false
    @State private var historySelectionMode = false
    @State private var historySelection: Set<String> = []
    @State private var historyPendingDeletion: [RecordingHistoryItem] = []
    @State private var showHistoryDeleteConfirmation = false
    @AppStorage("showPanelRail") private var showPanelRail = true
    @AppStorage("showInspector") private var showInspector = true
    @State private var isPreviewFullscreen = false
    @State private var previewOwnsNativeFullscreen = false
    @State private var annotationDragStart: CGPoint?
    @State private var annotationDragEnd: CGPoint?

    var body: some View {
        Group {
            if isPreviewFullscreen {
                fullscreenPreview
            } else {
                workstation
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $store.isExportSheetPresented) {
            ExportSheet(store: store)
                .environment(\.locale, store.appLanguage.locale)
        }
        .sheet(isPresented: $store.isMicrophoneSelectionPresented) {
            MicrophoneSelectionSheet(store: store)
                .environment(\.locale, store.appLanguage.locale)
        }
        .alert(
            "ScreenFree",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.localizedErrorMessage ?? "")
        }
        .onDeleteCommand {
            store.deleteCurrentSelection()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .screenFreeEscapePressed
            )
        ) { notification in
            guard let context =
                notification.object as? ScreenFreeKeyEventContext else {
                return
            }
            if isPreviewFullscreen {
                exitPreviewFullscreen()
                context.isHandled = true
            } else if store.handleEscape() {
                context.isHandled = true
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .screenFreeDeletePressed
            )
        ) { notification in
            guard let context =
                notification.object as? ScreenFreeKeyEventContext else {
                return
            }
            context.isHandled = store.handleDeleteKey()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .screenFreeUndoPressed
            )
        ) { notification in
            guard let context =
                notification.object as? ScreenFreeKeyEventContext,
                  store.canUndoTimelineEdit else {
                return
            }
            store.undoTimelineEdit()
            context.isHandled = true
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .screenFreeRedoPressed
            )
        ) { notification in
            guard let context =
                notification.object as? ScreenFreeKeyEventContext,
                  store.canRedoTimelineEdit else {
                return
            }
            store.redoTimelineEdit()
            context.isHandled = true
        }
    }

    private var workstation: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(.white.opacity(0.06))

            HStack(spacing: 0) {
                if showPanelRail {
                    panelRail
                    Divider().overlay(.white.opacity(0.06))
                }

                VStack(spacing: 0) {
                    preview
                    playbackBar
                    TimelineView(store: store)
                        .frame(height: 159)
                }

                if showInspector {
                    Divider().overlay(.white.opacity(0.06))
                    inspector
                        .frame(width: 292)
                }
            }
            .onChange(of: store.inspectorPanel) { _ in
                guard !showInspector else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    showInspector = true
                }
            }

            statusBar
        }
    }

    private var fullscreenPreview: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Text(store.formatted(store.playhead))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            .black.opacity(0.62),
                            in: Capsule()
                        )

                    Spacer()

                    Button {
                        exitPreviewFullscreen()
                    } label: {
                        Label(
                            "Exit full-screen preview",
                            systemImage: "arrow.down.right.and.arrow.up.left"
                        )
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 38, height: 34)
                        .background(
                            .black.opacity(0.62),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Exit full-screen preview (Esc)")
                }
                .padding(20)

                Spacer()

                Button {
                    store.togglePlayback()
                } label: {
                    Image(
                        systemName: store.isPlaying
                            ? "pause.circle.fill"
                            : "play.circle.fill"
                    )
                    .font(.system(size: 50))
                    .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 26)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showPanelRail.toggle()
                }
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(showPanelRail ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(Text("Toggle left panel"))

            HStack(spacing: 9) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("ScreenFree")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }

            Spacer()

            if let url = store.sourceURL {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Untitled recording")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Menu {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        store.appLanguage = language
                    } label: {
                        if store.appLanguage == language {
                            Label(language.displayName, systemImage: "checkmark")
                        } else {
                            Text(language.displayName)
                        }
                    }
                }
            } label: {
                Label(store.appLanguage.displayName, systemImage: "globe")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help("Language")

            Button {
                store.refreshRecordingHistory()
                showRecordingHistory.toggle()
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(ToolbarButtonStyle())
            .popover(
                isPresented: $showRecordingHistory,
                arrowEdge: .bottom
            ) {
                recordingHistoryPopover
            }

            Button {
                store.importVideo()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(ToolbarButtonStyle())

            Button {
                Task { await store.startOrStopRecording() }
            } label: {
                Label {
                    Text(
                        LocalizedStringKey(
                            store.isRecording || store.isPreparingRecording
                                ? "Stop"
                                : "Record"
                        )
                    )
                } icon: {
                    Image(
                        systemName: store.isRecording || store.isPreparingRecording
                            ? "stop.fill"
                            : "record.circle"
                    )
                }
            }
            .buttonStyle(
                AccentButtonStyle(
                    colors: store.isRecording || store.isPreparingRecording
                        ? [.red, .orange]
                        : [.purple, .indigo]
                )
            )

            Button {
                store.presentExportSheet()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(AccentButtonStyle(colors: [.indigo, .blue]))
            .disabled(store.sourceURL == nil || store.isExporting)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showInspector.toggle()
                }
            } label: {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(showInspector ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(Text("Toggle right panel"))
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(.black.opacity(0.18))
    }

    private var panelRail: some View {
        VStack(spacing: 7) {
            ForEach(primaryRailPanels) { panel in
                Button {
                    selectInspectorPanel(panel)
                } label: {
                    railIcon(
                        symbol: panel.symbol,
                        selected: store.inspectorPanel == panel
                    )
                }
                .buttonStyle(.plain)
                .help(Text(LocalizedStringKey(panel.rawValue)))
            }

            Menu {
                ForEach(editingRailPanels) { panel in
                    Button {
                        selectInspectorPanel(panel)
                    } label: {
                        Label(
                            LocalizedStringKey(panel.rawValue),
                            systemImage: panel.symbol
                        )
                    }
                }
            } label: {
                railIcon(
                    symbol: editingRailPanels.contains(store.inspectorPanel)
                        ? store.inspectorPanel.symbol
                        : "slider.horizontal.3",
                    selected: editingRailPanels.contains(store.inspectorPanel)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Editing tools")

            Spacer()
        }
        .padding(.vertical, 12)
        .frame(width: 55)
        .background(.black.opacity(0.12))
    }

    private var primaryRailPanels: [EditorStore.InspectorPanel] {
        [.recording, .canvas, .cursor, .audio]
    }

    private func selectInspectorPanel(_ panel: EditorStore.InspectorPanel) {
        store.inspectorPanel = panel
        if !showInspector {
            withAnimation(.easeInOut(duration: 0.2)) {
                showInspector = true
            }
        }
    }

    private var editingRailPanels: [EditorStore.InspectorPanel] {
        [.camera, .captions, .clip, .zoom, .transition]
    }

    private func railIcon(symbol: String, selected: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(selected ? .white : .secondary)
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(
                        selected
                            ? Color.purple.opacity(0.78)
                            : Color.clear
                    )
            }
    }

    private var preview: some View {
        GeometryReader { geometry in
            let zoomState = store.activeZoomMotion()
            let zoom = zoomState?.zoom
            let scale = zoomState?.scale ?? 1
            let cursor = store.project.cursorSample(
                atTimelineTime: store.playhead,
                freezeBeforeEnd: store.cursorTailFreeze,
                loopToStart: store.cursorLoopToStart,
                removeShakes: store.removeCursorShakes,
                shakeThreshold: store.cursorShakeThreshold,
                optimizeRapidChanges: store.optimizeRapidCursorChanges,
                smoothMovement: store.smoothCursorMovement
            )
            let followsCursor = zoom?.resolvedFollowsCursor == true
            let focusX = followsCursor
                ? cursor?.normalizedX ?? zoom?.focusX ?? 0.5
                : zoomState?.focusX ?? zoom?.focusX ?? 0.5
            let focusY = followsCursor
                ? cursor?.normalizedY ?? zoom?.focusY ?? 0.5
                : zoomState?.focusY ?? zoom?.focusY ?? 0.5
            let canvasSize = store.canvasAspectRatio.previewSize(
                in: geometry.size,
                sourceAspectRatio: store.sourceAspectRatio
            )
            let cropGeometry = CanvasCropGeometry(
                sourceSize: CGSize(
                    width: store.sourceAspectRatio * 1_000,
                    height: 1_000
                ),
                aspectRatio: store.canvasAspectRatio,
                contentMode: store.canvasContentMode
            )
            let mappedFocus = cropGeometry.clampedNormalizedOutputPoint(
                x: focusX,
                y: focusY
            )
            let click = store.activeClick()
            let shortcut = store.activeShortcut()
            let caption = store.activeCaption()
            let redactions = store.activeRedactions()
            let annotations = store.activeAnnotations()
            let contentSize = CGSize(
                width: max(1, canvasSize.width - store.canvasPadding * 2),
                height: max(1, canvasSize.height - store.canvasPadding * 2)
            )
            let cameraWidth = min(
                canvasSize.width * store.cameraSize,
                canvasSize.width * 0.5
            )
            let motionBlur = store.resolvedMotionBlur(
                renderSize: contentSize
            )
            let transitionFrame = store.transitionFrame(at: store.playhead)

            ZStack {
                CanvasBackgroundView(store: store)

                if store.sourceURL != nil {
                    NativePlayerView(
                        player: store.player,
                        videoGravity: store.canvasContentMode == .fit
                            ? .resizeAspect
                            : .resizeAspectFill
                    )
                        .disabled(true)
                        .scaleEffect(
                            scale * transitionFrame.contentScale,
                            anchor: UnitPoint(
                                x: mappedFocus.x,
                                y: mappedFocus.y
                            )
                        )
                        .blur(radius: motionBlur.screenRadius)
                        .clipShape(RoundedRectangle(cornerRadius: store.cornerRadius))
                        .shadow(
                            color: .black.opacity(store.shadowStrength),
                            radius: 28,
                            y: 18
                        )
                        .padding(store.canvasPadding)
                        .overlay(alignment: store.cameraPosition.alignment) {
                            if store.cameraURL != nil {
                                NativePlayerView(player: store.cameraPlayer)
                                    .disabled(true)
                                    .scaleEffect(
                                        x: store.cameraMirrored ? -1 : 1,
                                        y: 1
                                    )
                                    .frame(
                                        width: cameraWidth,
                                        height: cameraWidth * 0.625
                                    )
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: store.cameraCornerRadius
                                        )
                                    )
                                    .overlay {
                                        RoundedRectangle(
                                            cornerRadius: store.cameraCornerRadius
                                        )
                                            .stroke(.white.opacity(0.72), lineWidth: 2)
                                    }
                                    .shadow(color: .black.opacity(0.55), radius: 14, y: 7)
                                    .padding(store.canvasPadding + 16)
                            }
                        }
                        .overlay {
                            if transitionFrame.dipOpacity > 0.001 {
                                RoundedRectangle(
                                    cornerRadius: store.cornerRadius
                                )
                                    .fill(
                                        transitionFrame.dipIsWhite
                                            ? Color.white : Color.black
                                    )
                                    .padding(store.canvasPadding)
                                    .opacity(transitionFrame.dipOpacity)
                                    .allowsHitTesting(false)
                            }
                        }
                        .overlay {
                            ZStack {
                                if let shortcut {
                                    VStack {
                                        Text(shortcut.label)
                                            .font(
                                                .system(
                                                    size: 20,
                                                    weight: .semibold,
                                                    design: .rounded
                                                )
                                            )
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 9)
                                            .background(
                                                .black.opacity(0.76),
                                                in: RoundedRectangle(
                                                    cornerRadius: 12
                                                )
                                            )
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(
                                                        .white.opacity(0.16),
                                                        lineWidth: 1
                                                    )
                                            }
                                            .padding(
                                                .top,
                                                store.canvasPadding + 24
                                            )
                                        Spacer()
                                    }
                                }

                                if let caption {
                                    VStack {
                                        Spacer()
                                        Text(caption.text)
                                            .font(
                                                .system(
                                                    size: store.captionFontSize,
                                                    weight: .semibold
                                                )
                                            )
                                            .multilineTextAlignment(.center)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 18)
                                            .padding(.vertical, 10)
                                            .background(
                                                .black.opacity(0.72),
                                                in: RoundedRectangle(cornerRadius: 14)
                                            )
                                            .frame(maxWidth: contentSize.width * 0.76)
                                            .padding(.bottom, store.canvasPadding + 24)
                                    }
                                }

                                if let click,
                                   store.clickEffectPreset != .none,
                                   cropGeometry.containsSourcePoint(
                                       x: click.click.normalizedX,
                                       y: click.click.normalizedY
                                   ) {
                                    let mappedClick = cropGeometry
                                        .normalizedOutputPoint(
                                            x: click.click.normalizedX,
                                            y: click.click.normalizedY
                                        )
                                    Group {
                                        switch store.clickEffectPreset {
                                        case .none:
                                            EmptyView()
                                        case .circle:
                                            Circle()
                                                .fill(
                                                    .white.opacity(
                                                        0.62 * (1 - click.progress)
                                                    )
                                                )
                                                .scaleEffect(
                                                    1 - click.progress * 0.38
                                                )
                                        case .ripple:
                                            Circle()
                                                .stroke(
                                                    .white.opacity(1 - click.progress),
                                                    lineWidth: 2.5
                                                )
                                                .scaleEffect(
                                                    0.4 + click.progress * 1.5
                                                )
                                        case .rotation:
                                            Circle()
                                                .trim(from: 0.08, to: 0.82)
                                                .stroke(
                                                    .white.opacity(1 - click.progress),
                                                    style: StrokeStyle(
                                                        lineWidth: 2.5,
                                                        lineCap: .round,
                                                        dash: [7, 4]
                                                    )
                                                )
                                                .rotationEffect(
                                                    .degrees(click.progress * 300)
                                                )
                                                .scaleEffect(
                                                    0.72 + click.progress * 0.6
                                                )
                                        }
                                    }
                                        .frame(width: 28, height: 28)
                                        .position(
                                            x: store.canvasPadding
                                                + contentSize.width * mappedClick.x,
                                            y: store.canvasPadding
                                                + contentSize.height * mappedClick.y
                                        )
                                }

                                if let cursor,
                                   store.cursorIsVisible(),
                                   cropGeometry.containsSourcePoint(
                                       x: cursor.normalizedX,
                                       y: cursor.normalizedY
                                   ) {
                                    let mappedCursor = cropGeometry
                                        .normalizedOutputPoint(
                                            x: cursor.normalizedX,
                                            y: cursor.normalizedY
                                        )
                                    let cursorSize = CursorArtwork.size(
                                        for: store.cursorReplacement
                                    )
                                    let cursorHotspot = CursorArtwork.hotspot(
                                        for: store.cursorReplacement
                                    )
                                    let renderedWidth = cursorSize.width
                                        * store.cursorSize
                                    let renderedHeight = cursorSize.height
                                        * store.cursorSize
                                    Image(
                                        nsImage: CursorArtwork.image(
                                            for: store.cursorReplacement
                                        )
                                    )
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(
                                            width: renderedWidth,
                                            height: renderedHeight
                                        )
                                        .blur(radius: motionBlur.cursorRadius)
                                        .shadow(color: .black, radius: 1.5, x: 1, y: 1)
                                        .position(
                                            x: store.canvasPadding
                                                + contentSize.width * mappedCursor.x
                                                + renderedWidth
                                                    * (0.5 - cursorHotspot.x),
                                            y: store.canvasPadding
                                                + contentSize.height * mappedCursor.y
                                                + renderedHeight
                                                    * (0.5 - cursorHotspot.y)
                                        )
                                }

                                ForEach(redactions) { redaction in
                                    if redaction.resolvedPresentation == .spotlight {
                                        SpotlightOverlay(
                                            region: redaction,
                                            selected: redaction.id
                                                == store.selectedRedactionID
                                                && store.inspectorPanel == .privacy
                                        )
                                        .frame(
                                            width: contentSize.width,
                                            height: contentSize.height
                                        )
                                        .position(
                                            x: store.canvasPadding
                                                + contentSize.width / 2,
                                            y: store.canvasPadding
                                                + contentSize.height / 2
                                        )
                                    } else {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(
                                                .black.opacity(redaction.opacity)
                                            )
                                            .overlay {
                                                if redaction.id
                                                    == store.selectedRedactionID,
                                                   store.inspectorPanel == .privacy {
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(
                                                            .red.opacity(0.95),
                                                            style: StrokeStyle(
                                                                lineWidth: 2,
                                                                dash: [6, 4]
                                                            )
                                                        )
                                                }
                                            }
                                            .frame(
                                                width: contentSize.width
                                                    * redaction.normalizedWidth,
                                                height: contentSize.height
                                                    * redaction.normalizedHeight
                                            )
                                            .position(
                                                x: store.canvasPadding
                                                    + contentSize.width
                                                        * redaction.normalizedX,
                                                y: store.canvasPadding
                                                    + contentSize.height
                                                        * redaction.normalizedY
                                            )
                                    }
                                }

                                ForEach(annotations) { annotation in
                                    EmphasisAnnotationOverlay(
                                        annotation: annotation,
                                        selected: annotation.id
                                            == store.selectedAnnotationID
                                    )
                                    .frame(
                                        width: contentSize.width,
                                        height: contentSize.height
                                    )
                                    .position(
                                        x: store.canvasPadding
                                            + contentSize.width / 2,
                                        y: store.canvasPadding
                                            + contentSize.height / 2
                                    )
                                }

                                if let annotationDragStart,
                                   let annotationDragEnd,
                                   case let .annotation(kind)
                                        = store.activeTimelineTool {
                                    EmphasisAnnotationOverlay(
                                        annotation: EmphasisAnnotation(
                                            kind: kind,
                                            start: store.playhead,
                                            normalizedStartX: annotationDragStart.x,
                                            normalizedStartY: annotationDragStart.y,
                                            normalizedEndX: annotationDragEnd.x,
                                            normalizedEndY: annotationDragEnd.y
                                        ),
                                        selected: true
                                    )
                                    .frame(
                                        width: contentSize.width,
                                        height: contentSize.height
                                    )
                                    .position(
                                        x: store.canvasPadding
                                            + contentSize.width / 2,
                                        y: store.canvasPadding
                                            + contentSize.height / 2
                                    )
                                }

                                if let zoom,
                                   store.inspectorPanel == .zoom,
                                   zoom.id == store.selectedZoomID {
                                    let mappedZoom = cropGeometry
                                        .clampedNormalizedOutputPoint(
                                            x: zoom.focusX,
                                            y: zoom.focusY
                                        )
                                    FocusReticle()
                                        .position(
                                            x: store.canvasPadding
                                                + contentSize.width * mappedZoom.x,
                                            y: store.canvasPadding
                                                + contentSize.height * mappedZoom.y
                                        )
                                }
                            }
                            .allowsHitTesting(false)
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let outputX = (
                                        (value.location.x - store.canvasPadding)
                                        / contentSize.width
                                    ).clamped(to: 0...1)
                                    let outputY = (
                                        (value.location.y - store.canvasPadding)
                                        / contentSize.height
                                    ).clamped(to: 0...1)
                                    if case .annotation = store.activeTimelineTool {
                                        let point = CGPoint(
                                            x: outputX,
                                            y: outputY
                                        )
                                        if annotationDragStart == nil {
                                            annotationDragStart = point
                                        }
                                        annotationDragEnd = point
                                    } else if store.inspectorPanel == .privacy,
                                       store.selectedRedactionID != nil {
                                        store.beginContinuousTimelineEdit(
                                            .redaction
                                        )
                                        store.moveSelectedRedaction(
                                            x: outputX,
                                            y: outputY
                                        )
                                    } else if store.inspectorPanel == .zoom,
                                              store.selectedZoomID != nil {
                                        store.beginContinuousTimelineEdit(.zoom)
                                        let sourcePoint = cropGeometry
                                            .sourceNormalizedPoint(
                                                outputX: outputX,
                                                outputY: outputY
                                            )
                                        store.moveSelectedZoomFocus(
                                            x: sourcePoint.x,
                                            y: sourcePoint.y
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    guard case let .annotation(kind)
                                        = store.activeTimelineTool else {
                                        store.endContinuousTimelineEdit()
                                        annotationDragStart = nil
                                        annotationDragEnd = nil
                                        return
                                    }
                                    guard let start = annotationDragStart,
                                          let end = annotationDragEnd else {
                                        annotationDragStart = nil
                                        annotationDragEnd = nil
                                        return
                                    }
                                    if hypot(
                                        end.x - start.x,
                                        end.y - start.y
                                    ) >= 0.025 {
                                        store.addAnnotation(
                                            kind: kind,
                                            startPoint: start,
                                            endPoint: end
                                        )
                                    }
                                    annotationDragStart = nil
                                    annotationDragEnd = nil
                                }
                        )
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "rectangle.dashed.badge.record")
                            .font(.system(size: 54, weight: .thin))
                            .foregroundStyle(.white.opacity(0.75))
                        Text(
                            LocalizedStringKey(
                                store.isRecording
                                    ? "Recording your screen…"
                                    : "Ready to make something clear"
                            )
                        )
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                        Text(
                            LocalizedStringKey(
                                store.isRecording
                                ? "Move and click the mouse — ScreenFree is capturing the cursor path."
                                : "Record a display, window, or area. You can also import an existing video."
                            )
                        )
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)

                        if !store.isRecording {
                            Button {
                                Task { await store.startOrStopRecording() }
                            } label: {
                                Label("Start Recording", systemImage: "record.circle")
                                    .padding(.horizontal, 4)
                            }
                            .buttonStyle(AccentButtonStyle(colors: [.purple, .indigo]))
                        }
                    }
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipShape(Rectangle())
            .position(
                x: geometry.size.width / 2,
                y: geometry.size.height / 2
            )
        }
        .frame(minHeight: 360)
        .background(.black)
    }

    private var playbackBar: some View {
        HStack(spacing: 14) {
            Button {
                store.stepFrame(-1)
            } label: {
                Image(systemName: "backward.frame.fill")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.leftArrow, modifiers: [])
            .help("Previous frame")

            Button {
                store.togglePlayback()
            } label: {
                Image(systemName: store.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 27))
            }
            .buttonStyle(.plain)

            Button {
                store.stepFrame(1)
            } label: {
                Image(systemName: "forward.frame.fill")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.rightArrow, modifiers: [])
            .help("Next frame")

            Text(store.formatted(store.playhead))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                showCanvasSizePicker.toggle()
            } label: {
                Label(
                    LocalizedStringKey(store.canvasAspectRatio.displayTitle),
                    systemImage: "rectangle.ratio.16.to.9"
                )
            }
            .buttonStyle(ToolbarButtonStyle())
            .fixedSize()
            .disabled(store.sourceURL == nil)
            .popover(isPresented: $showCanvasSizePicker, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Canvas size")
                        .font(.headline)
                        .padding(.bottom, 4)
                    ForEach(CanvasAspectRatio.allCases) { ratio in
                        Button {
                            store.selectCanvasAspectRatio(ratio)
                            showCanvasSizePicker = false
                        } label: {
                            HStack {
                                Image(
                                    systemName: store.canvasAspectRatio == ratio
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                Text(LocalizedStringKey(ratio.displayTitle))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 5)
                    }
                }
                .padding(14)
                .frame(width: 210)
            }

            Button {
                store.canvasContentMode = store.canvasContentMode == .fit
                    ? .crop
                    : .fit
            } label: {
                Label(
                    store.canvasContentMode == .crop ? "Crop on" : "Fit",
                    systemImage: store.canvasContentMode == .crop
                        ? "crop"
                        : "arrow.down.right.and.arrow.up.left"
                )
                .labelStyle(.iconOnly)
            }
            .buttonStyle(ToolbarButtonStyle())
            .help(
                store.canvasContentMode == .crop
                    ? "Crop fills the canvas and may hide the edges."
                    : "Fit keeps the complete recording visible."
            )
            .disabled(store.sourceURL == nil)

            Button {
                enterPreviewFullscreen()
            } label: {
                Label(
                    "Full-screen preview",
                    systemImage: "arrow.up.left.and.arrow.down.right"
                )
                .labelStyle(.iconOnly)
            }
            .buttonStyle(ToolbarButtonStyle())
            .help("Full-screen preview")
            .disabled(store.sourceURL == nil)

            Button {
                store.toggleSplitTool()
            } label: {
                Label(
                    store.activeTimelineTool == .split
                        ? "Split mode"
                        : "Split",
                    systemImage: "scissors"
                )
            }
            .buttonStyle(ToolbarButtonStyle())
            .foregroundStyle(
                store.activeTimelineTool == .split
                    ? Color.orange
                    : Color.primary
            )
            .disabled(store.sourceURL == nil)

            Text(store.formatted(store.project.duration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .background(.black.opacity(0.26))
    }

    private var recordingHistoryPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Recording history", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                if !store.recordingHistory.isEmpty {
                    Button {
                        historySelectionMode.toggle()
                        if !historySelectionMode {
                            historySelection.removeAll()
                        }
                    } label: {
                        if historySelectionMode {
                            Text("Done")
                        } else {
                            Text("Select")
                        }
                    }
                    .buttonStyle(.borderless)
                }
                Button {
                    store.refreshRecordingHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh history")
            }

            Divider()

            if store.recordingHistory.isEmpty {
                ContentUnavailableView(
                    "No recordings yet",
                    systemImage: "film.stack",
                    description: Text(
                        "Finished recordings will appear here and can be opened for editing."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.recordingHistory) { item in
                            recordingHistoryRow(item)
                        }
                    }
                }
                if historySelectionMode {
                    Divider()
                    HStack {
                        Button {
                            if historySelection.count
                                == store.recordingHistory.count {
                                historySelection.removeAll()
                            } else {
                                historySelection = Set(
                                    store.recordingHistory.map(\.id)
                                )
                            }
                        } label: {
                            if historySelection.count
                                == store.recordingHistory.count {
                                Text("Deselect all")
                            } else {
                                Text("Select all")
                            }
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                        Button(role: .destructive) {
                            requestHistoryDeletion(
                                store.recordingHistory.filter {
                                    historySelection.contains($0.id)
                                }
                            )
                        } label: {
                            Text(
                                L10n.text(
                                    "Delete (%d)",
                                    language: store.appLanguage,
                                    historySelection.count
                                )
                            )
                        }
                        .disabled(historySelection.isEmpty)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 380, height: 420)
        .onAppear {
            store.refreshRecordingHistory()
        }
        .onDisappear {
            historySelectionMode = false
            historySelection.removeAll()
        }
        .alert(
            historyDeletionTitle,
            isPresented: $showHistoryDeleteConfirmation
        ) {
            Button(role: .destructive) {
                store.deleteRecordingsFromHistory(historyPendingDeletion)
                historySelection.subtract(
                    historyPendingDeletion.map(\.id)
                )
                historyPendingDeletion = []
            } label: {
                Text("Delete")
            }
            Button(role: .cancel) {
                historyPendingDeletion = []
            } label: {
                Text("Cancel")
            }
        } message: {
            Text(
                "The video file will be permanently deleted from your disk. This cannot be undone."
            )
        }
    }

    private var historyDeletionTitle: Text {
        if historyPendingDeletion.count > 1 {
            return Text(
                L10n.text(
                    "Delete %d recordings?",
                    language: store.appLanguage,
                    historyPendingDeletion.count
                )
            )
        }
        return Text("Delete this recording?")
    }

    private func toggleHistorySelection(_ item: RecordingHistoryItem) {
        if historySelection.contains(item.id) {
            historySelection.remove(item.id)
        } else {
            historySelection.insert(item.id)
        }
    }

    private func requestHistoryDeletion(_ items: [RecordingHistoryItem]) {
        guard !items.isEmpty else { return }
        historyPendingDeletion = items
        showHistoryDeleteConfirmation = true
    }

    private func recordingHistoryRow(
        _ item: RecordingHistoryItem
    ) -> some View {
        Button {
            if historySelectionMode {
                toggleHistorySelection(item)
            } else {
                showRecordingHistory = false
                Task { await store.openRecordingFromHistory(item) }
            }
        } label: {
            HStack(spacing: 11) {
                if historySelectionMode {
                    Image(
                        systemName: historySelection.contains(item.id)
                            ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.system(size: 16))
                    .foregroundStyle(
                        historySelection.contains(item.id)
                            ? Color.accentColor : Color.secondary
                    )
                }

                Image(systemName: "film.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.purple)
                    .frame(width: 28, height: 28)
                    .background(
                        Color.purple.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 7)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(
                        "\(item.modifiedAt.formatted(date: .abbreviated, time: .shortened)) · \(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer()
                if !historySelectionMode {
                    Button {
                        requestHistoryDeletion([item])
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Delete recording")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(9)
            .contentShape(Rectangle())
            .background(
                historySelectionMode && historySelection.contains(item.id)
                    ? Color.accentColor.opacity(0.18)
                    : Color.white.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                showRecordingHistory = false
                Task { await store.openRecordingFromHistory(item) }
            } label: {
                Label("Open in editor", systemImage: "scissors")
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            Divider()
            Button(role: .destructive) {
                requestHistoryDeletion([item])
            } label: {
                Label("Delete recording", systemImage: "trash")
            }
        }
    }

    private func enterPreviewFullscreen() {
        guard store.sourceURL != nil, !isPreviewFullscreen else { return }
        let window = NSApp.keyWindow
        previewOwnsNativeFullscreen =
            window?.styleMask.contains(.fullScreen) == false
        isPreviewFullscreen = true
        if previewOwnsNativeFullscreen {
            window?.toggleFullScreen(nil)
        }
    }

    private func exitPreviewFullscreen() {
        guard isPreviewFullscreen else { return }
        let window = NSApp.keyWindow
        isPreviewFullscreen = false
        if previewOwnsNativeFullscreen,
           window?.styleMask.contains(.fullScreen) == true {
            window?.toggleFullScreen(nil)
        }
        previewOwnsNativeFullscreen = false
    }

    @ViewBuilder
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(
                    LocalizedStringKey(store.inspectorPanel.rawValue),
                    systemImage: store.inspectorPanel.symbol
                )
                    .font(.system(size: 15, weight: .semibold))

                Divider().overlay(.white.opacity(0.08))

                switch store.inspectorPanel {
                case .recording:
                    RecordingInspector(store: store)
                case .canvas:
                    CanvasInspector(store: store)
                case .cursor:
                    CursorInspector(store: store)
                case .audio:
                    AudioInspector(store: store)
                case .camera:
                    CameraInspector(store: store)
                case .captions:
                    CaptionsInspector(store: store)
                case .clip:
                    ClipInspector(store: store)
                case .zoom:
                    ZoomInspector(store: store)
                case .transition:
                    TransitionInspector(store: store)
                case .privacy:
                    PrivacyInspector(store: store)
                case .annotation:
                    AnnotationInspector(store: store)
                case .export:
                    ExportInspector(store: store)
                }
            }
            .padding(18)
        }
        .background(.black.opacity(0.12))
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.isRecording ? Color.red : Color.green)
                .frame(width: 7, height: 7)
            Text(store.localizedStatusMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(store.localizedTimelineSummary)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 27)
        .background(.black.opacity(0.28))
    }
}

private struct RecordingInspector: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        InspectorSection(title: "Capture source") {
            Picker("Mode", selection: $store.captureMode) {
                ForEach(CaptureMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: store.captureMode) {
                Task {
                    await store.refreshCaptureTargets()
                    if store.captureMode == .area {
                        store.selectRecordingArea()
                    }
                }
            }

            if store.captureMode == .window {
                Picker("Source", selection: $store.selectedTargetID) {
                    ForEach(store.captureTargets) { target in
                        Text(target.title).tag(Optional(target.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .disabled(store.capturePermissionIssue)
            } else {
                DisplayTargetPicker(store: store)
            }

            Button {
                Task { await store.refreshCaptureTargets() }
            } label: {
                Label("Refresh sources", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))

            if store.capturePermissionIssue {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        "Screen recording permission is off.",
                        systemImage: "exclamationmark.shield"
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)

                    HStack {
                        Button("Request permission") {
                            Task { await store.requestScreenRecordingPermission() }
                        }
                        Button("Open Settings") {
                            store.openScreenRecordingSettings()
                        }
                    }
                }
            }

            if store.captureMode == .area {
                Button {
                    store.selectRecordingArea()
                } label: {
                    Label("Select area…", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ToolbarButtonStyle())

                Text(
                    "\(Int(store.selectedAreaNormalized.width * 100))% × \(Int(store.selectedAreaNormalized.height * 100))%"
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

                Text("Choose Area, then drag directly on the screen to draw the capture rectangle.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }

        InspectorSection(title: "Recording") {
            Label("Screen and sound", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
            Text("System audio and microphone are enabled by default.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Picker("System audio", selection: $store.systemAudioMode) {
                ForEach(SystemAudioCaptureMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                }
            }
            .pickerStyle(.menu)

            if store.systemAudioMode == .all {
                Toggle(
                    "Boost quiet system audio safely",
                    isOn: $store.normalizeSystemAudioVolume
                )
                .toggleStyle(.switch)
                Text("Automatic gain is written into the recording and limited before clipping.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if store.systemAudioMode == .selected {
                if store.audioApplications.isEmpty {
                    Text("No recordable applications found.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 7) {
                            ForEach(store.audioApplications) { application in
                                Toggle(
                                    application.name,
                                    isOn: Binding(
                                        get: {
                                            store.selectedAudioApplicationIDs
                                                .contains(application.id)
                                        },
                                        set: { selected in
                                            if selected {
                                                store.selectedAudioApplicationIDs
                                                    .insert(application.id)
                                            } else {
                                                store.selectedAudioApplicationIDs
                                                    .remove(application.id)
                                            }
                                        }
                                    )
                                )
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .frame(maxHeight: 132)
                }

                HStack {
                    Text(
                        L10n.text(
                            "%d applications selected",
                            language: store.appLanguage,
                            store.selectedAudioApplicationIDs.count
                        )
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh applications") {
                        Task { await store.refreshAudioApplications() }
                    }
                    .font(.system(size: 10))
                }
            }

            Toggle("Microphone", isOn: $store.recordMicrophone)
                .toggleStyle(.switch)
            if store.recordMicrophone {
                Picker("Microphone", selection: $store.selectedMicrophoneID) {
                    Text("No microphone").tag(Optional<String>.none)
                    ForEach(store.deviceMonitor.microphones) { device in
                        Text(
                            device.name + (
                                device.isDefault
                                    ? L10n.text(
                                        " (default)",
                                        language: store.appLanguage
                                    )
                                    : ""
                            )
                        )
                            .tag(Optional(device.id))
                    }
                }
                .labelsHidden()
                MicrophoneMeterView(monitor: store.deviceMonitor)
                Toggle(
                    "Reduce microphone noise",
                    isOn: $store.reduceMicrophoneNoise
                )
                .toggleStyle(.switch)
                Toggle(
                    "Normalize microphone volume",
                    isOn: $store.normalizeMicrophoneVolume
                )
                .toggleStyle(.switch)
                Text("Microphone enhancement is written to its separate source track while recording.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Picker("Camera", selection: $store.selectedCameraID) {
                Text("No camera").tag(Optional<String>.none)
                ForEach(store.deviceMonitor.cameras) { device in
                    Text(
                        device.name + (
                            device.isDefault
                                ? L10n.text(
                                    " (default)",
                                    language: store.appLanguage
                                )
                                : ""
                        )
                    )
                        .tag(Optional(device.id))
                }
            }
            .labelsHidden()
            .onChange(of: store.selectedCameraID) {
                Task {
                    await store.deviceMonitor.showCameraPreview(
                        deviceID: store.selectedCameraID
                    )
                }
            }

            if store.selectedCameraID != nil {
                Toggle(
                    "Hide camera preview",
                    isOn: $store.hideCameraPreview
                )
                .toggleStyle(.switch)

                if RecordingCameraPreviewPresentation.shouldShow(
                    cameraSelected: true,
                    hidden: store.hideCameraPreview
                ) {
                    CameraPreviewView(session: store.deviceMonitor.cameraSession)
                        .frame(height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        }
                } else {
                    Label(
                        "Camera preview hidden; recording remains enabled.",
                        systemImage: "eye.slash"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }

            if let deviceError = store.deviceMonitor.deviceError {
                VStack(alignment: .leading, spacing: 7) {
                    Label(
                        L10n.text(deviceError, language: store.appLanguage),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)

                    HStack {
                        if store.recordMicrophone {
                            Button("Microphone Settings") {
                                store.openMicrophoneSettings()
                            }
                        }
                        if store.selectedCameraID != nil {
                            Button("Camera Settings") {
                                store.openCameraSettings()
                            }
                        }
                    }
                    .font(.system(size: 10))
                }
            }

            Picker("Countdown", selection: $store.countdownSeconds) {
                Text("None").tag(0)
                Text("3 seconds").tag(3)
                Text("5 seconds").tag(5)
                Text("10 seconds").tag(10)
            }

            Picker(
                "After recording",
                selection: $store.afterRecordingAction
            ) {
                ForEach(AfterRecordingAction.allCases) { action in
                    Text(LocalizedStringKey(action.rawValue)).tag(action)
                }
            }
            .pickerStyle(.menu)

            if store.afterRecordingAction != .edit {
                Text("Quick delivery uses the original screen recording. Choose Open editor to compose camera, zoom, cursor, and captions.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Toggle(
                "Highlight recorded area",
                isOn: $store.highlightRecordingArea
            )
            .toggleStyle(.switch)
            .onChange(of: store.highlightRecordingArea) {
                store.refreshRecordingHighlight()
            }

            Text("The recording border is excluded from the captured video.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Toggle(
                "Automatically create zooms",
                isOn: $store.automaticallyCreateZooms
            )
            .toggleStyle(.switch)

            Text("Click metadata is always kept, so automatic zooms can be regenerated later.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Toggle(
                "Hide Dock icon while recording",
                isOn: $store.hideDockIconWhileRecording
            )
            .toggleStyle(.switch)

            Text("The Dock icon is restored after stop, cancel, or recording failure.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            #if !APP_STORE
                Toggle(
                    "Hide desktop icons while recording",
                    isOn: $store.hideDesktopIconsWhileRecording
                )
                .toggleStyle(.switch)

                Text("Finder refreshes when recording starts and the exact prior desktop setting is restored afterward.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            #endif

            Toggle(
                "Show speaker notes while recording",
                isOn: $store.showSpeakerNotes
            )
            .toggleStyle(.switch)
            .onChange(of: store.showSpeakerNotes) {
                store.refreshSpeakerNotes()
            }

            if store.showSpeakerNotes {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $store.speakerNotesText)
                        .font(.system(size: 12))
                        .frame(minHeight: 86)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(
                            .black.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .onChange(of: store.speakerNotesText) {
                            store.refreshSpeakerNotes()
                        }
                    if store.speakerNotesText.isEmpty {
                        Text("Enter notes visible only to you…")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                Text("Speaker notes stay outside the captured video.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Text("ScreenFree captures the native display stream plus a separate 30 fps cursor path and click timeline.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button {
                Task { await store.startOrStopRecording() }
            } label: {
                Label(
                    store.isRecording ? "Stop and edit" : "Start recording",
                    systemImage: store.isRecording ? "stop.fill" : "record.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                AccentButtonStyle(
                    colors: store.isRecording || store.isPreparingRecording
                        ? [.red, .orange]
                        : [.purple, .indigo]
                )
            )
        }

        StudioCheckView(store: store)
    }
}

private struct DisplayTargetPicker: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Multiple displays")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(store.captureTargets.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.captureTargets) { target in
                        Button {
                            store.selectedTargetID = target.id
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(.black.opacity(0.45))
                                    if let image = store.captureThumbnails[target.id] {
                                        Image(nsImage: image)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Image(systemName: "display")
                                            .font(.system(size: 24, weight: .thin))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 120, height: 68)
                                .clipShape(RoundedRectangle(cornerRadius: 7))

                                HStack(spacing: 4) {
                                    Text(
                                        target.title.replacingOccurrences(
                                            of: "Display",
                                            with: L10n.text("Display", language: store.appLanguage)
                                        )
                                    )
                                        .lineLimit(1)
                                    if target.isPrimary {
                                        Text("Primary")
                                            .font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(.blue.opacity(0.3), in: Capsule())
                                    }
                                }
                                .font(.system(size: 9, weight: .medium))
                            }
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(
                                        store.selectedTargetID == target.id
                                            ? Color.purple.opacity(0.24)
                                            : Color.white.opacity(0.035)
                                    )
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        store.selectedTargetID == target.id
                                            ? Color.purple
                                            : Color.white.opacity(0.08),
                                        lineWidth: store.selectedTargetID == target.id ? 2 : 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Choose exactly which display to record. The controller is excluded from the capture.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

private struct MicrophoneSelectionSheet: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "mic.badge.plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose a microphone")
                        .font(.title2.weight(.semibold))
                    Text(
                        "Multiple microphones were detected. Choose the one to record before continuing."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            Picker(
                "Microphone",
                selection: $store.selectedMicrophoneID
            ) {
                ForEach(store.deviceMonitor.microphones) { device in
                    Text(
                        device.name + (
                            device.isDefault
                                ? L10n.text(
                                    " (default)",
                                    language: store.appLanguage
                                )
                                : ""
                        )
                    )
                    .tag(Optional(device.id))
                }
            }
            .pickerStyle(.radioGroup)

            Divider()

            HStack {
                Button("Cancel") {
                    store.isMicrophoneSelectionPresented = false
                }
                Spacer()
                Button {
                    Task {
                        await store.startRecording(
                            microphoneSelectionConfirmed: true
                        )
                    }
                } label: {
                    Label(
                        "Record with this microphone",
                        systemImage: "record.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(store.selectedMicrophoneID == nil)
            }
        }
        .padding(24)
        .frame(width: 470)
        .interactiveDismissDisabled()
    }
}

private struct MicrophoneMeterView: View {
    @ObservedObject var monitor: DeviceMonitor

    var signalLabel: LocalizedStringKey {
        switch monitor.audioSignalState {
        case .unavailable: return "Unavailable"
        case .silent: return "Silent"
        case .good: return "Good"
        case .clipping: return "Clipping"
        }
    }

    var signalColor: Color {
        switch monitor.audioSignalState {
        case .unavailable: return .secondary
        case .silent: return .orange
        case .good: return .green
        case .clipping: return .red
        }
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text("Audio level")
                    .font(.system(size: 11))
                Spacer()
                Text(signalLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(signalColor)
            }
            AudioLevelCapsule(
                level: monitor.microphoneLevel,
                isActive: monitor.isMonitoringMicrophone
            )
            Button {
                Task { await monitor.toggleMicrophoneMeter() }
            } label: {
                Text(
                    LocalizedStringKey(
                        monitor.isMonitoringMicrophone ? "Stop test" : "Test microphone"
                    )
                )
            }
            .font(.system(size: 11))
        }
    }
}

private struct StudioCheckView: View {
    @ObservedObject var store: EditorStore
    @ObservedObject var monitor: DeviceMonitor

    init(store: EditorStore) {
        self.store = store
        monitor = store.deviceMonitor
    }

    private var freeStorageGB: Double {
        let values = try? FileManager.default
            .homeDirectoryForCurrentUser
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Double(values?.volumeAvailableCapacityForImportantUsage ?? 0)
            / 1_000_000_000
    }

    var body: some View {
        InspectorSection(title: "Studio Check") {
            checkRow(
                "Screen access",
                ready: !store.capturePermissionIssue,
                detail: store.capturePermissionIssue ? "Permission required" : "Ready"
            )
            HStack(spacing: 8) {
                Image(
                    systemName: store.inputMonitoringGranted
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle.fill"
                )
                .foregroundStyle(
                    store.inputMonitoringGranted ? Color.green : Color.orange
                )
                Text("Click and shortcut detection")
                    .font(.system(size: 11))
                Spacer()
                if store.inputMonitoringGranted {
                    Text("Ready")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Button("Enable") {
                        store.requestInputMonitoringPermission()
                    }
                    .font(.system(size: 10))
                }
            }
            checkRow(
                "Storage",
                ready: freeStorageGB >= 2,
                detail: String(format: "%.1f GB", freeStorageGB)
            )
            if store.recordMicrophone {
                checkRow(
                    "Microphone access",
                    ready: monitor.microphoneAuthorization == .authorized,
                    detail: authorizationDetail(
                        monitor.microphoneAuthorization
                    )
                )
                checkRow(
                    "Audio signal",
                    ready: monitor.audioSignalState == .good,
                    detail: monitor.isMonitoringMicrophone ? "Live" : "Test microphone"
                )
            }
            checkRow(
                "Camera detected",
                ready: !monitor.cameras.isEmpty,
                detail: "\(monitor.cameras.count)"
            )
            if store.selectedCameraID != nil {
                checkRow(
                    "Camera access",
                    ready: monitor.cameraAuthorization == .authorized,
                    detail: authorizationDetail(
                        monitor.cameraAuthorization
                    )
                )
            }
        }
    }

    private func authorizationDetail(
        _ status: AVAuthorizationStatus
    ) -> String {
        switch status {
        case .authorized:
            return "Ready"
        case .notDetermined:
            return "Permission required"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        @unknown default:
            return "Unavailable"
        }
    }

    private func checkRow(_ title: LocalizedStringKey, ready: Bool, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ready ? Color.green : Color.orange)
            Text(title)
                .font(.system(size: 11))
            Spacer()
            Text(LocalizedStringKey(detail))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

private struct CanvasInspector: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        InspectorSection(title: "Style presets") {
            Menu {
                ForEach(BuiltInStylePreset.allCases) { preset in
                    Button(LocalizedStringKey(preset.rawValue)) {
                        store.applyBuiltInStylePreset(preset)
                    }
                }
            } label: {
                Label("Apply built-in preset", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .menuStyle(.borderlessButton)

            HStack {
                Button("Import preset…") {
                    store.importStylePreset()
                }
                Button("Save preset…") {
                    store.saveStylePreset()
                }
            }
            .buttonStyle(ToolbarButtonStyle())

            Text("Presets include canvas, cursor, zoom motion, captions, and camera layout.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }

        InspectorSection(title: "Background") {
            Picker(
                "Aspect ratio",
                selection: Binding(
                    get: { store.canvasAspectRatio },
                    set: { store.selectCanvasAspectRatio($0) }
                )
            ) {
                ForEach(CanvasAspectRatio.allCases) { ratio in
                    Text(LocalizedStringKey(ratio.displayTitle)).tag(ratio)
                }
            }

            Picker("Screen framing", selection: $store.canvasContentMode) {
                ForEach(CanvasContentMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(
                store.canvasContentMode == .fit
                    ? "Fit keeps every part of a wide recording visible."
                    : "Crop fills the canvas and can hide the outer edges."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Picker("Background type", selection: $store.backgroundMode) {
                ForEach(CanvasBackgroundMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                }
            }
            .pickerStyle(.menu)

            if store.backgroundMode == .wallpaper {
                Picker("Wallpaper", selection: $store.wallpaperPreset) {
                    ForEach(WallpaperPreset.allCases) { wallpaper in
                        Text(LocalizedStringKey(wallpaper.rawValue))
                            .tag(wallpaper)
                    }
                }
                HStack {
                    WallpaperSwatch(preset: store.wallpaperPreset)
                    Button {
                        store.randomizeWallpaper()
                    } label: {
                        Label("Random wallpaper", systemImage: "dice")
                    }
                }
            } else if store.backgroundMode == .image {
                Button {
                    store.chooseBackgroundImage()
                } label: {
                    Label("Choose image…", systemImage: "photo")
                }
                if let imageURL = store.backgroundImageURL {
                    Text(imageURL.lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if store.backgroundMode != .wallpaper {
                LabeledSlider(
                    title: "Hue",
                    value: $store.backgroundHue,
                    range: 0...0.9,
                    suffix: ""
                )
            }
            if store.backgroundMode == .image {
                LabeledSlider(
                    title: "Background blur",
                    value: $store.backgroundBlur,
                    range: 0...40,
                    suffix: "px"
                )
            }
            if store.backgroundMode != .wallpaper {
                HStack(spacing: 6) {
                    ForEach([0.58, 0.68, 0.78, 0.92, 0.05], id: \.self) { hue in
                        Button {
                            store.backgroundHue = hue
                        } label: {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(hue: hue, saturation: 0.7, brightness: 0.58))
                                .frame(height: 34)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        InspectorSection(title: "Screen") {
            LabeledSlider(
                title: "Padding",
                value: $store.canvasPadding,
                range: 0...80,
                suffix: "px"
            )
            LabeledSlider(
                title: "Rounded corners",
                value: $store.cornerRadius,
                range: 0...42,
                suffix: "px"
            )
            LabeledSlider(
                title: "Shadow",
                value: $store.shadowStrength,
                range: 0...1,
                suffix: ""
            )
        }
    }
}

private struct CanvasBackgroundView: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        Group {
            switch store.backgroundMode {
            case .wallpaper:
                LinearGradient(
                    colors: store.wallpaperPreset.colors.map {
                        Color(
                            hue: $0.hue,
                            saturation: $0.saturation,
                            brightness: $0.brightness
                        )
                    },
                    startPoint: UnitPoint(
                        x: store.wallpaperPreset.startPoint.x,
                        y: store.wallpaperPreset.startPoint.y
                    ),
                    endPoint: UnitPoint(
                        x: store.wallpaperPreset.endPoint.x,
                        y: store.wallpaperPreset.endPoint.y
                    )
                )
            case .gradient:
                LinearGradient(
                    colors: [
                        Color(
                            hue: store.backgroundHue,
                            saturation: 0.65,
                            brightness: 0.36
                        ),
                        Color(
                            hue: store.backgroundHue + 0.1,
                            saturation: 0.72,
                            brightness: 0.13
                        )
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .solid:
                Color(
                    hue: store.backgroundHue,
                    saturation: 0.68,
                    brightness: 0.42
                )
            case .image:
                if let url = store.backgroundImageURL,
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(
                        hue: store.backgroundHue,
                        saturation: 0.68,
                        brightness: 0.36
                    )
                }
            }
        }
        .scaleEffect(backgroundBlur > 0.5 ? 1.04 : 1)
        .blur(radius: backgroundBlur)
        .clipped()
    }

    private var backgroundBlur: Double {
        store.backgroundMode == .image ? store.backgroundBlur : 0
    }
}

private struct WallpaperSwatch: View {
    let preset: WallpaperPreset

    var body: some View {
        LinearGradient(
            colors: preset.colors.map {
                Color(
                    hue: $0.hue,
                    saturation: $0.saturation,
                    brightness: $0.brightness
                )
            },
            startPoint: UnitPoint(
                x: preset.startPoint.x,
                y: preset.startPoint.y
            ),
            endPoint: UnitPoint(
                x: preset.endPoint.x,
                y: preset.endPoint.y
            )
        )
        .frame(width: 72, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct CursorInspector: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        InspectorSection(title: "Cursor style") {
            Picker("Cursor replacement", selection: $store.cursorReplacement) {
                ForEach(CursorReplacementStyle.allCases) { style in
                    Text(LocalizedStringKey(style.title)).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!store.showCursor)
            Toggle("Show cursor", isOn: $store.showCursor)
                .toggleStyle(.switch)
            LabeledSlider(
                title: "Cursor size",
                value: $store.cursorSize,
                range: 0.6...2.5,
                suffix: "×"
            )
            Picker("Click effect", selection: $store.clickEffectPreset) {
                ForEach(ClickEffectPreset.allCases) { effect in
                    Text(LocalizedStringKey(effect.rawValue)).tag(effect)
                }
            }
            Toggle(
                "Show shortcut labels",
                isOn: $store.showShortcutOverlay
            )
            .toggleStyle(.switch)
            if !store.project.shortcuts.isEmpty {
                HStack {
                    Text(
                        L10n.text(
                            "%d shortcuts recorded",
                            language: store.appLanguage,
                            store.project.shortcuts.count
                        )
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove shortcut labels") {
                        store.removeAllShortcuts()
                    }
                    .font(.system(size: 10))
                }
            }
            Toggle("Hide cursor when idle", isOn: $store.hideCursorWhenIdle)
                .toggleStyle(.switch)
                .disabled(!store.showCursor)
            if store.hideCursorWhenIdle {
                LabeledSlider(
                    title: "Idle timeout",
                    value: $store.cursorIdleTimeout,
                    range: 0.5...5,
                    suffix: "s"
                )
            }
            LabeledSlider(
                title: "Stop before end",
                value: $store.cursorTailFreeze,
                range: 0...5,
                suffix: "s"
            )
            .disabled(!store.showCursor)
            Text("Set to 0s to keep cursor movement until the final frame.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Toggle(
                "Return cursor to start",
                isOn: $store.cursorLoopToStart
            )
            .toggleStyle(.switch)
            .disabled(!store.showCursor)
            Text("Moves the cursor smoothly to its opening position near the end.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Toggle(
                "Remove cursor shakes",
                isOn: $store.removeCursorShakes
            )
            .toggleStyle(.switch)
            .disabled(!store.showCursor)
            if store.removeCursorShakes {
                LabeledSlider(
                    title: "Shake threshold",
                    value: $store.cursorShakeThreshold,
                    range: 0.002...0.08,
                    suffix: ""
                )
            }
            Toggle(
                "Optimize rapid cursor changes",
                isOn: $store.optimizeRapidCursorChanges
            )
            .toggleStyle(.switch)
            .disabled(!store.showCursor)
            Toggle(
                "Smooth cursor movement",
                isOn: $store.smoothCursorMovement
            )
            .toggleStyle(.switch)
            .disabled(!store.showCursor)
            Text("Path cleanup is non-destructive and keeps the recorded cursor samples.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text("Cursor locations and clicks are captured separately so zooms can be regenerated after recording.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("For privacy, only shortcuts containing Command, Control, or Option are recorded. Ordinary typing is never stored.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct CaptionsInspector: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        InspectorSection(title: "Captions") {
            Picker("Recognition language", selection: $store.captionLanguage) {
                Text("简体中文").tag("zh-CN")
                Text("English").tag("en-US")
                Text("日本語").tag("ja-JP")
                Text("한국어").tag("ko-KR")
            }

            Toggle("Show captions", isOn: $store.showCaptions)
                .toggleStyle(.switch)

            LabeledSlider(
                title: "Caption size",
                value: $store.captionFontSize,
                range: 18...60,
                suffix: "px"
            )

            Text("Vocabulary & context")
                .font(.system(size: 12, weight: .semibold))
            TextEditor(text: $store.captionVocabulary)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 68, maxHeight: 96)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
            Text("Add product names or specialist terms, separated by commas or new lines. They guide recognition and are saved only in this project.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Button {
                store.generateCaptions()
            } label: {
                HStack {
                    if store.isGeneratingCaptions {
                        ProgressView().controlSize(.small)
                    }
                    Label(
                        store.isGeneratingCaptions
                            ? "Generating…"
                            : "Generate on this Mac",
                        systemImage: "captions.bubble"
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AccentButtonStyle(colors: [.purple, .blue]))
            .disabled(
                store.sourceURL == nil
                    || store.audioAnalysis.waveform.isEmpty
                    || store.isGeneratingCaptions
            )

            Text("Speech recognition stays on this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }

        if !store.project.captions.isEmpty {
            InspectorSection(title: "Transcript") {
                ForEach(store.project.captions.prefix(30)) { cue in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.formatted(cue.sourceStart))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        TextField(
                            "Caption",
                            text: Binding(
                                get: { cue.text },
                                set: { store.updateCaption(id: cue.id, text: $0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                }

                Button(role: .destructive) {
                    store.removeAllCaptions()
                } label: {
                    Label("Remove captions", systemImage: "trash")
                }
            }
        }
    }
}

private struct CameraInspector: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        InspectorSection(title: "Camera layout") {
            if store.cameraURL == nil {
                Label("No camera recording", systemImage: "video.slash")
                    .foregroundStyle(.secondary)
                Text("Choose a camera before recording to create an editable picture-in-picture track.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Picker("Position", selection: $store.cameraPosition) {
                    ForEach(CameraPosition.allCases) { position in
                        Text(LocalizedStringKey(position.rawValue)).tag(position)
                    }
                }
                .pickerStyle(.menu)

                LabeledSlider(
                    title: "Camera size",
                    value: $store.cameraSize,
                    range: 0.12...0.5,
                    suffix: "×"
                )
                LabeledSlider(
                    title: "Camera corners",
                    value: $store.cameraCornerRadius,
                    range: 0...60,
                    suffix: "px"
                )
                Toggle("Mirror camera", isOn: $store.cameraMirrored)
                    .toggleStyle(.switch)
            }
        }
    }
}

private struct AudioInspector: View {
    @ObservedObject var store: EditorStore

    private var rmsDecibels: Double {
        guard store.audioAnalysis.rms > 0 else { return -.infinity }
        return 20 * log10(Double(store.audioAnalysis.rms))
    }

    private var peakDecibels: Double {
        guard store.audioAnalysis.peak > 0 else { return -.infinity }
        return 20 * log10(Double(store.audioAnalysis.peak))
    }

    var body: some View {
        if let layout = store.recordedAudioLayout,
           layout.hasSystemAudio || layout.hasMicrophone {
            InspectorSection(title: "Recorded tracks") {
                if layout.hasSystemAudio {
                    LabeledSlider(
                        title: "System volume",
                        value: Binding(
                            get: { store.systemAudioVolume * 100 },
                            set: { store.systemAudioVolume = $0 / 100 }
                        ),
                        range: 0...200,
                        suffix: "%"
                    )
                }

                if layout.hasMicrophone {
                    Toggle(
                        "Mute microphone",
                        isOn: $store.microphoneAudioMuted
                    )
                    .toggleStyle(.switch)
                    LabeledSlider(
                        title: "Microphone volume",
                        value: Binding(
                            get: { store.microphoneAudioVolume * 100 },
                            set: { store.microphoneAudioVolume = $0 / 100 }
                        ),
                        range: 0...200,
                        suffix: "%"
                    )
                    .disabled(store.microphoneAudioMuted)
                }

                Text("Recorded tracks stay independently adjustable in preview and recovery, then mix into the exported MP4.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }

        InspectorSection(title: "Background music") {
            if let url = store.backgroundMusicURL {
                Label {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "music.note")
                }
                LabeledContent("Duration") {
                    Text(store.formatted(store.backgroundMusicDuration))
                        .font(.system(.caption, design: .monospaced))
                }
                LabeledSlider(
                    title: "Music volume",
                    value: $store.backgroundMusicVolume,
                    range: 0...1,
                    suffix: "×"
                )
                HStack {
                    Button("Replace…") {
                        store.importBackgroundMusic()
                    }
                    Button("Remove", role: .destructive) {
                        store.removeBackgroundMusic()
                    }
                }
                Text("Music loops automatically to match the edited timeline.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    store.importBackgroundMusic()
                } label: {
                    Label("Add background music…", systemImage: "music.note.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ToolbarButtonStyle())
            }
        }

        InspectorSection(title: "Audio analysis") {
            if store.isAnalyzingAudio {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Analyzing audio…")
                        .font(.system(size: 11))
                }
            } else if store.audioAnalysis.waveform.isEmpty {
                Label("No audio signal", systemImage: "speaker.slash")
                    .foregroundStyle(.secondary)
            } else {
                MiniWaveform(samples: store.audioAnalysis.waveform)
                    .frame(height: 58)

                LabeledContent("Average") {
                    Text("\(rmsDecibels, specifier: "%.1f") dBFS")
                        .font(.system(.caption, design: .monospaced))
                }
                LabeledContent("Peak") {
                    Text("\(peakDecibels, specifier: "%.1f") dBFS")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(peakDecibels > -1 ? Color.orange : Color.secondary)
                }

                Button {
                    store.normalizeAllAudio()
                } label: {
                    Label("Normalize safely", systemImage: "waveform.badge.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ToolbarButtonStyle())

                Text("ScreenFree analyzes the real recorded samples and chooses gain without clipping.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MiniWaveform: View {
    let samples: [Float]

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let mid = geometry.size.height / 2
                for (index, sample) in samples.enumerated() {
                    let x = geometry.size.width * CGFloat(index)
                        / CGFloat(max(1, samples.count - 1))
                    let height = CGFloat(sample) * geometry.size.height * 0.46
                    path.move(to: CGPoint(x: x, y: mid - height))
                    path.addLine(to: CGPoint(x: x, y: mid + height))
                }
            }
            .stroke(
                LinearGradient(
                    colors: [.purple, .blue],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 1
            )
        }
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ClipInspector: View {
    @ObservedObject var store: EditorStore

    var selectedClip: TimelineClip? {
        store.project.clips.first { $0.id == store.selectedClipID }
    }

    var selectedIndex: Int? {
        store.project.clips.firstIndex { $0.id == store.selectedClipID }
    }

    var body: some View {
        InspectorSection(title: "Smart editing") {
            Button {
                store.smartTrimSilence()
            } label: {
                Label("Smart trim", systemImage: "wand.and.stars")
            }
            .disabled(store.project.clips.isEmpty)
            Text("Cuts silent footage from the start and end of the recording.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }

        if let clip = selectedClip {
            InspectorSection(title: "Selected clip") {
                LabeledSlider(
                    title: "Playback speed",
                    value: Binding(
                        get: { clip.playbackRate },
                        set: { store.updateSelectedClip(playbackRate: $0) }
                    ),
                    range: 0.5...4,
                    suffix: "×",
                    onEditingChanged: { editing in
                        if editing {
                            store.beginContinuousTimelineEdit(.clip)
                        } else {
                            store.endContinuousTimelineEdit()
                        }
                    }
                )
                LabeledSlider(
                    title: "Volume",
                    value: Binding(
                        get: { clip.volume * 100 },
                        set: { store.updateSelectedClip(volume: $0 / 100) }
                    ),
                    range: 0...400,
                    suffix: "%",
                    onEditingChanged: { editing in
                        if editing {
                            store.beginContinuousTimelineEdit(.clip)
                        } else {
                            store.endContinuousTimelineEdit()
                        }
                    }
                )
            }

            InspectorSection(title: "Trim and split") {
                HStack {
                    Button("Trim start") { store.trimSelected(start: true) }
                    Button("Trim end") { store.trimSelected(start: false) }
                    Button("Reset trim") { store.resetSelectedTrim() }
                }
                .buttonStyle(ToolbarButtonStyle())

                Button {
                    store.splitAtPlayhead()
                } label: {
                    Label("Split at playhead", systemImage: "scissors")
                }

                HStack {
                    Button("Merge previous") {
                        store.mergeSelectedClip(withNext: false)
                    }
                    .disabled(selectedIndex == nil || selectedIndex == 0)

                    Button("Merge next") {
                        store.mergeSelectedClip(withNext: true)
                    }
                    .disabled(
                        selectedIndex == nil
                            || selectedIndex == store.project.clips.count - 1
                    )
                }
                .buttonStyle(ToolbarButtonStyle())

                Button(role: .destructive) {
                    store.deleteSelectedClip()
                } label: {
                    Label("Remove clip", systemImage: "trash")
                }
                .disabled(store.project.clips.count <= 1)
            }
        } else {
            Text("Select a clip on the timeline to change speed, volume, or trim.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

private struct TransitionInspector: View {
    @ObservedObject var store: EditorStore

    private var selectedTransition: ClipTransition? {
        store.project.transitions.first {
            $0.id == store.selectedTransitionID
        }
    }

    var body: some View {
        if let transition = selectedTransition {
            InspectorSection(title: "Selected transition") {
                templateGrid(selected: transition.style) { style in
                    store.updateSelectedTransition(style: style)
                }
                LabeledSlider(
                    title: "Duration",
                    value: Binding(
                        get: { transition.duration },
                        set: { store.updateSelectedTransition(duration: $0) }
                    ),
                    range: 0.2...1.2,
                    suffix: "s"
                )
                HStack {
                    Button {
                        store.previewTransition()
                    } label: {
                        Label("Preview", systemImage: "play.fill")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        store.removeSelectedTransition()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
                .buttonStyle(ToolbarButtonStyle())
            }
        } else {
            InspectorSection(title: "Transition templates") {
                templateGrid(selected: store.transitionStyle) { style in
                    store.transitionStyle = style
                }
                Text(
                    "Drag a template onto the cut between two clips, or tap a junction marker."
                )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                LabeledSlider(
                    title: "Default duration",
                    value: $store.transitionDuration,
                    range: 0.2...1.2,
                    suffix: "s"
                )
            }
        }
    }

    private func templateGrid(
        selected: ClipTransitionStyle,
        onSelect: @escaping (ClipTransitionStyle) -> Void
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 8
        ) {
            ForEach(ClipTransitionStyle.allCases) { style in
                Button {
                    onSelect(style)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: style.symbol)
                            .font(.system(size: 16))
                        Text(LocalizedStringKey(style.rawValue))
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        selected == style
                            ? Color.accentColor.opacity(0.28)
                            : Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .overlay {
                        if selected == style {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.accentColor, lineWidth: 1.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .draggable(style.rawValue)
                .accessibilityIdentifier(
                    "transition.template.\(style.rawValue)"
                )
            }
        }
    }
}

private struct ZoomInspector: View {
    @ObservedObject var store: EditorStore

    var selectedZoom: ZoomEvent? {
        store.project.zooms.first { $0.id == store.selectedZoomID }
    }

    var body: some View {
        InspectorSection(title: "Mouse zoom") {
            Text("Drag either edge of a purple zoom bar to change its duration.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            LabeledSlider(
                title: "Default scale",
                value: $store.zoomScale,
                range: 1.1...3,
                suffix: "×"
            )
            LabeledSlider(
                title: "Default duration",
                value: $store.zoomDuration,
                range: 0.1...10,
                suffix: "s"
            )
            Picker("Motion", selection: $store.zoomMotionPreset) {
                ForEach(ZoomMotionPreset.allCases) { preset in
                    Text(LocalizedStringKey(preset.rawValue)).tag(preset)
                }
            }
            .pickerStyle(.menu)
            if store.zoomMotionPreset == .custom {
                LabeledSlider(
                    title: "Transition duration",
                    value: $store.zoomCustomTransitionDuration,
                    range: 0.08...1.5,
                    suffix: "s"
                )
                LabeledSlider(
                    title: "Control X1",
                    value: $store.zoomCustomX1,
                    range: 0...1,
                    suffix: ""
                )
                LabeledSlider(
                    title: "Control Y1",
                    value: $store.zoomCustomY1,
                    range: 0...1,
                    suffix: ""
                )
                LabeledSlider(
                    title: "Control X2",
                    value: $store.zoomCustomX2,
                    range: 0...1,
                    suffix: ""
                )
                LabeledSlider(
                    title: "Control Y2",
                    value: $store.zoomCustomY2,
                    range: 0...1,
                    suffix: ""
                )
                Text("Cubic Bézier controls are shared by preview and export.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Button("Add at playhead") { store.addZoomAtPlayhead() }
                Button("Auto from clicks") { store.regenerateAutomaticZooms() }
            }
            .buttonStyle(ToolbarButtonStyle())
        }

        InspectorSection(title: "Motion blur") {
            Toggle("Enable motion blur", isOn: $store.motionBlurEnabled)
                .toggleStyle(.switch)
            Group {
                LabeledSlider(
                    title: "Overall strength",
                    value: $store.motionBlurStrength,
                    range: 0...1,
                    suffix: "×"
                )
                LabeledSlider(
                    title: "Cursor movement",
                    value: $store.cursorMotionBlur,
                    range: 0...1,
                    suffix: "×"
                )
                LabeledSlider(
                    title: "Screen zooming",
                    value: $store.zoomMotionBlur,
                    range: 0...1,
                    suffix: "×"
                )
                LabeledSlider(
                    title: "Screen panning",
                    value: $store.panMotionBlur,
                    range: 0...1,
                    suffix: "×"
                )
            }
            .disabled(!store.motionBlurEnabled)
            Text("Blur responds to real cursor and zoom velocity, so static frames stay sharp.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }

        if let zoom = selectedZoom {
            InspectorSection(title: "Selected zoom") {
                Text("Starts at \(store.formatted(zoom.start))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                LabeledSlider(
                    title: "Scale",
                    value: Binding(
                        get: { zoom.scale },
                        set: { store.updateSelectedZoom(scale: $0) }
                    ),
                    range: 1.1...3,
                    suffix: "×",
                    onEditingChanged: { editing in
                        if editing {
                            store.beginContinuousTimelineEdit(.zoom)
                        } else {
                            store.endContinuousTimelineEdit()
                        }
                    }
                )
                LabeledSlider(
                    title: "Duration",
                    value: Binding(
                        get: { zoom.duration },
                        set: { store.updateSelectedZoom(duration: $0) }
                    ),
                    range: 0.1...max(
                        0.1,
                        min(30, store.project.duration - zoom.start)
                    ),
                    suffix: "s",
                    onEditingChanged: { editing in
                        if editing {
                            store.beginContinuousTimelineEdit(.zoom)
                        } else {
                            store.endContinuousTimelineEdit()
                        }
                    }
                )

                Toggle(
                    "Follow cursor",
                    isOn: Binding(
                        get: { zoom.resolvedFollowsCursor },
                        set: { store.updateSelectedZoom(followsCursor: $0) }
                    )
                )
                .toggleStyle(.switch)

                Text("Click the video preview to move the zoom focus.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    store.deleteSelectedZoom()
                } label: {
                    Label("Delete zoom", systemImage: "trash")
                }
            }
        } else {
            Text("Add a zoom or select one on the purple Zooms track.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

private struct PrivacyInspector: View {
    @ObservedObject var store: EditorStore

    private var selectedRedaction: PrivacyRedaction? {
        store.project.redactions.first { $0.id == store.selectedRedactionID }
    }

    var body: some View {
        InspectorSection(title: "Privacy & highlights") {
            Text("Cover sensitive data or focus attention on one area for only the required time range.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    store.addRedactionAtPlayhead()
                } label: {
                    Label("Redact", systemImage: "eye.slash")
                }
                Button {
                    store.addSpotlightAtPlayhead()
                } label: {
                    Label("Spotlight", systemImage: "light.beacon.max")
                }
            }
            .buttonStyle(ToolbarButtonStyle())
            .disabled(store.sourceURL == nil)
        }

        if let redaction = selectedRedaction {
            InspectorSection(
                title: redaction.resolvedPresentation == .spotlight
                    ? "Selected spotlight"
                    : "Selected redaction"
            ) {
                Text("Drag the region in the preview or either edge of its timeline bar.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                LabeledSlider(
                    title: "Width",
                    value: Binding(
                        get: { Double(redaction.normalizedWidth * 100) },
                        set: {
                            store.updateSelectedRedaction(
                                width: CGFloat($0 / 100)
                            )
                        }
                    ),
                    range: 6...100,
                    suffix: "%",
                    onEditingChanged: { editing in
                        if editing {
                            store.beginContinuousTimelineEdit(.redaction)
                        } else {
                            store.endContinuousTimelineEdit()
                        }
                    }
                )
                LabeledSlider(
                    title: "Height",
                    value: Binding(
                        get: { Double(redaction.normalizedHeight * 100) },
                        set: {
                            store.updateSelectedRedaction(
                                height: CGFloat($0 / 100)
                            )
                        }
                    ),
                    range: 5...100,
                    suffix: "%",
                    onEditingChanged: { editing in
                        if editing {
                            store.beginContinuousTimelineEdit(.redaction)
                        } else {
                            store.endContinuousTimelineEdit()
                        }
                    }
                )
                LabeledSlider(
                    title: redaction.resolvedPresentation == .spotlight
                        ? "Dim intensity"
                        : "Opacity",
                    value: Binding(
                        get: { Double(redaction.opacity * 100) },
                        set: {
                            store.updateSelectedRedaction(
                                opacity: CGFloat($0 / 100)
                            )
                        }
                    ),
                    range: 35...100,
                    suffix: "%",
                    onEditingChanged: { editing in
                        if editing {
                            store.beginContinuousTimelineEdit(.redaction)
                        } else {
                            store.endContinuousTimelineEdit()
                        }
                    }
                )
                if redaction.resolvedPresentation == .spotlight {
                    LabeledSlider(
                        title: "Highlight hue",
                        value: Binding(
                            get: {
                                Double(redaction.resolvedHighlightHue)
                            },
                            set: {
                                store.updateSelectedRedaction(
                                    highlightHue: CGFloat($0)
                                )
                            }
                        ),
                        range: 0...1,
                        suffix: "",
                        onEditingChanged: { editing in
                            if editing {
                                store.beginContinuousTimelineEdit(.redaction)
                            } else {
                                store.endContinuousTimelineEdit()
                            }
                        }
                    )
                }
                LabeledSlider(
                    title: "Duration",
                    value: Binding(
                        get: { redaction.duration },
                        set: {
                            store.updateSelectedRedaction(duration: $0)
                        }
                    ),
                    range: 0.1...max(
                        0.1,
                        store.project.duration - redaction.start
                    ),
                    suffix: "s",
                    onEditingChanged: { editing in
                        if editing {
                            store.beginContinuousTimelineEdit(.redaction)
                        } else {
                            store.endContinuousTimelineEdit()
                        }
                    }
                )

                Button(role: .destructive) {
                    store.deleteSelectedRedaction()
                } label: {
                    Label(
                        redaction.resolvedPresentation == .spotlight
                            ? "Delete spotlight"
                            : "Delete redaction",
                        systemImage: "trash"
                    )
                }
            }
        } else {
            Text("Add a redaction or spotlight, or select one on the Privacy track.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

private struct AnnotationInspector: View {
    @ObservedObject var store: EditorStore

    private var selectedAnnotation: EmphasisAnnotation? {
        store.project.annotations.first {
            $0.id == store.selectedAnnotationID
        }
    }

    var body: some View {
        InspectorSection(title: "Emphasis annotations") {
            Text("Choose a shape, then drag directly on the video. The annotation is included in preview and export.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    store.beginAnnotationTool(.rectangle)
                } label: {
                    Label("Rectangle", systemImage: "rectangle")
                }
                Button {
                    store.beginAnnotationTool(.line)
                } label: {
                    Label("Line", systemImage: "line.diagonal")
                }
            }
            .buttonStyle(ToolbarButtonStyle())
            .disabled(store.sourceURL == nil)
        }

        if let annotation = selectedAnnotation {
            InspectorSection(title: "Selected annotation") {
                Text(
                    annotation.kind == .rectangle
                        ? "Rectangle emphasis"
                        : "Line emphasis"
                )
                .font(.system(size: 12, weight: .medium))
                Text(
                    "\(store.formatted(annotation.start)) · \(annotation.duration, specifier: "%.1f")s"
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    store.deleteSelectedAnnotation()
                } label: {
                    Label("Delete annotation", systemImage: "trash")
                }
            }
        } else {
            Text("Draw on the preview or drag on the Annotations track.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ExportInspector: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        InspectorSection(title: "Export") {
            Picker("Destination", selection: $store.exportDestination) {
                ForEach(ExportDestination.allCases) { destination in
                    Text(LocalizedStringKey(destination.rawValue)).tag(destination)
                }
            }
            .pickerStyle(.segmented)

            Picker("Format", selection: $store.exportFormat) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)

            Picker("Resolution", selection: $store.exportResolution) {
                ForEach(ExportResolution.allCases) { resolution in
                    Text(LocalizedStringKey(resolution.rawValue)).tag(resolution)
                }
            }
            if store.exportResolution == .custom {
                HStack(spacing: 8) {
                    TextField(
                        "Width",
                        value: Binding(
                            get: { store.exportCustomWidth },
                            set: { store.setCustomExportWidth($0) }
                        ),
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    Text("×")
                        .foregroundStyle(.secondary)
                    TextField(
                        "Height",
                        value: Binding(
                            get: { store.exportCustomHeight },
                            set: { store.setCustomExportHeight($0) }
                        ),
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    Text("px")
                        .foregroundStyle(.secondary)
                }
                Text("Custom dimensions use an even 320–7680 px canvas and center-crop the source to fit.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Text("Output size")
                Spacer()
                Text(
                    "\(store.resolvedExportDimensions.width) × \(store.resolvedExportDimensions.height)"
                )
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            Picker("Quality", selection: $store.exportQuality) {
                ForEach(ExportQuality.allCases) { quality in
                    Text(LocalizedStringKey(quality.rawValue)).tag(quality)
                }
            }
            Text(LocalizedStringKey(store.exportQuality.explanation))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Picker("Frame rate", selection: $store.exportFrameRate) {
                ForEach(
                    ExportFrameRateOptions.supported(for: store.exportFormat),
                    id: \.self
                ) { rate in
                    Text("\(rate) fps").tag(rate)
                }
            }
            .onChange(of: store.exportFormat) { _, format in
                store.exportFrameRate = ExportFrameRateOptions.normalized(
                    store.exportFrameRate,
                    for: format
                )
            }

            HStack {
                Text("Codec")
                Spacer()
                Text(store.exportFormat == .gif ? "Animated GIF" : "H.264 + AAC")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Timeline")
                Spacer()
                Text(store.formatted(store.project.duration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text("Timeline cuts and every mouse-focused zoom are rendered into the exported video.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if store.isVideoExporting {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Export progress")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(
                            store.exportProgress,
                            format: .percent.precision(.fractionLength(0))
                        )
                        .font(.system(.caption, design: .monospaced))
                    }
                    ProgressView(value: store.exportProgress)
                        .progressViewStyle(.linear)
                    Button(role: .cancel) {
                        store.cancelExport()
                    } label: {
                        Label("Cancel export", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ToolbarButtonStyle())
                }
            }

            Button {
                store.presentExportSheet(
                    destination: store.exportDestination
                )
            } label: {
                Label {
                    Text(
                        LocalizedStringKey(
                            store.exportDestination == .clipboard
                                ? "Copy video"
                                : "Export video"
                        )
                    )
                } icon: {
                    Image(systemName: store.exportDestination.symbolName)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AccentButtonStyle(colors: [.indigo, .blue]))
            .disabled(store.sourceURL == nil || store.isExporting)

            HStack {
                Button {
                    store.copyCurrentFrame()
                } label: {
                    Label("Copy frame", systemImage: "doc.on.clipboard")
                }
                Button {
                    store.saveCurrentFrame()
                } label: {
                    Label("Save frame…", systemImage: "photo")
                }
            }
            .buttonStyle(ToolbarButtonStyle())
            .disabled(store.sourceURL == nil || store.isExporting)
        }

        InspectorSection(title: "Original media") {
            Button {
                store.saveOriginalScreenMedia()
            } label: {
                Label("Save original screen…", systemImage: "rectangle.on.rectangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(store.sourceURL == nil || store.isExporting)

            if store.cameraURL != nil {
                Button {
                    store.saveOriginalCameraMedia()
                } label: {
                    Label("Save original camera…", systemImage: "video")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(store.isExporting)
            }

            if store.recordedAudioLayout?.hasSystemAudio == true {
                Button {
                    store.saveOriginalSystemAudio()
                } label: {
                    Label("Save original system audio…", systemImage: "speaker.wave.2")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(store.isExporting)
            }

            if store.recordedAudioLayout?.hasMicrophone == true {
                Button {
                    store.saveOriginalMicrophoneAudio()
                } label: {
                    Label("Save original microphone…", systemImage: "mic")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(store.isExporting)
            }

            Text("Original files exclude timeline cuts, canvas styling, cursor effects, and zooms.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(ToolbarButtonStyle())
    }
}

private struct InspectorSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.035))
                .stroke(.white.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct LabeledSlider<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let title: LocalizedStringKey
    @Binding var value: V
    let range: ClosedRange<V>
    let suffix: String
    let onEditingChanged: (Bool) -> Void

    init(
        title: LocalizedStringKey,
        value: Binding<V>,
        range: ClosedRange<V>,
        suffix: String,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.title = title
        _value = value
        self.range = range
        self.suffix = suffix
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Double(value), specifier: "%.1f")\(suffix)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: $value,
                in: range,
                onEditingChanged: onEditingChanged
            )
                .tint(.purple)
        }
    }
}

private struct EmphasisAnnotationOverlay: View {
    let annotation: EmphasisAnnotation
    let selected: Bool

    var body: some View {
        Canvas { context, size in
            let start = CGPoint(
                x: size.width * annotation.normalizedStartX,
                y: size.height * annotation.normalizedStartY
            )
            let end = CGPoint(
                x: size.width * annotation.normalizedEndX,
                y: size.height * annotation.normalizedEndY
            )
            var path = Path()
            switch annotation.kind {
            case .rectangle:
                path.addRoundedRect(
                    in: CGRect(
                        x: min(start.x, end.x),
                        y: min(start.y, end.y),
                        width: abs(end.x - start.x),
                        height: abs(end.y - start.y)
                    ),
                    cornerSize: CGSize(width: 10, height: 10)
                )
            case .line:
                path.move(to: start)
                path.addLine(to: end)
            }
            context.stroke(
                path,
                with: .color(.orange),
                style: StrokeStyle(
                    lineWidth: annotation.lineWidth,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: selected ? [9, 5] : []
                )
            )
        }
        .shadow(color: .black.opacity(0.7), radius: 2)
        .allowsHitTesting(false)
    }
}

private struct SpotlightOverlay: View {
    let region: PrivacyRedaction
    let selected: Bool

    var body: some View {
        Canvas { context, size in
            let hole = CGRect(
                x: size.width
                    * (region.normalizedX - region.normalizedWidth / 2),
                y: size.height
                    * (region.normalizedY - region.normalizedHeight / 2),
                width: size.width * region.normalizedWidth,
                height: size.height * region.normalizedHeight
            )
            var dimPath = Path(CGRect(origin: .zero, size: size))
            dimPath.addRoundedRect(in: hole, cornerSize: CGSize(width: 12, height: 12))
            context.fill(
                dimPath,
                with: .color(.black.opacity(region.opacity)),
                style: FillStyle(eoFill: true)
            )
            let border = Path(
                roundedRect: hole,
                cornerRadius: 12
            )
            context.stroke(
                border,
                with: .color(
                    Color(
                        hue: region.resolvedHighlightHue,
                        saturation: 0.9,
                        brightness: 1
                    ).opacity(selected ? 1 : 0.86)
                ),
                style: StrokeStyle(
                    lineWidth: selected ? 3 : 2,
                    dash: selected ? [7, 4] : []
                )
            )
        }
    }
}

private struct FocusReticle: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.95), lineWidth: 1.5)
                .frame(width: 30, height: 30)
            Circle()
                .fill(.purple)
                .frame(width: 6, height: 6)
        }
        .shadow(color: .black.opacity(0.7), radius: 3)
    }
}

private struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = videoGravity
        view.allowsPictureInPicturePlayback = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        nsView.videoGravity = videoGravity
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(configuration.isPressed ? 0.11 : 0.06))
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct AccentButtonStyle: ButtonStyle {
    let colors: [Color]

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: colors.map { $0.opacity(configuration.isPressed ? 0.7 : 1) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .shadow(color: (colors.first ?? .purple).opacity(0.25), radius: 8, y: 3)
    }
}
