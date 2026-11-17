import SwiftUI

extension Color {
    /// The app's one orange, #FF7C00: the accent colour in the asset catalogue, used for the send
    /// buttons and, as the accent, for icons, links and controls. Read by name rather than as
    /// `Color.accentColor`, because the share card runs inside another app's window and would get
    /// that app's accent (often the system blue) instead of ours.
    static let campfireOrange = Color("AccentColor")
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
