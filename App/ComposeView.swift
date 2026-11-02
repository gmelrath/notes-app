import SwiftUI

/// The screen the app opens on: write a note, optionally with a link, and send it to Notion or email.
struct ComposeView: View {
    @StateObject private var model = ComposeModel()
    @FocusState private var focusedField: Field?
    @Environment(\.scenePhase) private var scenePhase

    private enum Field { case link, title, note }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = model.errorMessage {
                    Banner(text: error, systemImage: "exclamationmark.triangle.fill", tint: .red)
                } else if let confirmation = model.confirmation {
                    Banner(text: confirmation, systemImage: "checkmark.circle.fill", tint: .green)
                } else if let previous = model.previous {
                    Banner(text: previous.duplicateMessage, systemImage: "clock.arrow.circlepath", tint: .orange)
                }

                noteCard
                linkCard
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { actions }
        .onAppear {
            focusedField = .note
            model.refreshPasteboard()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { model.refreshPasteboard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            model.refreshPasteboard()
        }
        .onChange(of: model.confirmation) {
            guard model.confirmation != nil else { return }
            focusedField = .note
            Task {
                try? await Task.sleep(for: .seconds(3))
                model.dismissConfirmation()
            }
        }
    }

    private var linkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField("Link (optional)", text: $model.linkText)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focusedField, equals: .link)
    
                if model.linkText.isEmpty {
                    if model.canPaste {
                        PasteButton(supportedContentTypes: [.url, .plainText]) { providers in
                            Task { @MainActor in await model.paste(providers) }
                        }
                        .labelStyle(.titleOnly)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                    }
                } else {
                    Button("Clear link", systemImage: "xmark.circle.fill", action: model.clearLink)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
            }

            if model.url != nil {
                Divider()
                TextField(model.isFetchingTitle ? "Fetching title…" : "Title", text: $model.title, axis: .vertical)
                    .font(.headline)
                    .lineLimit(1...4)
                    .focused($focusedField, equals: .title)

                if let summary = model.summary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            // A text editor rather than a text field, so Return always starts a new line.
            TextEditor(text: $model.note)
                .focused($focusedField, equals: .note)
                .scrollContentBackground(.hidden)
                // Sized so the note, link and send buttons all fit above the keyboard.
                .frame(minHeight: model.url == nil ? 140 : 96)
                .overlay(alignment: .topLeading) {
                    if model.note.isEmpty {
                        Text(model.url == nil ? "Write a note" : "Add a note")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(10)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))

            Text(model.url == nil
                 ? "The first line becomes the title."
                 : "In Notion, your note replaces the page's description.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                sendButton(.notion, enabled: model.canSend)
                sendButton(.email, enabled: model.canSendByEmail)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !model.hasEmailAddress {
                Text("To send by email, add your address in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.bar)
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
        .disabled(!enabled && model.sent != destination)
        .tint(model.sent == destination ? .green : nil)
    }
}
