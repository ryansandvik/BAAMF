import SwiftUI

/// Lists all completed months with their winning book and group average score.
/// Full implementation in Phase 5.
struct HistoryListView: View {
    var body: some View {
        ContentUnavailableView(
            "History",
            systemImage: "clock.fill",
            description: Text("Past months and scores will appear here.\nComing in Phase 5.")
        )
        .navigationTitle("History")
    }
}

#Preview { HistoryListView() }
