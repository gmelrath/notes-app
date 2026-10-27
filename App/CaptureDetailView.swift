import SwiftUI

struct CaptureDetailView: View {
    @State var capture: Capture
    @ObservedObject var model: HistoryModel
    @State private var isRetrying = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
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
                    if capture.fileNames.isEmpty {
                        Button {
                            Task {
                                isRetrying = true
                                capture = await model.retry(capture)
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
                        Text("Files aren't kept after a failed send. Share them again to retry.")
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
                Text("This only removes it from this phone. Anything already in Notion or your inbox stays there.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete from history?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.delete([capture.id])
                dismiss()
            }
        }
    }
}
