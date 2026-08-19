import ScreenFreeCore
import SwiftUI

/// 录制设置页：进入录制的唯一配置入口（ADR 0002）。
/// 左侧分区导航 + 右侧内容 + 底部操作条；除口播稿外，所有控件
/// 默认还原为上一次真正开录时使用的配置。
struct RecordingSetupView: View {
    @ObservedObject var store: EditorStore
    @State private var section: SetupSection = .capture

    private enum SetupSection: String, CaseIterable, Identifiable {
        case capture = "Capture source"
        case audio = "Audio & Camera"
        case script = "Script"
        case options = "Recording options"

        var id: Self { self }

        var symbol: String {
            switch self {
            case .capture: return "display"
            case .audio: return "waveform"
            case .script: return "text.bubble"
            case .options: return "gearshape"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.06))

            HStack(spacing: 0) {
                sidebar
                Divider().overlay(.white.opacity(0.06))

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch section {
                        case .capture:
                            captureSection
                        case .audio:
                            audioSection
                        case .script:
                            scriptSection
                        case .options:
                            optionsSection
                        }
                        StudioCheckView(store: store)
                    }
                    .padding(24)
                    .frame(maxWidth: 660, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity)

            Divider().overlay(.white.opacity(0.06))
            footer
        }
        .background(StudioTheme.canvas)
        .sheet(isPresented: $store.isMicrophoneSelectionPresented) {
            MicrophoneSelectionSheet(store: store)
                .environment(\.locale, store.appLanguage.locale)
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
            store.dismissRecordingSetup()
            context.isHandled = true
        }
    }

    private var header: some View {
        HStack {
            Button {
                store.dismissRecordingSetup()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("New Recording")
                    .font(.system(size: 15, weight: .semibold))
                Text("Defaults to the last-used setup")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Color.clear
                .frame(width: 58, height: 8)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(StudioTheme.surface)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SetupSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    Label(
                        LocalizedStringKey(item.rawValue),
                        systemImage: item.symbol
                    )
                    .font(
                        .system(
                            size: 13,
                            weight: section == item ? .semibold : .regular
                        )
                    )
                    .foregroundStyle(section == item ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                section == item
                                    ? Color.white.opacity(0.08)
                                    : Color.clear
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if section == .script && !store.scriptHasText {
                Label("Empty script — the teleprompter stays hidden.", systemImage: "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
            }
        }
        .padding(12)
        .frame(width: 212, alignment: .topLeading)
        .background(StudioTheme.surface.opacity(0.6))
    }

    private var footer: some View {
        HStack {
            Label(
                store.scriptHasText
                    ? "The teleprompter shows while recording."
                    : "No script — the teleprompter stays hidden.",
                systemImage: "text.bubble"
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel") {
                store.dismissRecordingSetup()
            }

            Button {
                Task { await store.startRecording() }
            } label: {
                Label("Start recording", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                AccentButtonStyle(
                    colors: [StudioTheme.accentBright, StudioTheme.accent]
                )
            )
            .frame(width: 230)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(StudioTheme.surface)
    }

    // MARK: - 捕获源

    private var captureSection: some View {
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
                            Task {
                                await store.requestScreenRecordingPermission()
                            }
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
    }

    // MARK: - 音频与摄像头

    private var audioSection: some View {
        InspectorSection(title: "Audio & Camera") {
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

            Divider().overlay(.white.opacity(0.08))

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

            Divider().overlay(.white.opacity(0.08))

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
        }
    }

    // MARK: - 口播稿

    private var scriptSection: some View {
        InspectorSection(title: "Script") {
            HStack {
                Menu {
                    ForEach(store.recentScripts) { entry in
                        Button(entry.title) {
                            store.scriptText = entry.text
                        }
                    }
                } label: {
                    Label("Recent scripts", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(store.recentScripts.isEmpty)

                Spacer()

                Button("Clear") {
                    store.scriptText = ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $store.scriptText)
                    .font(.system(size: 13))
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(
                        .black.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                if store.scriptText.isEmpty {
                    Text("Paste or write the script to speak while recording…")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }

            Text("The teleprompter never enters the captured video.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Divider().overlay(.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 12) {
                Text("Teleprompter")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                LabeledSlider(
                    title: "Font size",
                    value: $store.prompterFontSize,
                    range: 16...48,
                    suffix: " pt"
                )

                LabeledSlider(
                    title: "Scroll speed",
                    value: $store.prompterSpeed,
                    range: 0.5...2.5,
                    suffix: "×"
                )

                Text("While recording, pause or adjust the speed on the teleprompter panel and drag it anywhere; it stays out of the captured video.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 录制选项

    private var optionsSection: some View {
        InspectorSection(title: "Recording options") {
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

            Text("Long right-button holds are kept so automatic zooms can be regenerated later.")
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

            Divider().overlay(.white.opacity(0.08))

            Text("ScreenFree captures the native display stream plus a separate 30 fps cursor path and click timeline.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
