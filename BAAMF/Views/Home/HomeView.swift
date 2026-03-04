import SwiftUI
import Combine

/// The Home tab — adapts its content to whatever phase the current month is in.
struct HomeView: View {

    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel = HomeViewModel()
    @State private var showCreateMonth = false

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
        .sheet(isPresented: $showCreateMonth) {
            CreateMonthSheet(allMembers: viewModel.allMembers)
        }
    }

    // MARK: - Month content (status-driven)

    @ViewBuilder
    private func monthContent(_ month: ClubMonth) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                monthHeaderCard(month)

                switch month.status {
                case .setup:        setupSection(month)
                case .submissions:  submissionsSection(month)
                case .vetoes:       vetoesSection(month)
                case .votingR1:     votingR1Section(month)
                case .votingR2:     votingR2Section(month)
                case .scoring:      scoringSection(month)
                case .complete:     completeSection(month)
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

    // MARK: - Status sections

    @ViewBuilder
    private func setupSection(_ month: ClubMonth) -> some View {
        let isHostOrAdmin = viewModel.isCurrentUserHost(userId: authViewModel.currentUserId ?? "")
            || authViewModel.isAdmin

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "gearshape")
                    .font(.title2).foregroundStyle(.tint).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host Setup").font(.headline)
                    Text("The host is choosing a submission mode and setting event details.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if isHostOrAdmin {
                NavigationLink {
                    HostSetupView(month: month)
                } label: {
                    Text("Configure Submissions →")
                        .font(.footnote.bold())
                        .foregroundStyle(.tint)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func submissionsSection(_ month: ClubMonth) -> some View {
        let description: String = {
            switch month.submissionMode {
            case .theme:  return "Theme: \(month.theme ?? "TBD"). Submit a book that fits."
            case .pick4:  return "The host is selecting 4 books."
            case .open:   return "Submit a book you'd love the club to read."
            }
        }()

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.up")
                    .font(.title2).foregroundStyle(.tint).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Submissions Open").font(.headline)
                    Text(description).font(.footnote).foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                SubmissionsView(month: month, allMembers: viewModel.allMembers)
            } label: {
                Text("View Submissions →")
                    .font(.footnote.bold())
                    .foregroundStyle(.tint)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func vetoesSection(_ month: ClubMonth) -> some View {
        PhaseCard(icon: "hand.raised", title: "Veto Window",
                  description: "Review submitted books. Veto any you've read or don't want to read.")
        // Phase 3: NavigationLink → VetoView
    }

    private func votingR1Section(_ month: ClubMonth) -> some View {
        PhaseCard(icon: "hand.thumbsup", title: "Voting — Round 1",
                  description: "Cast your 2 votes. Voting is anonymous and live.")
        // Phase 4: NavigationLink → VotingR1View
    }

    private func votingR2Section(_ month: ClubMonth) -> some View {
        PhaseCard(icon: "rosette", title: "Voting — Round 2",
                  description: "Top books remain. Cast your final vote.")
        // Phase 4: NavigationLink → VotingR2View
    }

    private func scoringSection(_ month: ClubMonth) -> some View {
        PhaseCard(icon: "star.fill", title: "Scoring",
                  description: "Rate this month's book on a 1–7 scale.")
        // Phase 5: NavigationLink → ScoringView
    }

    private func completeSection(_ month: ClubMonth) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Month Complete").font(.headline)
            if let score = month.groupAvgScore {
                HStack {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                    Text("Group average: \(score.scoreDisplay)").font(.subheadline)
                }
            }
            Text("See the full history in the History tab.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - No month view

    private var noMonthView: some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                "No Active Month",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("No document found for \(Date().monthYearDisplay()).")
            )
            if authViewModel.isAdmin {
                Button {
                    showCreateMonth = true
                } label: {
                    Label("Create Month", systemImage: "plus.circle.fill")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

// MARK: - Placeholder PhaseCard (for phases not yet implemented)

private struct PhaseCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2).foregroundStyle(.tint).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(description).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Create Month Sheet (admin only)

private struct CreateMonthSheet: View {

    let allMembers: [Member]

    @StateObject private var viewModel = HostSetupViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var selectedHostId: String = ""

    private var currentYear: Int  { Calendar.current.component(.year,  from: Date()) }
    private var currentMonth: Int { Calendar.current.component(.month, from: Date()) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Host", selection: $selectedHostId) {
                        Text("Select a host…").tag("")
                        ForEach(allMembers) { member in
                            Text(member.name).tag(member.id ?? "")
                        }
                    }
                } header: {
                    Text("Host for \(currentMonth.monthName) \(currentYear)")
                } footer: {
                    Text("The host will configure submissions once the month is created.")
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Create Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await viewModel.createMonth(
                                year: currentYear,
                                month: currentMonth,
                                hostId: selectedHostId
                            )
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedHostId.isEmpty || viewModel.isSaving)
                }
            }
            .onChange(of: viewModel.savedSuccessfully) { _, success in
                if success { dismiss() }
            }
        }
    }
}

#Preview {
    NavigationStack {
        HomeView().environmentObject(AuthViewModel())
    }
}
