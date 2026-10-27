import Foundation

extension WidgetSnapshot {
    /// Today's widget numbers from the engine's results.
    nonisolated init(engine: EngineSnapshot, todayRecord: DayRecord?, updatedAt: Date) {
        let today = engine.todayScores
        var calibratingNights: Int?
        if case .calibrating(let nights) = today?.recovery ?? .calibrating(nightsCollected: engine.hrvNightsCollected) {
            calibratingNights = nights
        }
        let target = today?.effortTarget ?? RecoveryBand.steady.effortTarget
        self.init(
            date: engine.today.description,
            recovery: today?.recovery.score?.total,
            recoveryBand: today?.recovery.score?.band.rawValue,
            calibratingNights: calibratingNights,
            sleep: today?.sleep?.total,
            effort: today?.effort,
            effortTargetLow: target.lowerBound,
            effortTargetHigh: target.upperBound,
            steps: todayRecord?.steps,
            streakDays: engine.streaks.values.map(\.current).max() ?? 0,
            updatedAt: updatedAt
        )
    }
}
