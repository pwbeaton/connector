import Foundation
import WidgetKit

/// Saves the widget's numbers where the widget can read them, then asks iOS to redraw it.
nonisolated struct WidgetBridge: WidgetUpdating {
    func update(_ snapshot: WidgetSnapshot) {
        try? WidgetSnapshotFile.save(snapshot)
        Task { @MainActor in
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
