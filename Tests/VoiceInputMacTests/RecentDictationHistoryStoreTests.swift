import XCTest
@testable import VoiceInputMac

final class RecentDictationHistoryStoreTests: XCTestCase {
    func testRecordPersistsEntriesAcrossReload() {
        let suite = "RecentDictationHistoryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = RecentDictationHistoryStore(userDefaults: defaults, maxRecords: 3)
        let entry = RecentDictationHistoryEntry(
            id: UUID(),
            createdAt: Date(),
            text: "第一条结果",
            inputDeviceName: "USB 麦克风",
            optimizationStatus: .optimized
        )

        _ = store.record(entry)

        let reloadedStore = RecentDictationHistoryStore(userDefaults: defaults, maxRecords: 3)
        XCTAssertEqual(reloadedStore.load().count, 1)
        XCTAssertEqual(reloadedStore.load().first?.text, "第一条结果")
        XCTAssertEqual(reloadedStore.load().first?.inputDeviceName, "USB 麦克风")
    }

    func testRecordCapsHistoryAtConfiguredMaximum() {
        let suite = "RecentDictationHistoryStoreTests.max.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = RecentDictationHistoryStore(userDefaults: defaults, maxRecords: 2)
        _ = store.record(.init(id: UUID(), createdAt: Date(), text: "1", inputDeviceName: nil, optimizationStatus: .localOnly))
        _ = store.record(.init(id: UUID(), createdAt: Date(), text: "2", inputDeviceName: nil, optimizationStatus: .optimized))
        let records = store.record(.init(id: UUID(), createdAt: Date(), text: "3", inputDeviceName: nil, optimizationStatus: .fallbackToLocal))

        XCTAssertEqual(records.map(\.text), ["3", "2"])
    }
}
