import SwiftUI
import Combine

/// The Home tab — adapts its content to whatever phase the current month is in.
struct HomeView: View {

    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel = HomeViewModel()
    @State private var showCreateMonth = false
    @State private var showManageMonth = false

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
        .sheet(isPresented: $showManageMonth) {
            if let month = viewModel.currentMonth {
                MonthManagementView(month: month)
                    .environmentObject(authViewModel)
            }
        }
    }

    // MARK: - Month content

    @ViewBuilder
    private func monthContent(_ month: ClubMonth) -> some View {
        let needsOrangeHighlight = month.status == .vetoes
            && viewModel.userNeedsReplacement(userId: authViewModel.currentUserId ?? "")

        ScrollView {
            VStack(spacing: 0) {

                // ── Header ──────────────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(month.month.monthName + " \(month.year)")
                                .font(.title2.bold())
                            Text("Host: \(viewModel.memberName(for: month.hostId))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            StatusBadge(status: month.status)
                            // Gear is available to all users — phase controls inside are
                            // gated to host/admin; everyone sees Sign Out.
                            Button {
                                showManageMonth = true
                            } label: {
                                Image(systemName: "gearshape")
                                    .font(.body)
                                    .foregroundStyle(.tint)
                            }
                        }
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

                Divider()

                // ── Phase section ────────────────────────────────────────────────
                phaseContent(month)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(
                needsOrangeHighlight
                    ? Color.orange.opacity(0.08)
                    : Color(.secondarySystemGroupedBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                if needsOrangeHighlight {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                }
            }
            .padding()
        }
    }

    // MARK: - Phase content (inner, no background — combined card wraps it)

    @ViewBuilder
    private func phaseContent(_ month: ClubMonth) -> some View {
        switch month.status {
        case .setup:       setupContent(month)
        case .submissions: submissionsContent(month)
        case .vetoes:      vetoesContent(month)
        case .votingR1:    votingR1Content(month)
        case .votingR2:    votingR2Content(month)
        case .reading:     readingContent(month)
        case .scoring:     scoringContent(month)
        case .complete:    completeContent(month)
        }
    }

    // MARK: Setup

    @ViewBuilder
    private func setupContent(_ month: ClubMonth) -> some View {
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
    }

    // MARK: Submissions

    @ViewBuilder
    private func submissionsContent(_ month: ClubMonth) -> some View {
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
    }

    // MARK: Vetoes

    @ViewBuilder
    private func vetoesContent(_ month: ClubMonth) -> some View {
        let needsReplacement = viewModel.userNeedsReplacement(
            userId: authViewModel.currentUserId ?? "")

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: needsReplacement ? "exclamationmark.triangle.fill" : "hand.raised")
                    .font(.title2)
                    .foregroundStyle(needsReplacement ? Color.orange : Color.accentColor)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Veto Window").font(.headline)
                    if needsReplacement {
                        Text("Your book was removed — you can submit a replacement before voting opens.")
                            .font(.footnote).foregroundStyle(.orange)
                    } else {
                        Text("Review submitted books. Veto any you've read or don't want to read.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            if needsReplacement {
                NavigationLink {
                    BookSearchView(month: month, onSubmitted: {})
                } label: {
                    Text("Submit Replacement →")
                        .font(.footnote.bold())
                        .foregroundStyle(.orange)
                }
            }

            NavigationLink {
                VetoView(month: month, allMembers: viewModel.allMembers)
            } label: {
                Text("Review & Veto →")
                    .font(.footnote.bold())
                    .foregroundStyle(.tint)
            }
        }
    }

    // MARK: Voting R1

    @ViewBuilder
    private func votingR1Content(_ month: ClubMonth) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "hand.thumbsup")
                    .font(.title2).foregroundStyle(.tint).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Voting — Round 1").font(.headline)
                    Text("Cast your 2 votes. Voting is anonymous.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                VotingR1View(month: month, allMembers: viewModel.allMembers)
            } label: {
                Text("Vote Now →")
                    .font(.footnote.bold())
                    .foregroundStyle(.tint)
            }
        }
    }

    // MARK: Voting R2

    @ViewBuilder
    private func votingR2Content(_ month: ClubMonth) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "rosette")
                    .font(.title2).foregroundStyle(.tint).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Voting — Round 2").font(.headline)
                    Text("The top books have advanced. Cast your final vote.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                VotingR2View(month: month, allMembers: viewModel.allMembers)
            } label: {
                Text("Vote Now →")
                    .font(.footnote.bold())
                    .foregroundStyle(.tint)
            }
        }
    }

    // MARK: Reading

    @ViewBuilder
    private func readingContent(_ month: ClubMonth) -> some View {
        HStack(alignment: .top, spacing: 16) {
            if let coverUrl = month.selectedBookCoverUrl {
                CoverImage(url: coverUrl, size: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 56, height: 80)
                    .overlay {
                        Image(systemName: "book.fill")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("This Month's Pick")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                if let title = month.selectedBookTitle {
                    Text(title)
                        .font(.headline)
                        .lineLimit(3)
                }
                if let author = month.selectedBookAuthor {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("Scoring opens at your event.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }

            Spacer()
        }
    }

    // MARK: Scoring

    @ViewBuilder
    private func scoringContent(_ month: ClubMonth) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.title2).foregroundStyle(.tint).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scoring").font(.headline)
                    Text("Rate this month's book on a 1–7 scale.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                ScoringView(month: month, allMembers: viewModel.allMembers)
            } label: {
                Text("Score Now →")
                    .font(.footnote.bold())
                    .foregroundStyle(.tint)
            }
        }
    }

    // MARK: Complete

    @ViewBuilder
    private func completeContent(_ month: ClubMonth) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2).foregroundStyle(.green).frame(width: 32)
                Text("Month Complete").font(.headline)
            }
            if let score = month.groupAvgScore {
                HStack {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                    Text("Group average: \(score.scoreDisplay)").font(.subheadline)
                }
            }
            Text("See the full history in the History tab.")
                .font(.footnote).foregroundStyle(.secondary)
        }
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
