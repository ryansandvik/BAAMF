import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - DeleteAccountView
//
// Present this as a sheet from ProfileView:
//   .sheet(isPresented: $showDeleteAccount) {
//       DeleteAccountView()
//           .environmentObject(authViewModel)
//   }

struct DeleteAccountView: View {

    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showFinalConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This will permanently delete your account and all associated data. This cannot be undone.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } header: {
                    Text("Warning")
                }

                Section {
                    SecureField("Enter your password to confirm", text: $password)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                } header: {
                    Text("Confirm your identity")
                } footer: {
                    Text("We need to verify your identity before deleting your account.")
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showFinalConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            if isDeleting {
                                ProgressView()
                            } else {
                                Text("Delete My Account")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(password.isEmpty || isDeleting)
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isDeleting)
                }
            }
            .confirmationDialog(
                "Are you absolutely sure?",
                isPresented: $showFinalConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete My Account", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your account and all your data will be permanently deleted.")
            }
        }
    }

    // MARK: - Deletion

    private func deleteAccount() async {
        isDeleting = true
        errorMessage = nil

        guard let user = Auth.auth().currentUser,
              let email = user.email else {
            errorMessage = "Could not identify your account. Please sign out and sign in again."
            isDeleting = false
            return
        }

        // Step 1: Re-authenticate (required by Firebase for sensitive operations)
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        do {
            try await user.reauthenticate(with: credential)
        } catch {
            errorMessage = "Incorrect password. Please try again."
            isDeleting = false
            return
        }

        let uid = user.uid
        let db = Firestore.firestore()

        // Step 2: Delete Firestore member document
        do {
            try await db.collection("users").document(uid).delete()
        } catch {
            // Non-fatal — proceed with auth deletion even if Firestore cleanup fails
            print("Warning: could not delete Firestore member document: \(error)")
        }

        // Step 3: Delete Firebase Auth account
        do {
            try await user.delete()
        } catch {
            errorMessage = "Failed to delete account. Please try again or contact support."
            isDeleting = false
            return
        }

        // Step 4: Sign out locally — RootView will return to LoginView automatically
        authViewModel.signOut()
    }
}
