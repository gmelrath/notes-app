import SwiftUI

/// One entry from Sent. It's looked up by ID in the shared history each time, so it always shows the
/// current version (after Try again, or a sync from the other device), and closes if it's deleted.
struct CaptureDetailView: View {
    let id: Capture.ID
    @EnvironmentObject private var model: HistoryModel
    @State private var isRetrying = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var capture: Capture? { model.captures.first { $0.id == id } }

    var body: some View {
        Page("Details", showsBack: true) {
            if let capture { details(capture) }
        }
        .confirmationDialog("Delete from history?", isPresented: $confirmDelete, titleVisibility: .visible) {
            // Closing happens below, once the entry is gone.
            Button("Delete", role: .destructive) { model.delete([id]) }
        }
        .onChange(of: capture == nil) { _, isGone in
            if isGone { dismiss() }
        }
    }

    private func details(_ capture: Capture) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(capture.title)
                        .font(.title3.weight(.semibold))
                    if let summary = capture.summary {
                        Text(summary)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                if let url = capture.url {
                    Button {
                        openURL(url)
                    } label: {
                        Label(capture.host ?? url.absoluteString, systemImage: "safari")
                    }
                }
            }

            Section("Status") {
                HStack {
                    StatusBadge(capture: capture)
                    Spacer()
                    Text(capture.date.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)

                if capture.status == .failed {
                    if let error = capture.errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if model.canRetry(capture) {
                        Button {
                            Task {
                                isRetrying = true
                                _ = await model.retry(capture)
                                isRetrying = false
                            }
                        } label: {
                            HStack {
                                Label("Try again", systemImage: "arrow.clockwise")
                                if isRetrying {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isRetrying)
                    } else {
                        Text(capture.missingFilesMessage(on: UIDevice.current.model))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let note = capture.note {
                Section("Note") {
                    Text(note)
                }
            }

            if let text = capture.text {
                Section("Shared text") {
                    Text(text)
                        .foregroundStyle(.secondary)
                }
            }

            if !capture.fileNames.isEmpty {
                Section("Files") {
                    ForEach(capture.fileNames, id: \.self) { name in
                        Label(name, systemImage: "doc")
                    }
                }
            }

            Section {
                Button("Delete from history", role: .destructive) {
                    confirmDelete = true
                }
            } footer: {
                Text("This removes it from Campfire on all your devices. Anything already in Notion or your inbox stays there.")
            }
        }
        .pageList()
    }
}
