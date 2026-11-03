import SwiftUI

@main
struct CampfireApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ComposeView()
                    .navigationTitle("Campfire")
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            NavigationLink {
                                HistoryView()
                            } label: {
                                Image(systemName: "archivebox")
                            }
                            .accessibilityLabel("Sent")

                            NavigationLink {
                                SettingsView()
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityLabel("Settings")
                        }
                    }
            }
            .onChange(of: scenePhase, initial: true) {
                if scenePhase == .active { Task { await syncHistory() } }
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // iCloud's change notifications arrive silently; no permission prompt is needed.
        application.registerForRemoteNotifications()
        return true
    }

    /// Another device changed the history.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { completionHandler(await syncHistory() ? .newData : .noData) }
    }
}

extension Notification.Name {
    /// Posted when changes from another device have been pulled into the history.
    static let historyDidChange = Notification.Name("historyDidChange")
}

/// Syncs with iCloud and tells open screens if the history changed.
@MainActor @discardableResult
func syncHistory() async -> Bool {
    let changed = await CloudHistory.shared.sync()
    if changed { NotificationCenter.default.post(name: .historyDidChange, object: nil) }
    return changed
}

/// Keeps the app's copy of the history in step with the file the share card writes to.
@MainActor
final class HistoryModel: ObservableObject {
    @Published private(set) var captures: [Capture] = []

    func reload() {
        captures = CaptureStore.load()
    }

    func delete(_ ids: Set<Capture.ID>) {
        CaptureStore.delete(ids: ids)
        AttachmentStore.remove(for: ids)
        reload()
        Task { await syncHistory() }
    }

    /// Retry needs the kept copies of any shared files; without them, files would silently go missing.
    func canRetry(_ capture: Capture) -> Bool {
        capture.destination == .notion || capture.fileNames.isEmpty || !AttachmentStore.files(for: capture.id).isEmpty
    }

    func retry(_ capture: Capture) async -> Capture {
        var updated = capture
        updated.date = .now
        do {
            try await Sender.send(capture, to: capture.destination, attachments: AttachmentStore.files(for: capture.id))
            updated.status = .sent
            updated.errorMessage = nil
            AttachmentStore.remove(for: [capture.id])
        } catch {
            updated.status = .failed
            updated.errorMessage = error.localizedDescription
        }
        CaptureStore.save(updated)
        reload()
        Task { await syncHistory() }
        return updated
    }
}
