import SwiftUI

struct SettingsView: View {
    @State private var email = AppSettings.emailAddressDraft
    @FocusState private var emailFocused: Bool

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }
    private var showsEmailError: Bool { !trimmedEmail.isEmpty && !AppSettings.isValidEmail(trimmedEmail) }

    var body: some View {
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
                    Text("Captures you send by email go to this address.")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: email) {
            AppSettings.emailAddress = trimmedEmail.isEmpty ? nil : trimmedEmail
        }
    }
}
