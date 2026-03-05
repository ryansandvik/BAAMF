import SwiftUI
import Combine

// Typed navigation destination for Profile's NavigationStack.
// Using a value-based NavigationLink ensures the pushed view is tracked
// in the NavigationPath binding in MainTabView, so resetting the path
// on tab-switch correctly pops back to the root Profile screen.
enum ProfileNavDestination: Hashable {
    case schedule
}

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
                Section("Admin") {
                    // Value-based link — pushed onto the NavigationPath binding
                    // in MainTabView so tab-switching correctly resets to root.
                    NavigationLink(value: ProfileNavDestination.schedule) {
                        Label("Manage Schedule", systemImage: "calendar.badge.plus")
                    }
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
        .navigationDestination(for: ProfileNavDestination.self) { destination in
            switch destination {
            case .schedule:
                ScheduleView()
            }
        }
    }
}

#Preview {
    NavigationStack { ProfileView() }
        .environmentObject(AuthViewModel())
}
