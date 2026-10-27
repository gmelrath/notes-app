import SwiftUI
import UIKit

/// Entry point the share sheet opens. Hosts the SwiftUI card.
final class ShareViewController: UIViewController {
    private lazy var model = ShareCardModel { [weak self] in
        self?.extensionContext?.completeRequest(returningItems: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let host = UIHostingController(rootView: ShareCardView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        Task { await model.load(from: items) }
    }
}
