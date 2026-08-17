// swiftformat:disable all
//
// PROTOTYPE — THROWAWAY. 不进生产，不做本地化，不做测试。
// 回答的问题：双入口首页 + 录制设置页 + 录制中提词器，整体结构应该长什么样？
// 三个结构上不同的变体（A/B/C），同一流程：首页 → 录制设置 → 录制画面（含可交互提词器 mock）。
// 运行：swift run ScreenFree --prototype-home
// 切换变体：左下角悬浮条，或键盘 ←/→（在文本框里输入时不会触发）。
// 决策定稿后：本文件与 ScreenFreeApp.swift 里的 --prototype-home 门控一并删除，
// 获胜方案按生产标准重写（本地化、UserDefaults/项目持久化、测试）。
//

import SwiftUI
import AppKit

// MARK: - 共享状态（全部内存态，不落盘）

private enum ProtoScreen {
    case home
    case setup
    case recording
}

private enum PrototypeVariant: String, CaseIterable {
    case a
    case b
    case c

    var label: String {
        switch self {
        case .a: return "A · 双卡片首页 + 分区设置页"
        case .b: return "B · 极简首页 + 三步向导"
        case .c: return "C · 首页即设置（单页）"
        }
    }
}

private struct ProtoRecentScript: Identifiable {
    let id = UUID()
    let title: String
    let snippet: String
    let text: String
}

private enum ProtoScript {
    static let sample = """
大家好，欢迎来到这一期视频。今天我要给大家介绍一款我自己一直在用的 macOS 录屏工具。

很多同学做产品演示的时候都会遇到同一个问题：录完的素材要花好几个小时去剪辑，Zoom 效果要一帧一帧打关键帧，鼠标点击要自己加高亮，非常痛苦。

这款工具的想法是把这些重复劳动全部交给软件。你只管正常操作，它会记录每一次鼠标点击、每一次按键，然后在时间线上自动生成缩放和聚拢的建议。

比如现在我在点击这个按钮，注意画面会自动推进到点击的位置，转场用的是缓动曲线，看起来非常顺滑，完全不需要手工调。

音频方面，系统声音和麦克风是两条独立轨道，剪辑的时候可以分别调音量、做标准化，不会互相干扰。

口播的部分就交给提词器：你现在看到的这个面板会按你说话的速度自动向上滚动，快了慢了都可以用快捷键实时调整，而且它永远不会被录进成片里。

最后导出的时候，所见即所得——预览里的每一个效果都会完整出现在 MP4 里。好了，我们下期再见。
"""

    static let recent: [ProtoRecentScript] = [
        ProtoRecentScript(
            title: "功能演示脚本",
            snippet: "大家好，欢迎来到这一期视频。今天我要给大家介绍……",
            text: sample
        ),
        ProtoRecentScript(
            title: "版本更新口播 0.2",
            snippet: "这次更新主要修复了三个问题……",
            text: "这次更新主要修复了三个问题。\n\n第一个是时间线在放大状态下的视口跟随，播放时不会再跑丢了。\n\n第二个是波形图，现在静音区间是真的空白。\n\n第三个是导出比例，16:9 不再出现黑边。感谢大家的反馈，我们继续。"
        ),
        ProtoRecentScript(
            title: "产品介绍开场",
            snippet: "如果我说录屏可以像写文档一样简单……",
            text: "如果我说录屏可以像写文档一样简单，你信吗？\n\n这一条视频只用了一次录制，零剪辑。\n\n秘密就在于所有的效果都是非破坏性的元数据，随时可以改。"
        ),
    ]
}

private final class ProtoSession: ObservableObject {
    @Published var variant: PrototypeVariant = .a
    @Published var screen: ProtoScreen = .home

    // 录制设置页里的可调项（三个变体共享，切变体不丢）
    @Published var scriptText: String = ProtoScript.sample
    @Published var prompterFontSize: Double = 22
    @Published var prompterSpeed: Double = 1.0

    // 捕获/音频 mock 配置（只为让设置页看起来真实）
    @Published var captureMode = 0 // 0 屏幕 1 窗口 2 区域
    @Published var micOn = true
    @Published var systemAudioOn = true
    @Published var cameraOn = false
    @Published var countdownOn = true
    @Published var highlightBorderOn = true
    @Published var autoZoomOn = true

    // 录制画面状态
    @Published var recordingPaused = false
    @Published var prompterPaused = false
    @Published var prompterProgress: Double = 0
    @Published var elapsed: Double = 0

