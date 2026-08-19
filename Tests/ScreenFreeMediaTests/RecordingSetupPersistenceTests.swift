import XCTest
@testable import ScreenFree

final class RecordingSetupPersistenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RecordingSetupPersistenceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - 最近口播稿

    func testRecordInsertsMostRecentFirstAndDeduplicates() {
        let store = RecentScriptsStore(defaults: defaults)

        store.record(title: "第一条", text: "第一条的全文")
        store.record(title: "第二条", text: "第二条的全文")
        var entries = store.record(title: "第一条改题", text: "第一条的全文")

        XCTAssertEqual(entries.map(\.text), ["第一条的全文", "第二条的全文"])
        XCTAssertEqual(entries.first?.title, "第一条改题")
        XCTAssertEqual(entries.count, 2)
    }

    func testRecordCapsAtLimit() {
        let store = RecentScriptsStore(defaults: defaults)

        for index in 0..<(RecentScriptsStore.limit + 3) {
            store.record(title: "稿\(index)", text: "第 \(index) 份口播稿全文")
        }

        let entries = store.load()
        XCTAssertEqual(entries.count, RecentScriptsStore.limit)
        XCTAssertEqual(entries.first?.text, "第 \(RecentScriptsStore.limit + 2) 份口播稿全文")
        XCTAssertEqual(
            entries.last?.text,
            "第 3 份口播稿全文"
        )
    }

    func testRecordIgnoresBlankScript() {
        let store = RecentScriptsStore(defaults: defaults)

        store.record(title: "空白", text: "  \n\t ")
        XCTAssertTrue(store.load().isEmpty)
    }

    func testRecentScriptsSurviveStoreReload() {
        RecentScriptsStore(defaults: defaults)
            .record(title: "持久化", text: "重新读取后仍在")

        XCTAssertEqual(
            RecentScriptsStore(defaults: defaults).load().first?.text,
            "重新读取后仍在"
        )
    }

    // MARK: - 上次使用的录制配置

    func testLastRecordingSetupRoundTrip() {
        let setup = LastRecordingSetup(
            captureMode: .area,
            selectedTargetID: 1_234_567_890,
            selectedAreaNormalized: CGRect(x: 0.12, y: 0.2, width: 0.5, height: 0.4),
            systemAudioMode: .selected,
            selectedAudioApplicationIDs: ["com.apple.Safari", "com.apple.Terminal"],
            recordMicrophone: false,
            selectedMicrophoneID: "B9E2F3-AA",
            selectedCameraID: nil,
            countdownSeconds: 5,
            highlightRecordingArea: false
        )

        LastRecordingSetupStore(defaults: defaults).save(setup)

        XCTAssertEqual(
            LastRecordingSetupStore(defaults: defaults).load(),
            setup
        )
    }

    func testLastRecordingSetupMissingReturnsNil() {
        XCTAssertNil(LastRecordingSetupStore(defaults: defaults).load())
    }

    // MARK: - 旧演讲备注迁移

    func testMigrationImportsLegacyTextAndRemovesLegacyKeys() {
        defaults.set(
            "旧演讲备注第一行\n第二行",
            forKey: SpeakerNotesMigration.legacyTextKey
        )
        defaults.set(true, forKey: SpeakerNotesMigration.legacyEnabledKey)
        let recents = RecentScriptsStore(defaults: defaults)

        let migrated = SpeakerNotesMigration.run(
            defaults: defaults,
            recents: recents
        )

        XCTAssertTrue(migrated)
        XCTAssertEqual(recents.load().first?.text, "旧演讲备注第一行\n第二行")
        XCTAssertEqual(recents.load().first?.title, "旧演讲备注第一行")
        XCTAssertNil(
            defaults.object(forKey: SpeakerNotesMigration.legacyTextKey)
        )
        XCTAssertNil(
            defaults.object(forKey: SpeakerNotesMigration.legacyEnabledKey)
        )
    }

    func testMigrationWithBlankLegacyTextOnlyRemovesKeys() {
        defaults.set("   \n ", forKey: SpeakerNotesMigration.legacyTextKey)
        let recents = RecentScriptsStore(defaults: defaults)

        let migrated = SpeakerNotesMigration.run(
            defaults: defaults,
            recents: recents
        )

        XCTAssertTrue(migrated)
        XCTAssertTrue(recents.load().isEmpty)
    }

    func testMigrationSkipsWhenLegacyKeyAbsent() {
        let migrated = SpeakerNotesMigration.run(
            defaults: defaults,
            recents: RecentScriptsStore(defaults: defaults)
        )

        XCTAssertFalse(migrated)
    }
}
