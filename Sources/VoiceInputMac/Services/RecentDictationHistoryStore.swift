import Foundation

struct RecentDictationHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    enum OptimizationStatus: String, Codable, Equatable, Sendable {
        case localOnly
        case optimized
        case fallbackToLocal

        var title: String {
            switch self {
            case .localOnly:
                return "本地结果"
            case .optimized:
                return "在线纠错"
            case .fallbackToLocal:
                return "在线回退"
            }
        }
    }

    let id: UUID
    let createdAt: Date
    let text: String
    let inputDeviceName: String?
    let optimizationStatus: OptimizationStatus
}

protocol RecentDictationHistoryStoring: AnyObject, Sendable {
    func load() -> [RecentDictationHistoryEntry]
    @discardableResult func record(_ entry: RecentDictationHistoryEntry) -> [RecentDictationHistoryEntry]
    @discardableResult func clear() -> [RecentDictationHistoryEntry]
}

final class RecentDictationHistoryStore: RecentDictationHistoryStoring, @unchecked Sendable {
    private let defaultsKey = "voice_input_mac_recent_history_v1"
    private let maxRecords: Int
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard, maxRecords: Int = 10) {
        self.userDefaults = userDefaults
        self.maxRecords = maxRecords
    }

    func load() -> [RecentDictationHistoryEntry] {
        guard let data = userDefaults.data(forKey: defaultsKey),
              let decoded = try? decoder.decode([RecentDictationHistoryEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    @discardableResult
    func record(_ entry: RecentDictationHistoryEntry) -> [RecentDictationHistoryEntry] {
        var records = load()
        records.insert(entry, at: 0)
        if records.count > maxRecords {
            records.removeLast(records.count - maxRecords)
        }
        save(records)
        return records
    }

    @discardableResult
    func clear() -> [RecentDictationHistoryEntry] {
        userDefaults.removeObject(forKey: defaultsKey)
        return []
    }

    private func save(_ records: [RecentDictationHistoryEntry]) {
        guard let data = try? encoder.encode(records) else { return }
        userDefaults.set(data, forKey: defaultsKey)
    }
}
