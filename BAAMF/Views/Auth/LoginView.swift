import SwiftUI
import Combine

struct LoginView: View {

    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var isCreatingAccount = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showResetSheet = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, email, password }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 32) {

                    // Logo / title
                    VStack(spacing: 8) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.tint)
                        Text("BAAMF")
                            .font(.largeTitle.bold())
                        Text("Book club, organized.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    // Form
                    VStack(spacing: 0) {
                        if isCreatingAccount {
                            TextField("Full Name", text: $name)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .email }
                                .padding()
                                .background(Color(.secondarySystemGroupedBackground))

                            Divider().padding(.leading)
                        }

                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))

                        Divider().padding(.leading)

                        SecureField("Password", text: $password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { Task { await primaryAction() } }
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                    .padding(.horizontal)
                    .animation(.easeInOut(duration: 0.2), value: isCreatingAccount)

                    // Error
                    if let error = authViewModel.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Primary action button
                    Button {
                        Task { await primaryAction() }
                    } label: {
                        HStack {
                            if authViewModel.isLoading {
                                ProgressView().tint(.white)
                            }
                            Text(isCreatingAccount ? "Create Account" : "Sign In")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isPrimaryButtonDisabled)
                    .padding(.horizontal)

                    // Secondary actions
                    HStack(spacing: 4) {
                        if isCreatingAccount {
                            Text("Already have an account?")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Sign In") { switchMode(to: false) }
                                .font(.footnote.bold())
                        } else {
                            Button("Forgot password?") { showResetSheet = true }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !isCreatingAccount {
                        Button("Create an account") { switchMode(to: true) }
                            .font(.footnote.bold())
                    }

                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showResetSheet) {
            PasswordResetSheet()
                .environmentObject(authViewModel)
        }
    }

    // MARK: - Helpers

    private var isPrimaryButtonDisabled: Bool {
        guard !authViewModel.isLoading else { return true }
        if isCreatingAccount {
            return name.trimmingCharacters(in: .whitespaces).isEmpty
                || email.isEmpty || password.isEmpty
        }
        return email.isEmpty || password.isEmpty
    }

    private func primaryAction() async {
        focusedField = nil
        if isCreatingAccount {
            await authViewModel.signUp(
                name: name.trimmingCharacters(in: .whitespaces),
                email: email,
                password: password
            )
        } else {
            await authViewModel.signIn(email: email, password: password)
        }
    }

    private func switchMode(to creating: Bool) {
        authViewModel.errorMessage = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            isCreatingAccount = creating
        }
        name = ""
        email = ""
        password = ""
        focusedField = creating ? .name : .email
    }
}

// MARK: - Password Reset Sheet

private struct PasswordResetSheet: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var resetEmail = ""
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email address", text: $resetEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("We'll send a password reset link to this address.")
                }
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task {
                            await authViewModel.sendPasswordReset(email: resetEmail)
                            sent = true
                        }
                    }
                    .disabled(resetEmail.isEmpty)
                }
            }
            .alert("Email Sent", isPresented: $sent) {
                Button("OK") { dismiss() }
            } message: {
                Text("Check your email for a password reset link.")
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