    var paragraphs: [String] {
        scriptText
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func resetRecordingState() {
        recordingPaused = false
        prompterPaused = false
        prompterProgress = 0
        elapsed = 0
    }

    var elapsedLabel: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - 根视图 + 悬浮切换条 + 键盘

struct PrototypeFlowRoot: View {
    @StateObject private var session = ProtoSession()
    @State private var keyMonitor: Any?

    var body: some View {
        ZStack {
            switch session.screen {
            case .home:
                HomeScreen()
            case .setup:
                SetupScreen()
            case .recording:
                RecordingScreen()
            }
            VStack { Spacer(); switcherBar.padding(.leading, 18).padding(.bottom, 18) }
        }
        .environmentObject(session)
        .frame(minWidth: 1120, minHeight: 720)
        .preferredColorScheme(.dark)
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
    }

    private var switcherBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(.yellow)
            Text("原型")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.yellow)
            Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 14)
            Button {
                cycleVariant(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            Text(session.variant.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 190, alignment: .center)
            Button {
                cycleVariant(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 14)
            Button {
                session.resetRecordingState()
                session.screen = .home
            } label: {
                Label("首页", systemImage: "house")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            Text("(←/→ 切换)")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(.black.opacity(0.88))
        )
        .overlay(
            Capsule().stroke(.yellow.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 10)
    }

    private func cycleVariant(_ direction: Int) {
        let all = PrototypeVariant.allCases
        let index = all.firstIndex(of: session.variant) ?? 0
        session.variant = all[(index + direction + all.count) % all.count]
        session.resetRecordingState()
        session.screen = .home
    }

    // MARK: 键盘（避开文本输入状态）

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 正在文本输入时不拦截
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            let option = event.modifierFlags.contains(.option)

            if option {
                switch event.keyCode {
                case 49: // ⌥空格：暂停/继续提词
                    session.prompterPaused.toggle()
                    return nil
                case 126: // ⌥↑ 提速
                    session.prompterSpeed = min(2.5, session.prompterSpeed + 0.25)
                    return nil
                case 125: // ⌥↓ 降速
                    session.prompterSpeed = max(0.5, session.prompterSpeed - 0.25)
                    return nil
                default:
                    return event
                }
            }

            switch event.keyCode {
            case 123: // ← 切换变体
                cycleVariant(-1)
                return nil
            case 124: // → 切换变体
                cycleVariant(1)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

// MARK: - 流程路由

private struct HomeScreen: View {
    @EnvironmentObject private var session: ProtoSession

    var body: some View {
        switch session.variant {
        case .a: VariantAHome()
        case .b: VariantBHome()
        case .c: VariantCHome()
        }
    }
}

private struct SetupScreen: View {
    @EnvironmentObject private var session: ProtoSession

    var body: some View {
        switch session.variant {
        case .a: VariantASetup()
        case .b: VariantBSetup()
        case .c: VariantCSetup()
        }
    }
}

private struct RecordingScreen: View {
    @EnvironmentObject private var session: ProtoSession

    private var prompterStyle: ProtoPrompterStyle {
        switch session.variant {
        case .a: return .bottomCenterPanel
        case .b: return .rightColumn
        case .c: return .wideStrip
        }
    }

    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ProtoRecordingStage(style: prompterStyle)
            .onReceive(ticker) { _ in
                if !session.recordingPaused && !session.prompterPaused {
                    session.elapsed += 0.1
                    session.prompterProgress = min(
                        1,
                        session.prompterProgress + 0.006 * session.prompterSpeed
                    )
                }
            }
    }
}

// MARK: - 变体 A：双卡片首页 + 分区设置页

private struct VariantAHome: View {
    @EnvironmentObject private var session: ProtoSession

    private let recentRecordings: [(name: String, meta: String)] = [
        ("功能演示 0816.mp4", "02:41 · 昨天"),
        ("版本更新口播 0.2.mp4", "01:07 · 8月14日"),
        ("产品介绍开场.mp4", "00:38 · 8月11日"),
    ]

    var body: some View {
        VStack(spacing: 44) {
            VStack(spacing: 8) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.white)
                Text("ScreenFree")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("录屏 · 剪辑 · 一步到位")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 28) {
                // 录制大卡
                Button {
                    session.screen = .setup
                } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.16))
                                .frame(width: 74, height: 74)
                            Image(systemName: "record.circle")
                                .font(.system(size: 40))
                                .foregroundStyle(.red)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("开始录制")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("屏幕 · 窗口 · 区域\n口播稿提词器 · 麦克风")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                    .padding(24)
                    .frame(width: 260, height: 240, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.white.opacity(0.045))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(.red.opacity(0.35), lineWidth: 1.2)
                    )
                }
                .buttonStyle(.plain)

                // 剪辑大卡
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.85))
                        Text("剪辑")
                            .font(.system(size: 22, weight: .semibold))
                        Spacer()
                        Text("打开项目…")
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(recentRecordings, id: \.name) { item in
                            HStack {
                                Image(systemName: "waveform")
                                    .foregroundStyle(.secondary)
                                Text(item.name)
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                                Text(item.meta)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Spacer()
                }
                .padding(24)
                .frame(width: 380, height: 240, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.white.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
    }
}

