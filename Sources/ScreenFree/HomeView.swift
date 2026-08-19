import SwiftUI

/// 应用根视图：按 `appScreen` 在首页 / 录制设置 / 编辑器之间切换。
/// 错误弹窗挂在这一层，保证任何界面状态下的错误都只有一处呈现。
struct AppRootView: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        Group {
            switch store.appScreen {
            case .home:
                HomeView(store: store)
            case .recordingSetup:
                RecordingSetupView(store: store)
            case .editor:
                MainView(store: store)
            }
        }
        .background(StudioTheme.canvas)
        .tint(StudioTheme.accent)
        .preferredColorScheme(.dark)
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
    }
}

/// 启动首页：录制 / 剪辑双入口（ADR 0002）。
/// 剪辑卡片承载原有历史能力：最近录制、打开项目、拖拽导入。
struct HomeView: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        VStack(spacing: 44) {
            VStack(spacing: 8) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(StudioTheme.accentGradient)
                Text("ScreenFree")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("Screen recording and editing")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 26) {
                recordCard
                editCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StudioTheme.emptyStateBackground)
        .onAppear {
            store.refreshRecordingHistory()
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task { await store.openExternalURL(url) }
            return true
        }
    }

    private var recordCard: some View {
        Button {
            store.presentRecordingSetup()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(StudioTheme.danger.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Image(systemName: "record.circle")
                        .font(.system(size: 38))
                        .foregroundStyle(StudioTheme.danger)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start recording")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(
                        "Screen, window, or area — with an optional teleprompter for your script."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(22)
            .frame(width: 260, height: 240, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(StudioTheme.danger.opacity(0.32), lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }

    private var editCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "film.stack")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Edit")
                    .font(.system(size: 21, weight: .semibold))
                Spacer()
                Button {
                    store.openProject()
                } label: {
                    Text("Open Project…")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            Divider().overlay(.white.opacity(0.08))

            if store.recordingHistory.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 22, weight: .thin))
                        .foregroundStyle(.tertiary)
                    Text("No recordings yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button {
                        store.importVideo()
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(ToolbarButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .frame(height: 118)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(
                        store.recordingHistory.prefix(4)
                    ) { item in
                        Button {
                            Task {
                                await store.openRecordingFromHistory(item)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "waveform")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(item.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                Text(
                                    item.modifiedAt
                                        .formatted(.relative(presentation: .named))
                                )
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(.white.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
            Button {
                store.appScreen = .editor
            } label: {
                Label("Open the editor", systemImage: "scissors")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ToolbarButtonStyle())
        }
        .padding(22)
        .frame(width: 380, height: 240, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }
}
