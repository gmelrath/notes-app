import SwiftUI

/// The layout every screen shares: a large title on the left, its action icons on the right,
/// and the content below, all on the light gray background. On iPad the header sits in the
/// same centred column as the content, rather than spanning the whole window.
struct Page<Actions: View, Content: View>: View {
    let title: String
    var showsBack = false
    @ViewBuilder var actions: Actions
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss
    @AppStorage(TitleFont.storageKey) private var titleFont = TitleFont.sansSerif

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if showsBack {
                    Button("Back", systemImage: "chevron.left") { dismiss() }
                        .labelStyle(.iconOnly)
                        .font(.title2.weight(.semibold))
                }
                Text(title)
                    .font(titleFont.font())
                    .foregroundStyle(Color("TitleColor"))
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 22) { actions }
                    .font(.title2)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            content
        }
        .readableWidth()
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension Page where Actions == EmptyView {
    init(_ title: String, showsBack: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(title: title, showsBack: showsBack, actions: { EmptyView() }, content: content)
    }
}

/// The page-title font, chosen in Settings. IBM Plex Serif's file and licence are in App/Fonts.
enum TitleFont: String, CaseIterable, Identifiable {
    case sansSerif, serif

    static let storageKey = "titleFont"
    var id: Self { self }

    var name: String {
        switch self {
        case .sansSerif: "Sans-serif"
        case .serif: "Serif"
        }
    }

    /// Sized like a large title by default, so it still follows the iPhone's text-size setting.
    func font(size: CGFloat = 34, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        switch self {
        case .sansSerif: .system(style).bold()
        case .serif: .custom("IBMPlexSerif-Medium", size: size, relativeTo: style)
        }
    }
}

extension View {
    /// Lists and forms on a page: white rows on the page's gray, lined up with the header.
    func pageList() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 16, for: .scrollContent)
    }
}

// Hiding the navigation bar also turns off swiping from the left edge to go back; this turns it on again.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
