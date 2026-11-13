import SwiftUI

/// The send buttons at the bottom of the compose screen and the share card: one per destination,
/// with any setup hints underneath.
struct SendButtonRow: View {
    /// Whether each destination's button is enabled.
    let canSend: (Destination) -> Bool
    let sending: Destination?
    let sent: Destination?
    /// Where Settings is, for the setup hints.
    var settings = "Settings"
    let send: (Destination) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ForEach(Destination.allCases, id: \.self, content: button)
            }

            ForEach(Destination.allCases.compactMap { $0.setupHint(settings: settings) }, id: \.self) { hint in
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .readableWidth()
        .background(Color(.systemGroupedBackground))
    }

    private func button(_ destination: Destination) -> some View {
        Button {
            send(destination)
        } label: {
            Group {
                if sending == destination {
                    ProgressView().tint(.white)
                } else if sent == destination {
                    Label("Sent", systemImage: "checkmark")
                } else {
                    Label(destination.rawValue, systemImage: destination.systemImage)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SendButtonStyle(tint: sent == destination ? .green : .campfireOrange))
        .disabled(!canSend(destination) && sent != destination)
        .keyboardShortcut(.return, modifiers: destination.shortcutModifiers)
    }
}

extension Destination {
    /// For a hardware keyboard: ⌘↩ sends to Notion, ⇧⌘↩ by email.
    var shortcutModifiers: EventModifiers {
        switch self {
        case .notion: .command
        case .email: [.command, .shift]
        }
    }
}
