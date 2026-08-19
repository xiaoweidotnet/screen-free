import CoreGraphics
import Foundation

// 术语见 CONTEXT.md：Script（口播稿）、Teleprompter（提词器）、
// Recording Setup（录制设置）。两类存储都只作为录制设置页的默认值来源，
// 真正跟项目走的那份口播稿存在 `.screenfree` 快照的 `script` 字段里。

// MARK: - 最近口播稿

struct RecentScriptEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var text: String
    var updatedAt: Date
}

/// 最近口播稿：全文副本（上限 10 条），仅作为设置页一键选入的来源。
struct RecentScriptsStore {
    static let limit = 10
    static let defaultsKey = "recentScripts"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [RecentScriptEntry] {
        guard
            let data = defaults.data(forKey: Self.defaultsKey)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard
            let entries = try? decoder.decode(
                [RecentScriptEntry].self,
                from: data
            )
        else { return [] }
        return Array(entries.prefix(Self.limit))
    }

    func save(_ entries: [RecentScriptEntry]) {
        let capped = Array(entries.prefix(Self.limit))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(capped) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// 按全文去重 upsert：命中旧条目时移除并提到最前，标题与时间更新。
    @discardableResult
    func record(title: String, text: String) -> [RecentScriptEntry] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return load() }
        var entries = load().filter { $0.text != text }
        entries.insert(
            RecentScriptEntry(
                id: UUID(),
                title: title,
                text: text,
                updatedAt: Date()
            ),
            at: 0
        )
        save(entries)
        return load()
    }

    /// 最近列表的条目标题：取稿件第一个非空行（截断到 60 字）。
    static func title(for text: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                return String(trimmed.prefix(60))
            }
        }
        return ""
    }
}

// MARK: - 上次使用的录制配置

/// 开录瞬间落盘的配置快照；录制设置页打开时按它还原默认值。
/// 语义是"上一次真正使用的配置"，未开录的临时改动不写入。
struct LastRecordingSetup: Codable, Equatable {
    var captureMode: CaptureMode
    var selectedTargetID: UInt32?
    var selectedAreaNormalized: CGRect
    var systemAudioMode: SystemAudioCaptureMode
    var selectedAudioApplicationIDs: Set<String>
    var recordMicrophone: Bool
    var selectedMicrophoneID: String?
    var selectedCameraID: String?
    var countdownSeconds: Int
    var highlightRecordingArea: Bool

    static let defaultsKey = "lastRecordingSetup"
}

struct LastRecordingSetupStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> LastRecordingSetup? {
        guard
            let data = defaults.data(forKey: LastRecordingSetup.defaultsKey)
        else { return nil }
        return try? JSONDecoder().decode(LastRecordingSetup.self, from: data)
    }

    func save(_ setup: LastRecordingSetup) {
        guard let data = try? JSONEncoder().encode(setup) else { return }
        defaults.set(data, forKey: LastRecordingSetup.defaultsKey)
    }
}

// MARK: - 旧演讲备注迁移

/// 首次启动新版：把旧版全局演讲备注（UserDefaults）导入最近口播稿，
/// 然后删除旧 key——key 消失本身就是"已迁移"标记。
enum SpeakerNotesMigration {
    static let legacyTextKey = "speakerNotesText"
    static let legacyEnabledKey = "showSpeakerNotes"

    /// 返回 true 表示本次执行了迁移（无论旧文本是否为空）。
    @discardableResult
    static func run(
        defaults: UserDefaults = .standard,
        recents: RecentScriptsStore = RecentScriptsStore()
    ) -> Bool {
        guard defaults.object(forKey: legacyTextKey) != nil else {
            return false
        }
        let legacyText = defaults.string(forKey: legacyTextKey) ?? ""
        if !legacyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recents.record(
                title: RecentScriptsStore.title(for: legacyText),
                text: legacyText
            )
        }
        defaults.removeObject(forKey: legacyTextKey)
        defaults.removeObject(forKey: legacyEnabledKey)
        return true
    }
}
