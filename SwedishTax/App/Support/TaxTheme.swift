import SwiftUI
import UIKit

extension Color {
    static let taxBackground = Color(light: (244, 247, 246), dark: (15, 21, 20))
    static let taxSurface = Color(light: (255, 255, 255), dark: (27, 35, 33))
    static let taxField = Color(light: (247, 249, 248), dark: (20, 27, 25))
    static let taxBorder = Color(light: (210, 218, 215), dark: (57, 69, 65))
    static let taxPrimary = Color(light: (30, 44, 41), dark: (235, 242, 240))
    static let taxBlue = Color(light: (0, 82, 147), dark: (74, 161, 225))
    static let taxGreen = Color(light: (24, 121, 78), dark: (68, 190, 127))
    static let taxAmber = Color(light: (128, 91, 0), dark: (238, 190, 76))

    init(light: (Int, Int, Int), dark: (Int, Int, Int)) {
        self.init(uiColor: UIColor { traits in
            let components = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat(components.0) / 255,
                green: CGFloat(components.1) / 255,
                blue: CGFloat(components.2) / 255,
                alpha: 1
            )
        })
    }
}
