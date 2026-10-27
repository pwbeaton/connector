import Foundation

/// Today's numbers for the widget. The app writes it after every sync; the
/// widget only reads it. Plain values only, so the widget needs none of the app's code.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// The civil date these numbers are for, as "YYYY-MM-DD".
    var date: String
    var recovery: Int?
    /// "go", "steady", or "recover" (matches RecoveryBand).
    var recoveryBand: String?
    /// Nights collected toward the HRV baseline while Recovery is calibrating.
    var calibratingNights: Int?
    var sleep: Int?
    var effort: Int?
    var effortTargetLow: Int
    var effortTargetHigh: Int
    var steps: Int?
    /// The longest of the current streaks, in days.
    var streakDays: Int
    var updatedAt: Date

    static let fileName = "widget-snapshot.json"

    /// Numbers that look like a real morning, for the widget gallery and previews.
    static let sample = WidgetSnapshot(date: "2026-10-27", recovery: 78, recoveryBand: "go", calibratingNights: nil,
                                       sleep: 84, effort: 41, effortTargetLow: 60, effortTargetHigh: 80, steps: 6_240,
                                       streakDays: 12, updatedAt: Date(timeIntervalSince1970: 1_793_000_000))
}

/// Reads and writes the snapshot file in the shared container.
nonisolated enum WidgetSnapshotFile {
    static func url(appGroup: String? = AppGroup.identifier) -> URL {
        SharedFiles.directory(appGroup: appGroup).appendingPathComponent(WidgetSnapshot.fileName)
    }

    static func load(from url: URL = url()) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot, to url: URL = url()) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}
