import SwiftUI

/// A tinted message strip shown at the top of the share card and the compose screen.
struct Banner: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension View {
    /// Keeps content at a comfortable width on iPad, centred, instead of stretching edge to edge.
    func readableWidth() -> some View {
        frame(maxWidth: 640).frame(maxWidth: .infinity)
    }
}
