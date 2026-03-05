import SwiftUI

/// Small colored pill showing the current month status.
struct StatusBadge: View {

    let status: MonthStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor.opacity(0.15))
            .foregroundStyle(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch status {
        case .setup:        return .gray
        case .submissions:  return .blue
        case .vetoes:       return .orange
        case .votingR1:     return .indigo
        case .votingR2:     return .purple
        case .reading:      return .teal
        case .scoring:      return .yellow
        case .complete:     return .green
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        ForEach(MonthStatus.allCases, id: \.self) { status in
            StatusBadge(status: status)
        }
    }
    .padding()
}
