import SwiftUI
import Combine

/// Admin-only control panel: force status transitions, enter scores on behalf of members,
/// manage host schedule overrides. Full implementation in Phase 6.
struct AdminView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        List {
            Section {
                Label("Signed in as \(authViewModel.currentMember?.name ?? "Admin")",
                      systemImage: "person.fill.checkmark")
                    .foregroundStyle(.secondary)
            }

            Section("Coming in Phase 6") {
                Label("Force Status Transition", systemImage: "arrow.right.circle")
                    .foregroundStyle(.secondary)
                Label("Enter Scores on Behalf", systemImage: "pencil.circle")
                    .foregroundStyle(.secondary)
                Label("Manage Host Schedule", systemImage: "calendar.badge.plus")
                    .foregroundStyle(.secondary)
                Label("Force Swap", systemImage: "arrow.left.arrow.right")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Admin")
    }
}

#Preview {
    NavigationStack { AdminView() }
        .environmentObject(AuthViewModel())
}
