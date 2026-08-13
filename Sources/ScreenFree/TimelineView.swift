import AppKit
import ScreenFreeCore
import SwiftUI

struct TimelineView: View {
    @ObservedObject var store: EditorStore
    @State private var zoomDraftStart: TimeInterval?
    @State private var zoomDraftEnd: TimeInterval?
    @State private var annotationDraftStart: TimeInterval?
    @State private var annotationDraftEnd: TimeInterval?
    @State private var annotationMoveOrigins: [UUID: TimeInterval] = [:]
    @State private var splitCursorPushed = false
    @State private var magnificationStartZoom: Double?

    var body: some View {
        GeometryReader { geometry in
            let viewportWidth = max(1, geometry.size.width - 34)
            let duration = max(0.01, store.project.duration)
            let scale = TimelineScale(zoom: store.timelineZoom)
            let contentWidth = scale.contentWidth(viewportWidth: viewportWidth)

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 8) {
                    ruler(
                        width: contentWidth,
                        duration: duration,
                        scale: scale
                    )
                    .frame(width: contentWidth, height: 20)

                    clipTrack(
                        width: contentWidth,
                        duration: duration,
                        scale: scale
                    )
                    .frame(width: contentWidth, height: 104)

                    zoomTrack(
                        width: contentWidth,
                        duration: duration,
                        scale: scale
                    )
                    .frame(width: contentWidth, height: 39)

                    privacyTrack(
                        width: contentWidth,
                        duration: duration,
                        scale: scale
                    )
                    .frame(width: contentWidth, height: 39)
                }
                .frame(width: contentWidth)
                .padding(.horizontal, 17)
                .padding(.top, 10)
                .background {
                    TimelinePlaybackAutoScroller(
                        playheadX: 17 + scale.x(
                            forTime: store.playhead,
                            duration: duration,
                            contentWidth: contentWidth
                        ),
                        contentWidth: contentWidth + 34,
                        isPlaying: store.isPlaying
                    )
                }
                .overlay(alignment: .topLeading) {
                    playhead(
                        width: contentWidth,
                        duration: duration,
                        scale: scale
                    )
                    .offset(x: 17, y: 8)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard store.sourceURL != nil,
                                  store.activeTimelineTool == .selection,
                                  !startsOnClipTrimHandle(
                                    x: value.startLocation.x - 17,
                                    width: contentWidth,
                                    duration: duration,
                                    scale: scale
                                  ) else {
                                return
                            }
                            let time = scale.time(
                                atX: value.location.x - 17,
                                duration: duration,
                                contentWidth: contentWidth
                            )
                            store.seek(to: time)
                        }
                        .onEnded { value in
                            guard store.sourceURL != nil,
                                  store.activeTimelineTool == .selection,
                                  !startsOnClipTrimHandle(
                                    x: value.startLocation.x - 17,
                                    width: contentWidth,
                                    duration: duration,
                                    scale: scale
                                  ),
                                  abs(value.translation.width) < 4,
                                  abs(value.translation.height) < 4 else {
                                return
                            }
                            let time = scale.time(
                                atX: value.location.x - 17,
                                duration: duration,
                                contentWidth: contentWidth
                            )
                            store.seekAndPlay(to: time)
                        }
                )
            }
            .simultaneousGesture(
                MagnificationGesture(minimumScaleDelta: 0.01)
                    .onChanged { magnification in
                        if magnificationStartZoom == nil {
                            magnificationStartZoom = store.timelineZoom
                        }
                        guard let startZoom = magnificationStartZoom else {
                            return
                        }
                        store.setTimelineZoom(
                            startZoom * Double(magnification)
                        )
                    }
                    .onEnded { _ in
                        magnificationStartZoom = nil
                    }
            )
        }
        .overlay(alignment: .topTrailing) {
            timelineZoomControl
                .padding(.top, 5)
                .padding(.trailing, 22)
        }
        .background(StudioTheme.canvas)
        .onChange(of: store.activeTimelineTool) {
            if store.activeTimelineTool != .split {
                updateSplitCursor(false)
            }
        }
        .onDisappear {
            updateSplitCursor(false)
        }
    }

    private var timelineZoomControl: some View {
        HStack(spacing: 5) {
            Button {
                store.undoTimelineEdit()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(!store.canUndoTimelineEdit)
            .accessibilityIdentifier("timeline.undo")
            .accessibilityLabel(store.timelineUndoTitle ?? "Undo timeline edit")
            .help(store.timelineUndoTitle ?? "Nothing to undo")

            Divider()
                .frame(height: 13)

            Button {
                store.zoomTimeline(by: 1 / TimelineScale.stepFactor)
            } label: {
                Image(systemName: "minus")
            }
            .disabled(store.timelineZoom <= TimelineScale.fitZoom)
            .accessibilityLabel("Zoom out timeline")
            .help("Zoom out timeline")

            Slider(
                value: Binding(
                    get: { log2(store.timelineZoom) },
                    set: { store.setTimelineZoom(pow(2, $0)) }
                ),
                in: 0...log2(TimelineScale.maximumZoom)
            )
            .controlSize(.mini)
            .frame(width: 82)

            Text("\(Int((store.timelineZoom * 100).rounded()))%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 38)
                .fixedSize()

            Button {
                store.zoomTimeline(by: TimelineScale.stepFactor)
            } label: {
                Image(systemName: "plus")
            }
            .disabled(store.timelineZoom >= TimelineScale.maximumZoom)
            .accessibilityLabel("Zoom in timeline")
            .help("Zoom in timeline")

            Button {
                store.fitTimeline()
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
            }
            .disabled(store.timelineZoom <= TimelineScale.fitZoom)
            .accessibilityLabel("Fit timeline")
            .help("Fit timeline")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 9, weight: .semibold))
        .padding(.horizontal, 8)
        .frame(height: 25)
        .background(
            .ultraThinMaterial,
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .help("Drag or pinch the timeline to change detail")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline zoom")
    }

    private func startsOnClipTrimHandle(
        x: CGFloat,
        width: CGFloat,
        duration: TimeInterval,
        scale: TimelineScale
    ) -> Bool {
        guard store.activeTimelineTool == .selection else { return false }
        let hitRadius: CGFloat = 18
        var timelineStart: TimeInterval = 0
        for clip in store.project.clips {
            let isExposingHandles = clip.id == store.selectedClipID
                || store.hoveredTimelineBlock == .clip(clip.id)
            let timelineEnd = timelineStart + clip.timelineDuration
            if isExposingHandles {
                let leadingX = scale.x(
                    forTime: timelineStart,
                    duration: duration,
                    contentWidth: width
                )
                let trailingX = scale.x(
                    forTime: timelineEnd,
                    duration: duration,
                    contentWidth: width
                )
                if abs(x - leadingX) <= hitRadius
                    || abs(x - trailingX) <= hitRadius {
                    return true
                }
            }
            timelineStart = timelineEnd
        }
        return false
    }

    private func ruler(
        width: CGFloat,
        duration: TimeInterval,
        scale: TimelineScale
    ) -> some View {
        let tickCount = min(80, max(4, Int(width / 110)))
        return ZStack(alignment: .topLeading) {
            Text("TIMELINE")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .padding(.leading, 8)

            ForEach(1...tickCount, id: \.self) { index in
                let time = duration * Double(index) / Double(tickCount)
                let x = scale.x(
                    forTime: time,
                    duration: duration,
                    contentWidth: width
                )
                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 1, height: 4)
                    .offset(x: x)

                Text(store.formatted(time))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 54)
                    .offset(
                        x: (x - 27).clamped(to: 0...max(0, width - 54)),
                        y: 7
                    )
            }
        }
        .clipped()
    }

    private func clipTrack(
        width: CGFloat,
        duration: TimeInterval,
        scale: TimelineScale
    ) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 7)
                .fill(.white.opacity(0.025))

            if store.project.clips.isEmpty {
                Text("Recorded clips appear here")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 0) {
                    ForEach(
                        Array(store.project.clips.enumerated()),
                        id: \.element.id
                    ) { index, clip in
                    let selected = clip.id == store.selectedClipID
                    let hovered =
                        store.hoveredTimelineBlock == .clip(clip.id)
                    let emphasized = selected || hovered
                    let timelineStart = store.project.clips[..<index].reduce(0) {
                        $0 + $1.timelineDuration
                    }
                    let clipStartX = scale.x(
                        forTime: timelineStart,
                        duration: duration,
                        contentWidth: width
                    )
                    let clipEndX = scale.x(
                        forTime: timelineStart + clip.timelineDuration,
                        duration: duration,
                        contentWidth: width
                    )
                    let clipWidth = max(1, clipEndX - clipStartX)
                    TimelineClipFilmstrip(
                        clip: clip,
                        index: index,
                        selected: selected,
                        hovered: hovered,
                        trimmingEnabled: store.activeTimelineTool == .selection,
                        thumbnails: store.timelineThumbnails,
                        waveformSamples: store.audioAnalysis.waveform,
                        sourceDuration: store.sourceDuration,
                        appLanguage: store.appLanguage,
                        timelineSecondsPerPoint: scale.timeDelta(
                            forPointDistance: 1,
                            duration: duration,
                            contentWidth: width
                        ),
                        onSelect: {
                            store.selectedClipID = clip.id
                            store.inspectorPanel = .clip
                        },
                        onTrimChange: { isLeading, sourceTime in
                            store.setClipTrimEdge(
                                clipID: clip.id,
                                isLeading: isLeading,
                                sourceTime: sourceTime
                            )
                        },
                        onEditBegan: {
                            store.beginContinuousTimelineEdit(.clip)
                        },
                        onEditEnded: {
                            store.endContinuousTimelineEdit()
                        }
                    )
                    .frame(width: clipWidth)
                    .clipped()
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                    .accessibilityIdentifier("timeline.clip.\(clip.id.uuidString)")
                    .accessibilityValue(hovered ? "Hovered" : (selected ? "Selected" : ""))
                    .onTapGesture {
                        if store.activeTimelineTool == .selection {
                            store.selectedClipID = clip.id
                            store.inspectorPanel = .clip
                        }
                    }
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard store.activeTimelineTool == .split else {
                                    return
                                }
                                let splitTime = (
                                    timelineStart
                                        + Double(value.location.x)
                                            * scale.timeDelta(
                                                forPointDistance: 1,
                                                duration: duration,
                                                contentWidth: width
                                            )
                                ).clamped(
                                    to: timelineStart...(timelineStart
                                        + clip.timelineDuration)
                                )
                                store.split(at: splitTime)
                                store.setHoveredClip(
                                    atTimelineTime: splitTime
                                )
                            }
                    )
                    .onHover { hovering in
                        store.setHoveredTimelineBlock(
                            .clip(clip.id),
                            hovering: hovering
                        )
                        updateSplitCursor(
                            hovering
                                && store.activeTimelineTool == .split
                        )
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            store.deleteClip(id: clip.id)
                        } label: {
                            Label("Delete clip", systemImage: "trash")
                        }
                        .disabled(store.project.clips.count <= 1)

                        Divider()

                        Menu("Set speed") {
                            ForEach(
                                [0.5, 0.75, 1, 1.25, 1.5, 2, 4],
                                id: \.self
                            ) { speed in
                                Button {
                                    store.selectedClipID = clip.id
                                    store.updateSelectedClip(
                                        playbackRate: speed
                                    )
                                } label: {
                                    if abs(clip.playbackRate - speed) < 0.001 {
                                        Label(
                                            playbackRateLabel(speed),
                                            systemImage: "checkmark"
                                        )
                                    } else {
                                        Text(playbackRateLabel(speed))
                                    }
                                }
                            }
                        }

                        Menu("Set volume") {
                            ForEach(
                                [0, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4],
                                id: \.self
                            ) { volume in
                                Button {
                                    store.selectedClipID = clip.id
                                    store.updateSelectedClip(volume: volume)
                                } label: {
                                    if abs(clip.volume - volume) < 0.001 {
                                        Label(
                                            "\(Int(volume * 100))%",
                                            systemImage: "checkmark"
                                        )
                                    } else {
                                        Text("\(Int(volume * 100))%")
                                    }
                                }
                            }
                        }

                        Button {
                            store.selectedClipID = clip.id
                            store.splitAtPlayhead()
                        } label: {
                            Label(
                                "Split at current time",
                                systemImage: "scissors"
                            )
                        }
                        .disabled(
                            store.playhead <= timelineStart + 0.05
                                || store.playhead
                                    >= timelineStart
                                        + clip.timelineDuration
                                        - 0.05
                        )

                        Divider()

                        Button {
                            store.selectedClipID = clip.id
                            store.resetSelectedTrim()
                        } label: {
                            Text("Reset trim")
                        }

                        Button {
                            store.selectedClipID = clip.id
                            store.mergeSelectedClip(withNext: true)
                        } label: {
                            Text("Merge with next")
                        }
                        .disabled(index >= store.project.clips.count - 1)

                        Button {
                            store.selectedClipID = clip.id
                            store.mergeSelectedClip(withNext: false)
                        } label: {
                            Text("Merge with previous")
                        }
                        .disabled(index == 0)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(
                                emphasized
                                    ? StudioTheme.accentBright
                                    : Color.white.opacity(0.12),
                                lineWidth: emphasized ? 1.5 : 1
                            )
                    }
                }
                }
                .frame(width: width, height: 104, alignment: .leading)

                // Transition markers on the cuts between adjacent clips.
                ForEach(
                    Array(store.project.transitionJunctions().enumerated()),
                    id: \.element.leftClipID
                ) { _, junction in
                    cutSeam(
                        x: scale.x(
                            forTime: junction.time,
                            duration: duration,
                            contentWidth: width
                        )
                    )
                    transitionMarker(
                        junction: junction,
                        x: scale.x(
                            forTime: junction.time,
                            duration: duration,
                            contentWidth: width
                        ),
                        pxPerSecond: width / max(0.01, CGFloat(duration))
                    )
                }

            }
        }
    }

    private func cutSeam(x: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(StudioTheme.canvas)
                .frame(width: 5, height: 104)
            HStack(spacing: 2) {
                Rectangle()
                    .fill(.white.opacity(0.24))
                    .frame(width: 1)
                Rectangle()
                    .fill(.black.opacity(0.8))
                    .frame(width: 1)
            }
            .frame(height: 104)
        }
        .offset(x: x - 2.5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .zIndex(4)
    }

    private func updateSplitCursor(_ active: Bool) {
        if active, !splitCursorPushed {
            NSCursor.crosshair.push()
            splitCursorPushed = true
        } else if !active, splitCursorPushed {
            NSCursor.pop()
            splitCursorPushed = false
        }
    }

    private func playbackRateLabel(_ rate: Double) -> String {
        let hundredths = (rate * 100).rounded()
        if hundredths.truncatingRemainder(dividingBy: 100) == 0 {
            return String(format: "%.0f×", rate)
        }
        if hundredths.truncatingRemainder(dividingBy: 10) == 0 {
            return String(format: "%.1f×", rate)
        }
        return String(format: "%.2f×", rate)
    }

    /// CapCut-style marker on a clip junction: a faint plus badge when the
    /// cut is empty (tap applies the current template, or drop a dragged
    /// template here), or a filled badge showing the placed transition.
    private func transitionMarker(
        junction: TransitionJunction,
        x: CGFloat,
        pxPerSecond: CGFloat
    ) -> some View {
        let transition = junction.transition
        let isSelected = transition?.id == store.selectedTransitionID
        let markerWidth: CGFloat = transition.map {
            max(22, min(64, CGFloat($0.duration) * pxPerSecond))
        } ?? 14

        return Group {
            if let transition {
                Image(systemName: transition.style.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(
                        isSelected
                            ? Color.accentColor : Color.black.opacity(0.75)
                    )
                    .frame(width: markerWidth, height: 16)
                    .background(
                        Capsule().fill(
                            isSelected
                                ? Color.accentColor.opacity(0.25)
                                : Color.white.opacity(0.88)
                        )
                    )
                    .overlay(
                        Capsule().stroke(
                            isSelected
                                ? Color.accentColor
                                : Color.black.opacity(0.35),
                            lineWidth: isSelected ? 1.5 : 0.5
                        )
                    )
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .overlay(
                        Circle().stroke(
                            Color.white.opacity(0.5),
                            lineWidth: 0.5
                        )
                    )
            }
        }
        .contentShape(Rectangle())
        .offset(x: x - markerWidth / 2)
        .onTapGesture {
            if let transition {
                store.selectedTransitionID = transition.id
                store.inspectorPanel = .transition
            } else {
                store.applyTransition(
                    store.transitionStyle,
                    toJunction: junction
                )
            }
        }
        .dropDestination(for: String.self) { payloads, _ in
            guard let raw = payloads.first,
                  let style = ClipTransitionStyle(rawValue: raw) else {
                return false
            }
            store.applyTransition(style, toJunction: junction)
            return true
        }
        .contextMenu {
            if transition != nil {
                Button(role: .destructive) {
                    store.selectedTransitionID = transition?.id
                    store.removeSelectedTransition()
                } label: {
                    Label("Remove transition", systemImage: "trash")
                }
            }
        }
        .accessibilityIdentifier(
            "timeline.transition.\(junction.leftClipID.uuidString)"
        )
        .zIndex(5)
    }

    private func waveform(for clip: TimelineClip) -> some View {
        GeometryReader { geometry in
            Path { path in
                let mid = geometry.size.height / 2
                let bars = TimelineWaveformGeometry.bars(
                    samples: store.audioAnalysis.waveform,
                    sourceDuration: store.sourceDuration,
                    clip: clip,
                    canvasSize: geometry.size
                )
                for bar in bars {
                    path.move(
                        to: CGPoint(
                            x: bar.x,
                            y: mid - bar.halfHeight
                        )
                    )
                    path.addLine(
                        to: CGPoint(
                            x: bar.x,
                            y: mid + bar.halfHeight
                        )
                    )
                }
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
    }

    private func zoomTrack(
        width: CGFloat,
        duration: TimeInterval,
        scale: TimelineScale
    ) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 7)
                .fill(.white.opacity(0.025))

            Text("ZOOMS")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .padding(.leading, 8)

            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    rangeCreationGesture(
                        width: width,
                        duration: duration,
                        scale: scale,
                        draftStart: $zoomDraftStart,
                        draftEnd: $zoomDraftEnd
                    ) { start, rangeDuration in
                        store.addZoom(
                            start: start,
                            duration: rangeDuration
                        )
                    }
                )

            if let zoomDraftStart, let zoomDraftEnd {
                draftRange(
                    start: min(zoomDraftStart, zoomDraftEnd),
                    end: max(zoomDraftStart, zoomDraftEnd),
                    width: width,
                    duration: duration,
                    scale: scale,
                    color: StudioTheme.zoom
                )
            }

            ForEach(store.project.zooms) { zoom in
                let selected = zoom.id == store.selectedZoomID
                let hovered =
                    store.hoveredTimelineBlock == .zoom(zoom.id)
                ZoomRangeBar(
                    zoom: zoom,
                    selected: selected || hovered,
                    splitMode: store.activeTimelineTool == .split,
                    trackWidth: width,
                    timelineDuration: duration,
                    timelineScale: scale,
                    onSelect: {
                        store.selectedZoomID = zoom.id
                        store.inspectorPanel = .zoom
                        store.seek(to: zoom.start + 0.05)
                    },
                    onRangeChange: { start, zoomDuration, edit in
                        store.setZoomRange(
                            id: zoom.id,
                            start: start,
                            duration: zoomDuration,
                            edit: edit
                        )
                    },
                    onEditBegan: {
                        store.beginContinuousTimelineEdit(.zoom)
                    },
                    onEditEnded: {
                        store.endContinuousTimelineEdit()
                    },
                    onSplit: { splitTime in
                        store.splitZoom(
                            id: zoom.id,
                            at: splitTime
                        )
                    }
                )
                .onHover { hovering in
                    store.setHoveredTimelineBlock(
                        .zoom(zoom.id),
                        hovering: hovering
                    )
                }
                .frame(
                    width: max(
                        1,
                        scale.x(
                            forTime: zoom.end,
                            duration: duration,
                            contentWidth: width
                        ) - scale.x(
                            forTime: zoom.start,
                            duration: duration,
                            contentWidth: width
                        )
                    ),
                    height: 27
                )
                .offset(
                    x: scale.x(
                        forTime: zoom.start,
                        duration: duration,
                        contentWidth: width
                    ),
                    y: 6
                )
                .zIndex(selected || hovered ? 1 : 0)
                .contextMenu {
                    Button {
                        store.selectedZoomID = zoom.id
                        store.splitZoom(
                            id: zoom.id,
                            at: store.playhead
                        )
                    } label: {
                        Label(
                            "Split zoom at current time",
                            systemImage: "scissors"
                        )
                    }
                    .disabled(
                        store.playhead <= zoom.start + 0.1
                            || store.playhead >= zoom.end - 0.1
                    )

                    Button(role: .destructive) {
                        store.selectedZoomID = zoom.id
                        store.deleteSelectedZoom()
                    } label: {
                        Label("Delete zoom", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func playhead(
        width: CGFloat,
        duration: TimeInterval,
        scale: TimelineScale
    ) -> some View {
        let x = scale.x(
            forTime: store.playhead,
            duration: duration,
            contentWidth: width
        )
        return ZStack(alignment: .top) {
            Rectangle()
                .fill(StudioTheme.playhead)
                .frame(width: 1.5, height: 228)
                .offset(y: 7)
            Image(systemName: "diamond.fill")
                .font(.system(size: 10))
                .foregroundStyle(StudioTheme.playhead)
        }
        .frame(width: 14)
        .offset(x: x - 7)
        .allowsHitTesting(false)
    }

    private func privacyTrack(
        width: CGFloat,
        duration: TimeInterval,
        scale: TimelineScale
    ) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 7)
                .fill(.white.opacity(0.025))

            Text("PRIVACY")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .padding(.leading, 8)

            ForEach(store.project.redactions) { redaction in
                let selected = redaction.id == store.selectedRedactionID
                let hovered =
                    store.hoveredTimelineBlock == .redaction(redaction.id)
                RedactionRangeBar(
                    redaction: redaction,
                    selected: selected || hovered,
                    trackWidth: width,
                    timelineDuration: duration,
                    timelineScale: scale,
                    onSelect: {
                        store.selectedRedactionID = redaction.id
                        store.inspectorPanel = .privacy
                        store.seek(to: redaction.start + 0.05)
                    },
                    onRangeChange: { start, redactionDuration in
                        store.setRedactionRange(
                            id: redaction.id,
                            start: start,
                            duration: redactionDuration
                        )
                    },
                    onEditBegan: {
                        store.beginContinuousTimelineEdit(.redaction)
                    },
                    onEditEnded: {
                        store.endContinuousTimelineEdit()
                    }
                )
                .onHover { hovering in
                    store.setHoveredTimelineBlock(
                        .redaction(redaction.id),
                        hovering: hovering
                    )
                }
                .frame(
                    width: max(
                        1,
                        scale.x(
                            forTime: redaction.end,
                            duration: duration,
                            contentWidth: width
                        ) - scale.x(
                            forTime: redaction.start,
                            duration: duration,
                            contentWidth: width
                        )
                    ),
                    height: 27
                )
                .offset(
                    x: scale.x(
                        forTime: redaction.start,
                        duration: duration,
                        contentWidth: width
                    ),
                    y: 6
                )
                .zIndex(selected || hovered ? 1 : 0)
                .contextMenu {
                    Button(role: .destructive) {
                        store.selectedRedactionID = redaction.id
                        store.deleteSelectedRedaction()
                    } label: {
                        Label(
                            redaction.resolvedPresentation == .spotlight
                                ? "Delete spotlight"
                                : "Delete privacy blur",
                            systemImage: "trash"
                        )
                    }
                }
            }
        }
    }

    private func annotationTrack(
        width: CGFloat,
        duration: TimeInterval,
        scale: TimelineScale
    ) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 7)
                .fill(.white.opacity(0.025))

            Text("ANNOTATIONS")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .padding(.leading, 8)

            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    rangeCreationGesture(
                        width: width,
                        duration: duration,
                        scale: scale,
                        draftStart: $annotationDraftStart,
                        draftEnd: $annotationDraftEnd
                    ) { start, rangeDuration in
                        store.addDefaultAnnotationRange(
                            start: start,
                            duration: rangeDuration
                        )
                    }
                )

            if let annotationDraftStart, let annotationDraftEnd {
                draftRange(
                    start: min(annotationDraftStart, annotationDraftEnd),
                    end: max(annotationDraftStart, annotationDraftEnd),
                    width: width,
                    duration: duration,
                    scale: scale,
                    color: .orange
                )
            }

            ForEach(store.project.annotations) { annotation in
                let selected = annotation.id == store.selectedAnnotationID
                let hovered =
                    store.hoveredTimelineBlock == .annotation(annotation.id)
                AnnotationRangeBar(
                    annotation: annotation,
                    selected: selected || hovered,
                    onSelect: {
                        store.selectedAnnotationID = annotation.id
                        store.inspectorPanel = .annotation
                        store.seek(to: annotation.start + 0.05)
                    },
                    onDelete: {
                        store.selectedAnnotationID = annotation.id
                        store.deleteSelectedAnnotation()
                    }
                )
                .onHover { hovering in
                    store.setHoveredTimelineBlock(
                        .annotation(annotation.id),
                        hovering: hovering
                    )
                }
                .frame(
                    width: max(
                        1,
                        scale.x(
                            forTime: annotation.end,
                            duration: duration,
                            contentWidth: width
                        ) - scale.x(
                            forTime: annotation.start,
                            duration: duration,
                            contentWidth: width
                        )
                    ),
                    height: 27
                )
                .offset(
                    x: scale.x(
                        forTime: annotation.start,
                        duration: duration,
                        contentWidth: width
                    ),
                    y: 6
                )
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            if annotationMoveOrigins[annotation.id] == nil {
                                store.beginContinuousTimelineEdit(.annotation)
                                annotationMoveOrigins[annotation.id] =
                                    annotation.start
                            }
                            guard let origin =
                                annotationMoveOrigins[annotation.id] else {
                                return
                            }
                            let delta = scale.timeDelta(
                                forPointDistance: value.translation.width,
                                duration: duration,
                                contentWidth: width
                            )
                            store.setAnnotationRange(
                                id: annotation.id,
                                start: (origin + delta).clamped(
                                    to: 0...max(
                                        0,
                                        duration - annotation.duration
                                    )
                                ),
                                duration: annotation.duration
                            )
                        }
                        .onEnded { _ in
                            annotationMoveOrigins[annotation.id] = nil
                            store.endContinuousTimelineEdit()
                        }
                )
                .zIndex(selected || hovered ? 2 : 1)
            }
        }
    }

    private func rangeCreationGesture(
        width: CGFloat,
        duration: TimeInterval,
        scale: TimelineScale,
        draftStart: Binding<TimeInterval?>,
        draftEnd: Binding<TimeInterval?>,
        onCreate: @escaping (TimeInterval, TimeInterval) -> Void
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let time = scale.time(
                    atX: value.location.x,
                    duration: duration,
                    contentWidth: width
                )
                if draftStart.wrappedValue == nil {
                    draftStart.wrappedValue = time
                }
                draftEnd.wrappedValue = time
            }
            .onEnded { value in
                guard let first = draftStart.wrappedValue else { return }
                let last = scale.time(
                    atX: value.location.x,
                    duration: duration,
                    contentWidth: width
                )
                let start = min(first, last)
                let draggedDuration = abs(last - first)
                let finalDuration = draggedDuration >= 0.12
                    ? draggedDuration
                    : min(store.zoomDuration, max(0.1, duration - start))
                onCreate(start, finalDuration)
                draftStart.wrappedValue = nil
                draftEnd.wrappedValue = nil
            }
    }

    private func draftRange(
        start: TimeInterval,
        end: TimeInterval,
        width: CGFloat,
        duration: TimeInterval,
        scale: TimelineScale,
        color: Color
    ) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color.opacity(0.28))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            }
            .frame(
                width: max(
                    3,
                    scale.x(
                        forTime: end,
                        duration: duration,
                        contentWidth: width
                    ) - scale.x(
                        forTime: start,
                        duration: duration,
                        contentWidth: width
                    )
                ),
                height: 27
            )
            .offset(
                x: scale.x(
                    forTime: start,
                    duration: duration,
                    contentWidth: width
                ),
                y: 6
            )
    }
}

