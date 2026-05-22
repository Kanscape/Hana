import SwiftUI

struct LoginRequiredView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    @State private var isCredentialLoginPresented = false

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            VStack(spacing: 10) {
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                }

                Button {
                    isCredentialLoginPresented = true
                } label: {
                    Label("账号密码登录", systemImage: "key")
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $isCredentialLoginPresented) {
            SiteCredentialLoginSheet()
        }
    }
}

struct SiteCredentialLoginSheet: View {
    @Environment(HanaServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var alertMessage: HanaAlertMessage?

    var body: some View {
        NavigationStack {
            Form {
                Section("站点账号") {
                    TextField("邮箱", text: $email)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                }
            }
            .navigationTitle("账号密码登录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "取消", systemImage: "xmark") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Image(systemName: "key")
                        }
                    }
                    .accessibilityLabel("登录")
                    .disabled(isSubmitting || !canSubmit)
                }
            }
        }
        .hanaFeedbackAlert($alertMessage)
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        alertMessage = nil
        defer { isSubmitting = false }

        do {
            await services.siteSession.syncDefaultWebCookies()
            let user = try await services.repository.login(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            services.siteSession.syncSharedHTTPCookies()
            await services.applyLoginState(user: user)
            dismiss()
        } catch {
            if services.siteSession.handle(error) {
                dismiss()
            } else {
                alertMessage = .error(error.localizedDescription)
            }
        }
    }
}
