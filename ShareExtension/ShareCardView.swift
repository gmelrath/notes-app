import SwiftUI

struct ShareCardView: View {
    @ObservedObject var model: ShareCardModel
    @FocusState private var focusedField: Field?

    private enum Field { case title, note }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.item.isEmpty {
                    ContentUnavailableView(
                        "Nothing to capture",
                        systemImage: "tray",
                        description: Text("Campfire couldn’t read what was shared.")
                    )
                } else {
                    content
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Campfire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: model.cancel)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !model.isLoading && !model.item.isEmpty { actions }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = model.errorMessage {
                    Banner(text: error, systemImage: "exclamationmark.triangle.fill", tint: .red)
                } else if let previous = model.previous {
                    Banner(text: previous.duplicateMessage, systemImage: "clock.arrow.circlepath", tint: .orange)
                }

                preview
                note
            }
            .padding()
            .readableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let host = model.item.url?.host() {
                Label(host.replacingOccurrences(of: "www.", with: ""), systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField(model.isFetchingTitle ? "Fetching title…" : "Title", text: $model.title, axis: .vertical)
                .font(.headline)
                .focused($focusedField, equals: .title)
                .lineLimit(1...4)

            if let summary = model.summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let text = model.item.text, !text.isEmpty {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
            }

            ForEach(model.item.files) { file in
                HStack {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                    Text(file.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(file.formattedSize)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Add a note", text: $model.note, axis: .vertical)
                .focused($focusedField, equals: .note)
                .lineLimit(3...8)
                .padding()
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
            Text("Notes are included when you send by email.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                sendButton(.notion, enabled: model.canSendToNotion)
                sendButton(.email, enabled: model.canSendByEmail)
            }

            if !model.hasEmailAddress {
                Text("To send by email, add your address in the Campfire app’s Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .readableWidth()
        .background(Color(.systemGroupedBackground))
    }

    private func sendButton(_ destination: Destination, enabled: Bool) -> some View {
        Button {
            focusedField = nil
            Task { await model.send(to: destination) }
        } label: {
            Group {
                if model.sending == destination {
                    ProgressView().tint(.white)
                } else if model.sent == destination {
                    Label("Sent", systemImage: "checkmark")
                } else {
                    Label(destination.rawValue, systemImage: destination.systemImage)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SendButtonStyle(tint: model.sent == destination ? .green : .campfireOrange))
        .disabled(!enabled && model.sent != destination)
        .keyboardShortcut(.return, modifiers: destination == .notion ? .command : [.command, .shift])
    }
}
