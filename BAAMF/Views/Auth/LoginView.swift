import SwiftUI
import Combine

struct LoginView: View {

    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var showResetSheet = false
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

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
                            .onSubmit { Task { await signIn() } }
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                    .padding(.horizontal)

                    // Error
                    if let error = authViewModel.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Sign in button
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            if authViewModel.isLoading {
                                ProgressView().tint(.white)
                            }
                            Text("Sign In")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(authViewModel.isLoading || email.isEmpty || password.isEmpty)
                    .padding(.horizontal)

                    // Forgot password
                    Button("Forgot password?") {
                        showResetSheet = true
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

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

    private func signIn() async {
        focusedField = nil
        await authViewModel.signIn(email: email, password: password)
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
