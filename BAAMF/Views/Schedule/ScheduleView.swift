import SwiftUI

/// Shows the host schedule for the current year and lets members request swaps.
/// Full implementation in Phase 6.
struct ScheduleView: View {
    var body: some View {
        ContentUnavailableView(
            "Host Schedule",
            systemImage: "calendar",
            description: Text("The host rotation and swap requests will appear here.\nComing in Phase 6.")
        )
        .navigationTitle("Schedule")
    }
}

#Preview { ScheduleView() }
