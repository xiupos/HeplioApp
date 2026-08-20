import SwiftUI

/// `Label`'s default `.titleAndIcon` style reserves a body-text-sized icon
/// slot, which looks oversized at small text styles like `.caption`.
struct TightLabelStyle: LabelStyle {
    var spacing: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

extension LabelStyle where Self == TightLabelStyle {
    static var tight: TightLabelStyle { TightLabelStyle() }
}