private struct TimelinePlaybackAutoScroller: NSViewRepresentable {
    var playheadX: CGFloat
    var contentWidth: CGFloat
    var isPlaying: Bool

    func makeNSView(context: Context) -> TimelinePlaybackScrollObserver {
        TimelinePlaybackScrollObserver()
    }

    func updateNSView(
        _ nsView: TimelinePlaybackScrollObserver,
        context: Context
    ) {
        nsView.update(
            playheadX: playheadX,
            contentWidth: contentWidth,
            isPlaying: isPlaying
        )
    }
}

private final class TimelinePlaybackScrollObserver: NSView {
    private var playheadX: CGFloat = 0
    private var contentWidth: CGFloat = 1
    private var isPlaying = false
    private var isFollowingPlayback = false
    private var updateScheduled = false

    func update(
        playheadX: CGFloat,
        contentWidth: CGFloat,
        isPlaying: Bool
    ) {
        self.playheadX = playheadX
        self.contentWidth = max(1, contentWidth)
        self.isPlaying = isPlaying
        scheduleScrollUpdate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleScrollUpdate()
    }

    private func scheduleScrollUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            self.applyPlaybackFollow()
        }
    }

    private func applyPlaybackFollow() {
        guard let scrollView = enclosingScrollView else {
            isFollowingPlayback = false
            return
        }
        let visibleRect = scrollView.contentView.documentVisibleRect
        let documentWidth = max(
            contentWidth,
            scrollView.documentView?.bounds.width ?? 0
        )
        let decision = TimelinePlaybackFollowPolicy.resolve(
            playheadX: playheadX,
            visibleMinX: visibleRect.minX,
            viewportWidth: visibleRect.width,
            contentWidth: documentWidth,
            isPlaying: isPlaying,
            wasFollowing: isFollowingPlayback
        )
        isFollowingPlayback = decision.isFollowing
        guard let targetScrollX = decision.targetScrollX,
              abs(targetScrollX - visibleRect.minX) > 0.5 else {
            return
        }

        scrollView.contentView.scroll(
            to: NSPoint(
                x: targetScrollX,
                y: scrollView.contentView.bounds.origin.y
            )
        )
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

private struct AnnotationRangeBar: View {
    let annotation: EmphasisAnnotation
    let selected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(selected ? Color.orange : Color.orange.opacity(0.68))
            .overlay {
                HStack(spacing: 4) {
                    Image(
                        systemName: annotation.kind == .rectangle
                            ? "rectangle"
                            : "line.diagonal"
                    )
                    Text(
                        annotation.kind == .rectangle
                            ? "Rectangle"
                            : "Line"
                    )
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        selected ? Color.white : Color.white.opacity(0.18),
                        lineWidth: selected ? 1.2 : 1
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .contextMenu {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete annotation", systemImage: "trash")
                }
            }
    }
}

private struct TimelineClipFilmstrip: View {
    let clip: TimelineClip
    let index: Int
    let selected: Bool
    let hovered: Bool
    let trimmingEnabled: Bool
    let thumbnails: [TimelineThumbnailFrame]
    let waveformSamples: [Float]
    let sourceDuration: TimeInterval
    let appLanguage: AppLanguage
    let timelineSecondsPerPoint: TimeInterval
    let onSelect: () -> Void
    let onTrimChange: (Bool, TimeInterval) -> Void
    let onEditBegan: () -> Void
    let onEditEnded: () -> Void

    private struct TrimOrigin {
        let sourceTime: TimeInterval
        let timelineSecondsPerPoint: TimeInterval
    }

    @State private var leadingOrigin: TrimOrigin?
    @State private var trailingOrigin: TrimOrigin?
    @State private var trimCursorPushed = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    filmstrip(width: geometry.size.width)
                        .frame(height: 70)

                    ZStack(alignment: .bottomLeading) {
                        StudioTheme.accentMuted.opacity(0.82)
                        waveform
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)

                        if geometry.size.width >= 92 {
                            Label(
                                "\(Int((clip.volume * 100).rounded()))%",
                                systemImage: clip.volume <= 0.001
                                    ? "speaker.slash.fill"
                                    : "speaker.wave.2.fill"
                            )
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(.leading, 7)
                            .padding(.bottom, 3)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }

                clipBadge
                    .padding(.top, 5)
                    .padding(.leading, selected || hovered ? 18 : 7)

                if trimmingEnabled, selected || hovered {
                    HStack(spacing: 0) {
                        trimHandle(isLeading: true)
                        Spacer(minLength: 0)
                        trimHandle(isLeading: false)
                    }
                    .transition(.opacity)
                }
            }
            .background(StudioTheme.raisedSurface)
            .animation(.easeOut(duration: 0.12), value: selected || hovered)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                L10n.text(
                    "Edited clip %d",
                    language: appLanguage,
                    index + 1
                )
            )
        )
        .accessibilityHint("Drag either edge to trim the clip")
        .onDisappear {
            updateTrimCursor(false)
        }
    }

    private var clipBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "scissors")
            Text(segmentLabel)
            Text("\(clip.timelineDuration, specifier: "%.1f")s")
            if abs(clip.playbackRate - 1) > 0.001 {
                Text("\(clip.playbackRate, specifier: "%.1f")×")
            }
        }
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(
            selected || hovered
                ? StudioTheme.accent.opacity(0.94)
                : .black.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 5)
        )
    }

    private var segmentLabel: String {
        guard index >= 0,
              index < 26,
              let scalar = UnicodeScalar(65 + index) else {
            return "\(index + 1)"
        }
        return String(Character(scalar))
    }

    @ViewBuilder
    private func filmstrip(width: CGFloat) -> some View {
        let tileCount = max(1, Int(ceil(width / 82)))
        let tileWidth = width / CGFloat(tileCount)
        HStack(spacing: 1) {
            ForEach(0..<tileCount, id: \.self) { tile in
                let fraction = (Double(tile) + 0.5) / Double(tileCount)
                let sourceTime = clip.sourceStart + clip.duration * fraction
                Group {
                    if let image = nearestThumbnail(to: sourceTime) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFill()
                    } else {
                        StudioTheme.elevatedSurface
                            .overlay {
                                Image(systemName: "film")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.18))
                            }
                    }
                }
                .frame(width: tileWidth, height: 70)
                .clipped()
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
        }
    }

    private var waveform: some View {
        GeometryReader { geometry in
            Path { path in
                let mid = geometry.size.height / 2
                let bars = TimelineWaveformGeometry.bars(
                    samples: waveformSamples,
                    sourceDuration: sourceDuration,
                    clip: clip,
                    canvasSize: geometry.size
                )
                for bar in bars {
                    path.move(
                        to: CGPoint(x: bar.x, y: mid - bar.halfHeight)
                    )
                    path.addLine(
                        to: CGPoint(x: bar.x, y: mid + bar.halfHeight)
                    )
                }
            }
            .stroke(
                StudioTheme.accentBright.opacity(0.9),
                style: StrokeStyle(lineWidth: 1, lineCap: .round)
            )
        }
    }

    private func trimHandle(isLeading: Bool) -> some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: isLeading ? 6 : 2,
                bottomLeadingRadius: isLeading ? 6 : 2,
                bottomTrailingRadius: isLeading ? 2 : 6,
                topTrailingRadius: isLeading ? 2 : 6
            )
            .fill(StudioTheme.accentBright)

            Image(systemName: isLeading ? "chevron.right" : "chevron.left")
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(StudioTheme.canvas)
        }
        .frame(width: 14)
        .padding(.vertical, 3)
        .contentShape(Rectangle().inset(by: -7))
        .highPriorityGesture(trimGesture(isLeading: isLeading))
        .onHover { hovering in
            updateTrimCursor(hovering)
        }
        .help(isLeading ? "Trim clip start" : "Trim clip end")
        .accessibilityLabel(isLeading ? "Trim clip start" : "Trim clip end")
    }

    private func trimGesture(isLeading: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                onSelect()
                if isLeading, leadingOrigin == nil {
                    onEditBegan()
                    leadingOrigin = TrimOrigin(
                        sourceTime: clip.sourceStart,
                        timelineSecondsPerPoint: timelineSecondsPerPoint
                    )
                } else if !isLeading, trailingOrigin == nil {
                    onEditBegan()
                    trailingOrigin = TrimOrigin(
                        sourceTime: clip.sourceEnd,
                        timelineSecondsPerPoint: timelineSecondsPerPoint
                    )
                }
                guard let origin = isLeading
                    ? leadingOrigin : trailingOrigin else {
                    return
                }
                let sourceDelta = Double(value.translation.width)
                    * origin.timelineSecondsPerPoint
                    * clip.playbackRate
                onTrimChange(isLeading, origin.sourceTime + sourceDelta)
            }
            .onEnded { _ in
                if isLeading {
                    leadingOrigin = nil
                } else {
                    trailingOrigin = nil
                }
                onEditEnded()
            }
    }

    private func nearestThumbnail(to sourceTime: TimeInterval) -> NSImage? {
        guard !thumbnails.isEmpty else { return nil }
        var lower = 0
        var upper = thumbnails.count - 1
        while lower < upper {
            let middle = (lower + upper) / 2
            if thumbnails[middle].sourceTime < sourceTime {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        if lower == 0 { return thumbnails[0].image }
        let previous = thumbnails[lower - 1]
        let next = thumbnails[lower]
        return abs(previous.sourceTime - sourceTime)
            <= abs(next.sourceTime - sourceTime)
            ? previous.image : next.image
    }

    private func updateTrimCursor(_ active: Bool) {
        if active, !trimCursorPushed {
            NSCursor.resizeLeftRight.push()
            trimCursorPushed = true
        } else if !active, trimCursorPushed {
            NSCursor.pop()
            trimCursorPushed = false
        }
    }
}

private struct ZoomRangeBar: View {
    let zoom: ZoomEvent
    let selected: Bool
    let splitMode: Bool
    let trackWidth: CGFloat
    let timelineDuration: TimeInterval
    let timelineScale: TimelineScale
    let onSelect: () -> Void
    let onRangeChange: (
        TimeInterval,
        TimeInterval,
        ZoomRangeEdit
    ) -> Void
    let onEditBegan: () -> Void
    let onEditEnded: () -> Void
    let onSplit: (TimeInterval) -> Void

    @State private var isHovering = false
    @State private var splitCursorPushed = false
    @State private var moveOrigin: (start: TimeInterval, duration: TimeInterval)?
    @State private var leadingOrigin: (start: TimeInterval, duration: TimeInterval)?
    @State private var trailingOrigin: (start: TimeInterval, duration: TimeInterval)?

    private var secondsPerPoint: TimeInterval {
        timelineScale.timeDelta(
            forPointDistance: 1,
            duration: timelineDuration,
            contentWidth: trackWidth
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? StudioTheme.zoom : StudioTheme.zoom.opacity(0.68))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            selected ? Color.white.opacity(0.9) : Color.white.opacity(0.18),
                            lineWidth: selected ? 1.2 : 1
                        )
                }

            HStack(spacing: 0) {
                resizeHandle(isLeading: true)

                HStack(spacing: 4) {
                    Image(systemName: "plus.magnifyingglass")
                    Text("\(zoom.scale, specifier: "%.1f")×")
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(moveGesture)
                .onTapGesture(perform: onSelect)

                resizeHandle(isLeading: false)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(perform: onSelect)
        .overlay {
            if splitMode {
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let fraction = (
                                        value.location.x
                                            / max(1, geometry.size.width)
                                    ).clamped(to: 0...1)
                                    onSplit(
                                        zoom.start
                                            + zoom.duration
                                                * Double(fraction)
                                    )
                                }
                        )
                }
            }
        }
        .onHover { hovering in
            isHovering = hovering
            updateSplitCursor(hovering && splitMode)
        }
        .onChange(of: splitMode) {
            updateSplitCursor(isHovering && splitMode)
        }
        .onDisappear {
            updateSplitCursor(false)
        }
        .accessibilityLabel("Zoom")
        .accessibilityValue(
            "\(zoom.scale, specifier: "%.1f")×, \(zoom.duration, specifier: "%.2f") seconds"
        )
    }

    private func updateSplitCursor(_ active: Bool) {
        if active, !splitCursorPushed {
            NSCursor.crosshair.push()
            splitCursorPushed = true
        } else if !active, splitCursorPushed {
            NSCursor.pop()
            splitCursorPushed = false
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if moveOrigin == nil {
                    onEditBegan()
                    moveOrigin = (zoom.start, zoom.duration)
                    onSelect()
                }
                guard let origin = moveOrigin else { return }
                let maximumStart = max(0, timelineDuration - origin.duration)
                let newStart = (
                    origin.start + Double(value.translation.width) * secondsPerPoint
                ).clamped(to: 0...maximumStart)
                onRangeChange(
                    newStart,
                    origin.duration,
                    .move
                )
            }
            .onEnded { _ in
                moveOrigin = nil
                onEditEnded()
            }
    }

    private func resizeHandle(isLeading: Bool) -> some View {
        Capsule()
            .fill(.white.opacity(selected || isHovering ? 0.92 : 0.35))
            .frame(width: 7, height: 19)
            .padding(.horizontal, 3)
            .contentShape(Rectangle().inset(by: -5))
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSelect()
                        if isLeading {
                            if leadingOrigin == nil {
                                onEditBegan()
                                leadingOrigin = (zoom.start, zoom.duration)
                            }
                            guard let origin = leadingOrigin else { return }
                            let originalEnd = origin.start + origin.duration
                            let proposedStart = origin.start
                                + Double(value.translation.width) * secondsPerPoint
                            let newStart = proposedStart.clamped(
                                to: 0...max(0, originalEnd - 0.1)
                            )
                            onRangeChange(
                                newStart,
                                originalEnd - newStart,
                                .resizeLeading
                            )
                        } else {
                            if trailingOrigin == nil {
                                onEditBegan()
                                trailingOrigin = (zoom.start, zoom.duration)
                            }
                            guard let origin = trailingOrigin else { return }
                            let proposedDuration = origin.duration
                                + Double(value.translation.width) * secondsPerPoint
                            let newDuration = proposedDuration.clamped(
                                to: 0.1...max(0.1, timelineDuration - origin.start)
                            )
                            onRangeChange(
                                origin.start,
                                newDuration,
                                .resizeTrailing
                            )
                        }
                    }
                    .onEnded { _ in
                        if isLeading {
                            leadingOrigin = nil
                        } else {
                            trailingOrigin = nil
                        }
                        onEditEnded()
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

private struct RedactionRangeBar: View {
    let redaction: PrivacyRedaction
    let selected: Bool
    let trackWidth: CGFloat
    let timelineDuration: TimeInterval
    let timelineScale: TimelineScale
    let onSelect: () -> Void
    let onRangeChange: (TimeInterval, TimeInterval) -> Void
    let onEditBegan: () -> Void
    let onEditEnded: () -> Void

    @State private var isHovering = false
    @State private var moveOrigin: (start: TimeInterval, duration: TimeInterval)?
    @State private var leadingOrigin: (start: TimeInterval, duration: TimeInterval)?
    @State private var trailingOrigin: (start: TimeInterval, duration: TimeInterval)?

    private var secondsPerPoint: TimeInterval {
        timelineScale.timeDelta(
            forPointDistance: 1,
            duration: timelineDuration,
            contentWidth: trackWidth
        )
    }

    var body: some View {
        let isSpotlight = redaction.resolvedPresentation == .spotlight
        let isBlur = redaction.resolvedEffect == .blur
        let accent = isSpotlight
            ? Color.orange
            : (isBlur ? Color.cyan : Color.red)
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? accent : accent.opacity(0.62))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            selected
                                ? Color.white.opacity(0.9)
                                : Color.white.opacity(0.18),
                            lineWidth: selected ? 1.2 : 1
                        )
                }

            HStack(spacing: 0) {
                resizeHandle(isLeading: true)
                HStack(spacing: 4) {
                    Image(
                        systemName: isSpotlight
                            ? "light.beacon.max.fill"
                            : (isBlur ? "drop.fill" : "eye.slash.fill")
                    )
                    Text(
                        isSpotlight
                            ? "Spotlight"
                            : (isBlur ? "Blur" : "Redact")
                    )
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(moveGesture)
                .onTapGesture(perform: onSelect)
                resizeHandle(isLeading: false)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .accessibilityLabel(
            redaction.resolvedPresentation == .spotlight
                ? "Spotlight highlight"
                : "Privacy redaction"
        )
        .accessibilityValue(
            "\(redaction.duration, specifier: "%.2f") seconds"
        )
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if moveOrigin == nil {
                    onEditBegan()
                    moveOrigin = (redaction.start, redaction.duration)
                    onSelect()
                }
                guard let origin = moveOrigin else { return }
                let maximumStart = max(0, timelineDuration - origin.duration)
                let newStart = (
                    origin.start
                        + Double(value.translation.width) * secondsPerPoint
                ).clamped(to: 0...maximumStart)
                onRangeChange(newStart, origin.duration)
            }
            .onEnded { _ in
                moveOrigin = nil
                onEditEnded()
            }
    }

    private func resizeHandle(isLeading: Bool) -> some View {
        Capsule()
            .fill(.white.opacity(selected || isHovering ? 0.92 : 0.35))
            .frame(width: 7, height: 19)
            .padding(.horizontal, 3)
            .contentShape(Rectangle().inset(by: -5))
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSelect()
                        if isLeading {
                            if leadingOrigin == nil {
                                onEditBegan()
                                leadingOrigin = (
                                    redaction.start,
                                    redaction.duration
                                )
                            }
                            guard let origin = leadingOrigin else { return }
                            let originalEnd = origin.start + origin.duration
                            let proposedStart = origin.start
                                + Double(value.translation.width)
                                    * secondsPerPoint
                            let newStart = proposedStart.clamped(
                                to: 0...max(0, originalEnd - 0.1)
                            )
                            onRangeChange(
                                newStart,
                                originalEnd - newStart
                            )
                        } else {
                            if trailingOrigin == nil {
                                onEditBegan()
                                trailingOrigin = (
                                    redaction.start,
                                    redaction.duration
                                )
                            }
                            guard let origin = trailingOrigin else { return }
                            let proposedDuration = origin.duration
                                + Double(value.translation.width)
                                    * secondsPerPoint
                            let newDuration = proposedDuration.clamped(
                                to: 0.1...max(
                                    0.1,
                                    timelineDuration - origin.start
                                )
                            )
                            onRangeChange(origin.start, newDuration)
                        }
                    }
                    .onEnded { _ in
                        if isLeading {
                            leadingOrigin = nil
                        } else {
                            trailingOrigin = nil
                        }
                        onEditEnded()
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

extension ClipTransitionStyle {
    /// SF Symbol used for template cards and timeline junction badges.
    var symbol: String {
        switch self {
        case .fade: return "circle.fill"
        case .flash: return "sun.max.fill"
        case .zoom: return "arrow.up.left.and.arrow.down.right"
        }
    }
}
