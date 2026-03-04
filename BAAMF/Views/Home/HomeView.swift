import SwiftUI
import Combine

/// The Home tab — adapts its content to whatever phase the current month is in.
struct HomeView: View {

    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading…")
            } else if let month = viewModel.currentMonth {
                monthContent(month)
            } else {
                noMonthView
            }
        }
        .navigationTitle("BAAMF")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    authViewModel.signOut()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .task {
            if let uid = authViewModel.currentUserId {
                viewModel.start(currentUserId: uid)
            }
        }
        .onDisappear { viewModel.stop() }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Month content (status-driven)

    @ViewBuilder
    private func monthContent(_ month: ClubMonth) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Month header card
                monthHeaderCard(month)

                // Status-specific content
                switch month.status {
                case .setup:
                    setupSection(month)
                case .submissions:
                    submissionsSection(month)
                case .vetoes:
                    vetoesSection(month)
                case .votingR1:
                    votingR1Section(month)
                case .votingR2:
                    votingR2Section(month)
                case .scoring:
                    scoringSection(month)
                case .complete:
                    completeSection(month)
                }
            }
            .padding()
        }
    }

    // MARK: - Month header

    private func monthHeaderCard(_ month: ClubMonth) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(month.month.monthName + " \(month.year)")
                        .font(.title2.bold())
                    Text("Host: \(viewModel.memberName(for: month.hostId))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(status: month.status)
            }

            if let eventDate = month.eventDate {
                Label(eventDate.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let location = month.eventLocation, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Status sections (placeholders — filled in later phases)

    private func setupSection(_ month: ClubMonth) -> some View {
        PhaseCard(
            icon: "gearshape",
            title: "Host Setup",
            description: "The host is choosing a submission mode and setting event details.",
            isCurrentUserAction: viewModel.isCurrentUserHost(userId: authViewModel.currentUserId ?? "")
                || authViewModel.isAdmin
        ) {
            // Phase 2: HostSetupView()
        }
    }

    private func submissionsSection(_ month: ClubMonth) -> some View {
        PhaseCard(
            icon: "tray.and.arrow.up",
            title: "Submissions Open",
            description: month.submissionMode == .theme
                ? "Theme: \(month.theme ?? ""). Submit a book that fits."
                : month.submissionMode == .pick4
                    ? "The host is selecting 4 books."
                    : "Submit a book you'd love the club to read.",
            isCurrentUserAction: true
        ) {
            // Phase 2: SubmissionsView()
        }
    }

    private func vetoesSection(_ month: ClubMonth) -> some View {
        PhaseCard(
            icon: "hand.raised",
            title: "Veto Window",
            description: "Review the submitted books. Veto any you've already read or don't want to read.",
            isCurrentUserAction: true
        ) {
            // Phase 3: VetoView()
        }
    }

    private func votingR1Section(_ month: ClubMonth) -> some View {
        PhaseCard(
            icon: "hand.thumbsup",
            title: "Voting — Round 1",
            description: "Cast your 2 votes. Voting is anonymous and live.",
            isCurrentUserAction: true
        ) {
            // Phase 4: VotingR1View()
        }
    }

    private func votingR2Section(_ month: ClubMonth) -> some View {
        PhaseCard(
            icon: "rosette",
            title: "Voting — Round 2",
            description: "Top books remain. Cast your final vote.",
            isCurrentUserAction: true
        ) {
            // Phase 4: VotingR2View()
        }
    }

    private func scoringSection(_ month: ClubMonth) -> some View {
        PhaseCard(
            icon: "star.fill",
            title: "Scoring",
            description: "Rate this month's book on a 1–7 scale.",
            isCurrentUserAction: true
        ) {
            // Phase 5: ScoringView()
        }
    }

    private func completeSection(_ month: ClubMonth) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Month Complete")
                .font(.headline)
            if let score = month.groupAvgScore {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("Group average: \(score.scoreDisplay)")
                        .font(.subheadline)
                }
            }
            Text("See the full history in the History tab.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - No month view

    private var noMonthView: some View {
        ContentUnavailableView(
            "No Active Month",
            systemImage: "calendar.badge.exclamationmark",
            description: Text("No month document found for \(Date().monthYearDisplay()). An administrator needs to create one.")
        )
    }
}

// MARK: - PhaseCard component (local to HomeView for now)

private struct PhaseCard<Destination: View>: View {
    let icon: String
    let title: String
    let description: String
    let isCurrentUserAction: Bool
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if isCurrentUserAction {
                // Phase 2+: NavigationLink to destination()
                Text("Coming in next phase…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environmentObject(AuthViewModel())
    }
}
