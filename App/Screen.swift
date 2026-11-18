import SwiftUI

/// Every screen the app can open. All navigation goes through this list: links are written
/// `NavigationLink(value: Screen.…)`, and the screens themselves are created here, registered once
/// at the top of the app. Never use `NavigationLink { SomeView() }`: mixing that older kind of link
/// with these makes SwiftUI push screens twice (NMB-30: Details appeared to be skipped).
enum Screen: Hashable {
    case sent
    case settings
    case details(Capture.ID)

    @MainActor @ViewBuilder
    var view: some View {
        switch self {
        case .sent: HistoryView()
        case .settings: SettingsView()
        case .details(let id): CaptureDetailView(id: id)
        }
    }
}
