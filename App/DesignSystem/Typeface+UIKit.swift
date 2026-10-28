import SwiftUI
import UIKit

extension Typeface {
    /// Navigation titles, tab labels, and segmented pickers are UIKit controls that don't read
    /// SwiftUI's font, so they get Satoshi through their appearance proxies.
    static func applyToSystemControls() {
        func font(_ weight: Font.Weight, _ style: UIFont.TextStyle, size: CGFloat) -> UIFont {
            guard let base = UIFont(name: name(weight), size: size) else { return .preferredFont(forTextStyle: style) }
            return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
        }
        let navigation = UINavigationBar.appearance()
        navigation.titleTextAttributes = [.font: font(.bold, .headline, size: 17)]
        navigation.largeTitleTextAttributes = [.font: font(.bold, .largeTitle, size: 34)]
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: font(.medium, .body, size: 17)], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: font(.medium, .caption2, size: 10)], for: .normal)
        let segmented = UISegmentedControl.appearance()
        segmented.setTitleTextAttributes([.font: font(.medium, .footnote, size: 13)], for: .normal)
        segmented.setTitleTextAttributes([.font: font(.bold, .footnote, size: 13)], for: .selected)
    }
}
