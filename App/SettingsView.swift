import SwiftUI

struct SettingsView: View {
    @State private var email = AppSettings.emailAddressDraft
    @FocusState private var emailFocused: Bool
    @AppStorage(TitleFont.storageKey) private var titleFont = TitleFont.sansSerif

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }
    private var showsEmailError: Bool { !trimmedEmail.isEmpty && !AppSettings.isValidEmail(trimmedEmail) }

    var body: some View {
        Page("Settings", showsBack: true) {
            form
        }
        .onChange(of: email) {
            // Skip when the change came from the other device, so it isn't sent straight back.
            guard trimmedEmail != AppSettings.emailAddressDraft else { return }
            AppSettings.emailAddress = trimmedEmail.isEmpty ? nil : trimmedEmail
        }
        .onDisappear { Task { await syncHistory() } }
        .onReceive(NotificationCenter.default.publisher(for: .historyDidChange)) { _ in
            // The address may have been changed on the other device.
            if !emailFocused { email = AppSettings.emailAddressDraft }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("you@example.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($emailFocused)
                    .submitLabel(.done)
            } header: {
                Text("Send email to")
            } footer: {
                if showsEmailError {
                    Text("That doesn't look like an email address.")
                        .foregroundStyle(.red)
                } else {
                    Text("Links and notes you send by email go to this address.")
                }
            }

            Section {
                KeyField(title: "Notion key", key: .notionToken)
                KeyField(title: "Resend key", key: .resendAPIKey)
            } header: {
                Text("Keys")
            } footer: {
                Text("Kept in this device’s Keychain and carried to your other devices by iCloud Keychain. Paste a key to replace the saved one.")
            }

            Section {
                Picker("Title font", selection: $titleFont) {
                    ForEach(TitleFont.allCases) { option in
                        Text(option.name).font(option.font(size: 22, relativeTo: .title2)).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Page titles")
            } footer: {
                Text("The font for the Campfire, Sent and Settings titles.")
            }
        }
        .pageList()
    }
}

/// One private key. The saved key is never shown; pasting a new one replaces it.
private struct KeyField: View {
    let title: String
    let key: Secrets.Key
    @State private var draft = ""
    @State private var isSaved = false

    var body: some View {
        HStack {
            SecureField(title, text: $draft, prompt: Text(isSaved ? "\(title): saved" : "Paste \(title.lowercased())"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
            if isSaved && draft.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Saved")
            }
        }
        .onAppear { isSaved = Secrets.value(key) != nil }
        .onChange(of: draft) {
            guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, Secrets.set(draft, for: key) else { return }
            isSaved = true
        }
        .onSubmit { draft = "" }
        .onDisappear { draft = "" }
    }
}
