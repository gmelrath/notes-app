import SwiftUI

extension Color {
    /// The send buttons' colour, #FF7C00.
    static let campfireOrange = Color(red: 1, green: 124 / 255, blue: 0)
}

/// The Notion and Email buttons: orange when ready, a lighter orange while pressed, and a gray
/// a shade darker than the background while there's nothing to send.
struct SendButtonStyle: ButtonStyle {
    var tint: Color = .campfireOrange
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.white : Color(.secondaryLabel))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(fill(pressed: configuration.isPressed), in: Capsule())
            .animation(.easeOut(duration: 0.2), value: isEnabled)
    }

    private func fill(pressed: Bool) -> Color {
        guard isEnabled else { return Color(.systemGray5) }
        return pressed ? tint.mix(with: .white, by: 0.25) : tint
    }
}
