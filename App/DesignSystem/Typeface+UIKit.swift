import SwiftUI
import UIKit

extension Typeface {
    /// Navigation titles and segmented pickers are UIKit controls that don't read SwiftUI's
    /// font, so they get Archivo through their appearance proxies.
    static func applyToSystemControls() {
        func font(_ size: CGFloat, _ weight: Double, width: Double = 100) -> UIFont {
            archivo(size: size, weight: weight, width: width) as UIFont
        }
        let navigation = UINavigationBar.appearance()
        navigation.titleTextAttributes = [.font: font(17, 700)]
        navigation.largeTitleTextAttributes = [.font: font(34, 700, width: 85)]
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: font(17, 600)], for: .normal)
        let segmented = UISegmentedControl.appearance()
        segmented.setTitleTextAttributes([.font: font(14, 500)], for: .normal)
        segmented.setTitleTextAttributes([.font: font(14, 700)], for: .selected)
    }
}