private enum ProtoSetupSection: String, CaseIterable {
    case capture = "捕获源"
    case audio = "音频与摄像头"
    case script = "口播稿"
    case options = "录制选项"

    var icon: String {
        switch self {
        case .capture: return "display"
        case .audio: return "mic"
        case .script: return "text.bubble"
        case .options: return "gearshape"
        }
    }
}

private struct VariantASetup: View {
    @EnvironmentObject private var session: ProtoSession
    @State private var section: ProtoSetupSection = .capture

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Button("← 返回") {
                    session.screen = .home
                }
                Spacer()
                Text("新录制")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("默认沿用上次配置")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            HStack(spacing: 0) {
                // 左侧分区导航
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ProtoSetupSection.allCases, id: \.self) { item in
                        Button {
                            section = item
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item.icon)
                                    .frame(width: 18)
                                Text(item.rawValue)
                                    .font(.system(size: 13, weight: section == item ? .semibold : .regular))
                                if item == .script && !session.scriptHasText {
                                    Spacer()
                                    Text("空")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(section == item ? Color.white.opacity(0.1) : .clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(16)
                .frame(width: 220, alignment: .topLeading)

                Divider()

                // 右侧内容
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch section {
                        case .capture: ProtoCaptureSection()
                        case .audio: ProtoAudioSection()
                        case .script: ProtoScriptSection()
                        case .options: ProtoOptionsSection()
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            // 底部操作条
            HStack {
                Text("提示词器：\(session.scriptHasText ? "有稿即显示" : "无稿不显示")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") {
                    session.screen = .home
                }
                Button {
                    session.resetRecordingState()
                    session.screen = .recording
                } label: {
                    Label("开始录制", systemImage: "record.fill")
                        .padding(.horizontal, 6)
                }
                .controlSize(.large)
                .tint(.red)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
    }
}

// MARK: - 变体 B：极简首页 + 三步向导

private struct VariantBHome: View {
    @EnvironmentObject private var session: ProtoSession

    var body: some View {
        VStack(spacing: 36) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.white)
            VStack(spacing: 14) {
                Button {
                    session.screen = .setup
                } label: {
                    HStack {
                        Image(systemName: "record.circle")
                            .font(.system(size: 26))
                        Text("录制")
                                .font(.system(size: 19, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .frame(width: 380)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)

                Button {
                    session.screen = .setup // 原型里指向同一向导，实际应进编辑器/历史
                } label: {
                    HStack {
                        Image(systemName: "film.stack")
                            .font(.system(size: 26))
                        Text("剪辑")
                                .font(.system(size: 19, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .frame(width: 380)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            Text("录制会先走三步配置，全部默认上次的选择")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct VariantBSetup: View {
    @EnvironmentObject private var session: ProtoSession
    @State private var step = 0
    private let steps = ["画面", "声音", "口播稿"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("← 返回") { session.screen = .home }
                Spacer()
                Text("新录制 · \(steps[step])")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("第 \(step + 1)/3 步")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()

            // 步骤指示器
            HStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(index <= step ? Color.red : Color.white.opacity(0.15))
                                .frame(width: 24, height: 24)
                            if index < step {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(index + 1)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(index == step ? .white : .secondary)
                            }
                        }
                        Text(title)
                            .font(.system(size: 12, weight: index == step ? .semibold : .regular))
                            .foregroundStyle(index == step ? .primary : .secondary)
                    }
                    if index < steps.count - 1 {
                        Rectangle()
                            .fill(index < step ? Color.red : Color.white.opacity(0.15))
                            .frame(height: 1.5)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                    }
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 20)

            // 步骤内容
            VStack(alignment: .leading, spacing: 24) {
                switch step {
                case 0: ProtoCaptureSection()
                case 1: ProtoAudioSection()
                default: ProtoScriptSection()
                }
            }
            .padding(.horizontal, 60)
            .frame(maxWidth: 720, maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity)

            Divider()

            HStack {
                if step > 0 {
                    Button("上一步") { step -= 1 }
                }
                Spacer()
                Button("取消") { session.screen = .home }
                if step < steps.count - 1 {
                    Button("下一步") { step += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        session.resetRecordingState()
                        session.screen = .recording
                    } label: {
                        Label("开始录制", systemImage: "record.fill")
                            .padding(.horizontal, 6)
                    }
                    .controlSize(.large)
                    .tint(.red)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - 变体 C：首页即设置（单页，无独立设置页）

private struct VariantCHome: View {
    @EnvironmentObject private var session: ProtoSession
    @State private var showingHistory = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ScreenFree")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    showingHistory = true
                } label: {
                    Label("剪辑", systemImage: "film.stack")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    // 主行动区
                    VStack(spacing: 14) {
                        Button {
                            session.resetRecordingState()
                            session.screen = .recording
                        } label: {
                            VStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.red.opacity(0.18))
                                        .frame(width: 88, height: 88)
                                    Image(systemName: "record.circle.fill")
                                        .font(.system(size: 52))
                                        .foregroundStyle(.red)
                                }
                                Text("开始录制")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        Text("内置显示器 · 麦克风开 · 系统声音开 —— 沿用上次配置")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 16)

                    // 内联配置三卡
                    HStack(alignment: .top, spacing: 16) {
                        ProtoInlineCard(title: "捕获源", icon: "display") {
                            Picker("", selection: $session.captureMode) {
                                Text("屏幕").tag(0)
                                Text("窗口").tag(1)
                                Text("区域").tag(2)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            Text(session.captureMode == 0 ? "内置显示器 (3024×1964)" : session.captureMode == 1 ? "最近使用的窗口" : "框选区域")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        ProtoInlineCard(title: "声音与画面", icon: "mic") {
                            ProtoCompactToggle(label: "麦克风", isOn: $session.micOn)
                            ProtoCompactToggle(label: "系统声音", isOn: $session.systemAudioOn)
                            ProtoCompactToggle(label: "摄像头", isOn: $session.cameraOn)
                        }
                        ProtoInlineCard(title: "口播稿", icon: "text.bubble") {
                            ProtoScriptSection(compact: true)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .sheet(isPresented: $showingHistory) {
            VStack(alignment: .leading, spacing: 12) {
                Text("最近录制")
                    .font(.system(size: 15, weight: .semibold))
                ForEach(["功能演示 0816.mp4 · 02:41", "版本更新口播 0.2.mp4 · 01:07", "产品介绍开场.mp4 · 00:38"], id: \.self) { row in
                    HStack {
                        Image(systemName: "waveform")
                        Text(row).font(.system(size: 12))
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
                Button("打开项目…") {}
                Button("完成") { showingHistory = false }
            }
            .padding(20)
            .frame(width: 420)
        }
    }
}

private struct VariantCSetup: View {
    // 变体 C 没有独立设置页；从首页直接开录。
    var body: some View {
        VariantCHome()
    }
}

private struct ProtoInlineCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1)))
    }
}

private struct ProtoCompactToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .font(.system(size: 12))
            .controlSize(.small)
    }
}

// MARK: - 设置区块（变体间复用的控件组）

private struct ProtoCaptureSection: View {
    @EnvironmentObject private var session: ProtoSession

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("捕获源").font(.system(size: 16, weight: .semibold))
            Picker("", selection: $session.captureMode) {
                Text("整个屏幕").tag(0)
                Text("单个窗口").tag(1)
                Text("框选区域").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 16) {
                ForEach([("内置显示器", "3024 × 1964", true), ("DELL U2723QE", "2560 × 1440", false)], id: \.0) { display in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: display.2 ? [.blue.opacity(0.25), .purple.opacity(0.2)] : [.gray.opacity(0.22), .gray.opacity(0.16)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .frame(width: 190, height: 120)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(display.2 ? Color.red : Color.white.opacity(0.15), lineWidth: 2)
                            )
                            .overlay(
                                Image(systemName: display.2 ? "checkmark.circle.fill" : "")
                                    .font(.system(size: 20))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                    .padding(6)
                            )
                        Text(display.0).font(.system(size: 12, weight: .medium))
                        Text(display.1).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            if session.captureMode == 2 {
                Label("开始后拖拽框选区域，虚线边框会标出范围", systemImage: "crop")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProtoAudioSection: View {
    @EnvironmentObject private var session: ProtoSession

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("音频与摄像头").font(.system(size: 16, weight: .semibold))
            ProtoCompactToggle(label: "麦克风（MacBook Pro 麦克风）", isOn: $session.micOn)
            ProtoCompactToggle(label: "系统声音", isOn: $session.systemAudioOn)
            ProtoCompactToggle(label: "摄像头画中画", isOn: $session.cameraOn)
            Label("麦克风与系统声音保持独立轨道，剪辑时可分别调整", systemImage: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProtoOptionsSection: View {
    @EnvironmentObject private var session: ProtoSession

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("录制选项").font(.system(size: 16, weight: .semibold))
            ProtoCompactToggle(label: "开始前倒计时（3 秒）", isOn: $session.countdownOn)
            ProtoCompactToggle(label: "录制区域高亮边框", isOn: $session.highlightBorderOn)
            ProtoCompactToggle(label: "点击处自动缩放", isOn: $session.autoZoomOn)
        }
    }
}

private struct ProtoScriptSection: View {
    @EnvironmentObject private var session: ProtoSession
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("口播稿").font(.system(size: compact ? 12 : 16, weight: .semibold))
                Spacer()
                Menu {
                    ForEach(ProtoScript.recent) { item in
                        Button(item.title) {
                            session.scriptText = item.text
                        }
                    }
                } label: {
                    Label("最近的稿子", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                if !compact {
                    Button {
                        session.scriptText = ""
                    } label: {
                        Text("清空")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            TextEditor(text: $session.scriptText)
                .font(.system(size: 13))
                .frame(height: compact ? 120 : 210)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 10) {
                Text("提词器").font(.system(size: 12, weight: .semibold))
                HStack {
                    Text("字号")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .leading)
                    Slider(value: $session.prompterFontSize, in: 16...48, step: 2)
                    Text("\(Int(session.prompterFontSize)) pt")
                        .font(.system(size: 11).monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                }
                HStack {
                    Text("滚动速度")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .leading)
                    Slider(value: $session.prompterSpeed, in: 0.5...2.5, step: 0.25)
                    Text(String(format: "×%.2f", session.prompterSpeed))
                        .font(.system(size: 11).monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                }
                Label("录制中：⌥空格 暂停/继续 · ⌥↑⌥↓ 调速 · 面板可拖动，不会进成片", systemImage: "text.bubble")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if !session.scriptHasText {
                Label("稿子为空 → 提词器不会出现", systemImage: "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
    }
}

extension ProtoSession {
    var scriptHasText: Bool {
        !scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - 录制画面 mock（假桌面 + 控制条 + 提词器面板）

private enum ProtoPrompterStyle {
    case bottomCenterPanel
    case rightColumn
    case wideStrip
}

private struct ProtoRecordingStage: View {
    @EnvironmentObject private var session: ProtoSession
    let style: ProtoPrompterStyle

    var body: some View {
        ZStack {
            ProtoFakeDesktop(highlight: session.highlightBorderOn, paused: session.recordingPaused)

            VStack {
                ProtoControlBar()
                Spacer()
            }

            ProtoPrompterPanel(style: style)

            // 状态条（原型调试用：把关键状态摊在脸上）
            VStack {
                HStack {
                    Spacer()
                    Text(
                        "速度 ×\(String(format: "%.2f", session.prompterSpeed)) · \(Int(session.prompterFontSize))pt · 进度 \(Int(session.prompterProgress * 100))% · "
                            + (session.prompterPaused ? "提词已暂停" : "提词滚动中")
                            + (session.recordingPaused ? " · 录制已暂停" : "")
                    )
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.black.opacity(0.55))
                    .padding(6)
                    .background(Capsule().fill(.white.opacity(0.6)))
                    .padding(12)
                }
                Spacer()
            }
        }
    }
}

private struct ProtoFakeDesktop: View {
    var highlight = true
    var paused = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hue: 0.58, saturation: 0.32, brightness: 0.32),
                         Color(hue: 0.66, saturation: 0.38, brightness: 0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            // 假的桌面窗口
            VStack(spacing: 22) {
                HStack(spacing: 22) {
                    fakeWindow(title: "Xcode — ScreenFree", width: 360, height: 200)
                    fakeWindow(title: "Safari — ScreenFree Docs", width: 300, height: 200)
                }
                HStack(spacing: 22) {
                    fakeWindow(title: "Terminal", width: 260, height: 140)
                    fakeWindow(title: "Finder", width: 200, height: 140)
                }
            }
            if highlight {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        paused ? Color.orange : Color.red,
                        style: StrokeStyle(lineWidth: 3, dash: [10, 6])
                    )
                    .shadow(color: (paused ? Color.orange : Color.red).opacity(0.6), radius: 5)
                    .padding(8)
            }
        }
    }

    private func fakeWindow(title: String, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle().fill(.white.opacity(0.12))
                HStack {
                    Circle().fill(.red).frame(width: 9, height: 9)
                    Circle().fill(.yellow).frame(width: 9, height: 9)
                    Circle().fill(.green).frame(width: 9, height: 9)
                    Spacer()
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 24)
            ZStack {
                Rectangle().fill(.white.opacity(0.06))
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.3), radius: 8)
    }
}

private struct ProtoControlBar: View {
    @EnvironmentObject private var session: ProtoSession

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(session.recordingPaused ? Color.orange : Color.red)
                .frame(width: 9, height: 9)

            Text(session.elapsedLabel)
                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())

            // 假麦克风电平
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(.green.opacity(0.8))
                        .frame(width: 3, height: CGFloat([8, 14, 10, 16][index]))
                }
            }

            Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 16)

            Button {
                session.recordingPaused.toggle()
            } label: {
                Label(
                    session.recordingPaused ? "继续" : "暂停",
                    systemImage: session.recordingPaused ? "play.fill" : "pause.fill"
                )
            }

            Button {
                session.screen = .home
            } label: {
                Label("完成", systemImage: "checkmark.circle.fill")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.35), radius: 8)
        .padding(.top, 18)
    }
}

// MARK: - 提词器面板（自动滚动 + 可拖动 + 手动暂停）

private struct ProtoPrompterPanel: View {
    @EnvironmentObject private var session: ProtoSession
    let style: ProtoPrompterStyle

    @State private var dragOffset: CGSize = .zero
    @State private var dragBase: CGSize?

    private var panelSize: CGSize {
        switch style {
        case .bottomCenterPanel: return CGSize(width: 580, height: 190)
        case .rightColumn: return CGSize(width: 300, height: 420)
        case .wideStrip: return CGSize(width: 880, height: 110)
        }
    }

    private var styleName: String {
        switch style {
        case .bottomCenterPanel: return "底部居中"
        case .rightColumn: return "右侧竖栏"
        case .wideStrip: return "底部宽条"
        }
    }

    var body: some View {
        panelBody
            .frame(width: panelSize.width, height: panelSize.height)
            .offset(dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let base = dragBase ?? dragOffset
                        dragBase = base
                        dragOffset = CGSize(
                            width: base.width + value.translation.width,
                            height: base.height + value.translation.height
                        )
                    }
                    .onEnded { _ in dragBase = nil }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(.bottom, style == .rightColumn ? 0 : 24)
            .padding(.trailing, style == .rightColumn ? 24 : 0)
    }

    private var alignment: Alignment {
        switch style {
        case .bottomCenterPanel, .wideStrip: return .bottom
        case .rightColumn: return .trailing
        }
    }

    private var currentIndex: Int {
        let count = max(session.paragraphs.count, 1)
        return min(Int(session.prompterProgress * Double(count)), count - 1)
    }

    private var panelBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("提词器", systemImage: "text.bubble")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text(styleName)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                Text(String(format: "×%.2f", session.prompterSpeed))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                Button {
                    session.prompterPaused.toggle()
                } label: {
                    Image(systemName: session.prompterPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                Text("⌥空格 · ⌥↑↓ · 可拖动")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.32))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(session.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                            Text(paragraph)
                                .font(.system(size: session.prompterFontSize, weight: .medium))
                                .foregroundStyle(
                                    index == currentIndex ? .white : .white.opacity(0.42)
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
                .onChange(of: session.prompterProgress) { _, _ in
                    withAnimation(.linear(duration: 0.12)) {
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
        .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 12)
    }
}
