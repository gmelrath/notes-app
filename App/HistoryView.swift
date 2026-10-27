import SwiftUI

struct HistoryView: View {
    @StateObject private var model = HistoryModel()
    @State private var searchText = ""
    @Environment(\.scenePhase) private var scenePhase

    private var filtered: [Capture] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.captures }
        return model.captures.filter { capture in
            [capture.title, capture.url?.absoluteString, capture.note, capture.summary]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.captures.isEmpty {
                    EmptyHistoryView()
                } else {
                    list
                }
            }
            .navigationTitle("Capture")
            .navigationDestination(for: Capture.self) { capture in
                CaptureDetailView(capture: capture, model: model)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
            if scenePhase == .active { model.reload() }
        }
    }

    private var list: some View {
        List {
            ForEach(filtered) { capture in
                NavigationLink(value: capture) {
                    CaptureRow(capture: capture)
                }
            }
            .onDelete { offsets in
                model.delete(Set(offsets.map { filtered[$0].id }))
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search captures")
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .refreshable { model.reload() }
    }
}

struct CaptureRow: View {
    let capture: Capture

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(capture.title)
                .font(.body.weight(.medium))
                .lineLimit(2)

            HStack(spacing: 6) {
                StatusBadge(capture: capture)
                if let host = capture.host {
                    Text(host).lineLimit(1)
                }
                Text("·")
                Text(capture.friendlyDate)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// A small pill: the destination icon, or a red "Not sent" when delivery failed.
struct StatusBadge: View {
    let capture: Capture

    var body: some View {
        switch capture.status {
        case .sent:
            pill(capture.destination.rawValue, systemImage: capture.destination.systemImage, tint: .secondary)
        case .failed:
            pill("\(capture.destination.rawValue) not sent", systemImage: "exclamationmark.circle.fill", tint: .red)
        }
    }

    private func pill(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text)
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct EmptyHistoryView: View {
    var body: some View {
        List {
            Section {
                step(1, "Tap **Share** in Safari, X, LinkedIn or any app.")
                step(2, "Scroll the row of apps and tap **More**.")
                step(3, "Turn on **Capture** and drag it near the top.")
            } header: {
                Text("Add Capture to your share sheet")
            } footer: {
                Text("Everything you capture will be listed here.")
            }
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.tint))
            Text(text)
        }
    }
}
