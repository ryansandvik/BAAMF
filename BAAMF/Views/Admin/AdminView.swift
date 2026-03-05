import SwiftUI
import Combine

/// Profile tab — visible to all members.
/// Shows user info and sign-out for everyone; admin controls shown only to admins.
struct ProfileView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        List {

            // MARK: User info
            Section {
                Label(
                    authViewModel.currentMember?.name ?? "Member",
                    systemImage: "person.circle.fill"
                )
                .foregroundStyle(.primary)
            }

            // MARK: Admin controls (admins only)
            if authViewModel.isAdmin {
                Section("Admin Controls") {
                    Label("Coming in Phase 6", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }

            // MARK: Sign out
            Section {
                Button(role: .destructive) {
                    authViewModel.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Profile")
    }
}

#Preview {
    NavigationStack { ProfileView() }
        .environmentObject(AuthViewModel())
}
