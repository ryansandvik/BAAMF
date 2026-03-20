import SwiftUI
import Combine

/// The Home tab — shows up to three month cards in a vertical feed:
///   • Previous month (if still in an active phase — catches late-running months)
///   • Current month (primary card)
///   • Next month (once its document has been auto-created)
struct HomeView: View {

    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var router = DeepLinkRouter.shared
    @State private var showCreateMonth = false
    @State private var managingMonth: ClubMonth? = nil
    /// Drives the replacement BookSearchView via navigationDestination (lifted out of LazyVStack
    /// to avoid the blank-screen bug with closure-based NavigationLink in lazy containers).
    @State private var replacementSearchMonth: ClubMonth? = nil
    /// Drives deep-link navigation to VetoView when a veto notification is tapped.
    @State private var deepLinkedVetoMonth: ClubMonth? = nil

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading…")
            } else if viewModel.hasAnyMonth {
                monthFeed
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
        .sheet(item: $managingMonth) { month in
            MonthManagementView(month: month)
                .environmentObject(authViewModel)
        }
        // Replacement search — lifted out of LazyVStack to prevent blank-screen bug.
        .navigationDestination(item: $replacementSearchMonth) { m in
            BookSearchView(month: m, onSubmitted: { replacementSearchMonth = nil })
        }
        // Deep-link destination: veto notification tap → VetoView for that month.
        .navigationDestination(item: $deepLinkedVetoMonth) { month in
            VetoView(month: month, allMembers: viewModel.allMembers)
        }
        // When a pending veto deep link arrives (set by AppDelegate after notification tap),
        // find the matching month and push VetoView. Fires once months are loaded.
        .onChange(of: router.pendingLink) { _, link in
            resolveDeepLink(link)
        }
        .onChange(of: viewModel.currentMonth) { _, _ in
            // Retry resolution in case months weren't loaded when the link arrived.
            resolveDeepLink(router.pendingLink)
        }
    }

    private func resolveDeepLink(_ link: AppDeepLink?) {
        guard case let .veto(monthId) = link else { return }
        let candidates = [viewModel.previousMonth, viewModel.currentMonth, viewModel.nextMonth]
            .compactMap { $0 }
        if let match = candidates.first(where: { $0.id == monthId }) {
            deepLinkedVetoMonth = match
            _ = router.consume()
        }
    }

    // MARK: - Multi-card feed

    private var monthFeed: some View {
        ScrollView {
            LazyVStack(spacing: 16) {

                // Previous month — only shown while still in an active phase
                if let prev = viewModel.previousMonth {
                    feedLabel("Previous Month — Still Active",
                              icon: "exclamationmark.circle.fill",
                              color: .orange)
                    monthCard(prev, checkReplacement: false)
                }

                // Current month — primary card
                if let curr = viewModel.currentMonth {
                    monthCard(curr)
                }

                // Next month — appears once auto-created on .reading advance
                if let next = viewModel.nextMonth {
                    feedLabel("Up Next", icon: "calendar", color: .secondary)
                    monthCard(next, checkReplacement: false)
                }
            }
            .padding()
        }
    }

    private func feedLabel(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.bold())
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Month card

    @ViewBuilder
    private func monthCard(_ month: ClubMonth, checkReplacement: Bool = true) -> some View {
        let needsOrangeHighlight = checkReplacement
            && month.status == .vetoes
            && viewModel.userNeedsReplacement(userId: authViewModel.currentUserId ?? "")

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
                        let canManage = (authViewModel.currentUserId ?? "") == month.hostId
                            || authViewModel.isAdmin
                        if canManage {
                            Button {
                                managingMonth = month
                            } label: {
                                Image(systemName: "gearshape")
                                    .font(.body)
                                    .foregroundStyle(.tint)
                            }
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
            phaseContent(month, checkReplacement: checkReplacement)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

            // ── Attendance ───────────────────────────────────────────────────
            if let monthId = month.id {
                Divider()
                AttendanceSection(
                    monthId: monthId,
                    currentUserId: authViewModel.currentUserId ?? "",
                    allMembers: viewModel.allMembers,
                    eventDate: month.eventDate
                )
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
        }
        .background(
            needsOrangeHighlight
                ? Color.orange.opacity(0.08)
                : Color(.secondarySystemGroupedBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    needsOrangeHighlight
                        ? Color.orange.opacity(0.35)
                        : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    // MARK: - Phase content

    @ViewBuilder
    private func phaseContent(_ month: ClubMonth, checkReplacement: Bool = true) -> some View {
        switch month.status {
        case .setup:       setupContent(month)
        case .submissions: submissionsContent(month)
        case .vetoes:      vetoesContent(month, checkReplacement: checkReplacement)
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
        let currentUserId = authViewModel.currentUserId ?? ""
        let isHost        = currentUserId == month.hostId
        let isAdminOnly   = authViewModel.isAdmin && !isHost

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "gearshape")
                    .font(.title2).foregroundStyle(.tint).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host Setup").font(.headline)
                    if isHost {
                        Text("You're the host — configure submission mode and event details to get started.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("The host is choosing a submission mode and setting event details.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            // Prominent host CTA — only shown to the host themselves
            if isHost {
                NavigationLink {
                    HostSetupView(month: month)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "pencil.and.list.clipboard")
                            .font(.subheadline.bold())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set Up Your Month")
                                .font(.subheadline.bold())
                            Text("Choose a mode, set your event date, and open submissions.")
                                .font(.caption)
                                .foregroundStyle(.tint.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tint.opacity(0.6))
                    }
                    .padding(12)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            } else if isAdminOnly {
                // Subtle link for admins who aren't the host
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
                    if let deadline = month.submissionDeadline {
                        deadlineLabel(deadline)
                    }
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
    private func vetoesContent(_ month: ClubMonth, checkReplacement: Bool = true) -> some View {
        let needsReplacement = checkReplacement
            && viewModel.userNeedsReplacement(userId: authViewModel.currentUserId ?? "")

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
                    if let deadline = month.vetoDeadline {
                        deadlineLabel(deadline)
                    }
                }
            }

            if needsReplacement {
                Button {
                    replacementSearchMonth = month
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
                    if let deadline = month.votingR1Deadline {
                        deadlineLabel(deadline)
                    }
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
                    if let deadline = month.votingR2Deadline {
                        deadlineLabel(deadline)
                    }
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
                if let submitterId = month.selectedBookSubmitterId {
                    Text("Submitted by \(viewModel.memberName(for: submitterId))")
                        .font(.caption)
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
                    if let title = month.selectedBookTitle {
                        Text(title).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let submitterId = month.selectedBookSubmitterId {
                        Text("Submitted by \(viewModel.memberName(for: submitterId))")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
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

    // MARK: - Deadline label

    @ViewBuilder
    private func deadlineLabel(_ date: Date) -> some View {
        let isPast = date < Date()
        Label(
            isPast
                ? "Closed \(date.formatted(date: .abbreviated, time: .omitted))"
                : "Closes \(date.formatted(date: .abbreviated, time: .shortened))",
            systemImage: isPast ? "clock.badge.xmark" : "clock.badge"
        )
        .font(.caption2)
        .foregroundStyle(isPast ? Color.red : Color.orange)
        .padding(.top, 2)
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

    private var currentYear:  Int { Calendar.current.component(.year,  from: Date()) }
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

// MARK: - Attendance section (embedded in each month card)

private struct AttendanceSection: View {

    let monthId: String
    let currentUserId: String
    let allMembers: [Member]
    /// When non-nil and in the past, the attendance toggle is locked to read-only
    /// and the label switches from "Attending?" to "Attended?".
    let eventDate: Date?

    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var vm: AttendanceViewModel
    @State private var showRoster = false

    init(monthId: String, currentUserId: String, allMembers: [Member], eventDate: Date? = nil) {
        self.monthId = monthId
        self.currentUserId = currentUserId
        self.allMembers = allMembers
        self.eventDate = eventDate
        _vm = StateObject(wrappedValue: AttendanceViewModel(monthId: monthId))
    }

    private var userStatus: Bool? { vm.currentUserStatus(uid: currentUserId) }
    /// True once the event date has passed — attendance becomes read-only.
    private var isLocked: Bool { eventDate.map { $0 < Date() } ?? false }

    var body: some View {
        HStack(spacing: 12) {
            // Attending toggle label — switches to past tense once the event ends
            HStack(spacing: 8) {
                Image(systemName: "person.fill.checkmark")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                Text(isLocked ? "Attended?" : "Attending?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Yes / No segmented buttons
            HStack(spacing: 6) {
                attendanceButton(label: "Yes", value: true)
                attendanceButton(label: "No",  value: false)
            }

            // Summary pill — tappable to show roster
            if vm.attendingCount > 0 || vm.notAttendingCount > 0 {
                Button { showRoster = true } label: {
                    Text("\(vm.attendingCount) going")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Roster icon button
            Button { showRoster = true } label: {
                Image(systemName: "person.2")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .task { vm.start() }
        .onDisappear { vm.stop() }
        .sheet(isPresented: $showRoster) {
            AttendanceRosterSheet(allMembers: allMembers, records: vm.records)
        }
    }

    @ViewBuilder
    private func attendanceButton(label: String, value: Bool) -> some View {
        let isSelected = userStatus == value
        Button {
            Task { await vm.setAttendance(attending: value, uid: currentUserId) }
        } label: {
            Text(label)
                .font(.caption.bold())
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isSelected
                    ? (value ? Color.green : Color.red).opacity(0.15)
                    : Color(.systemGray5))
                .foregroundStyle(isSelected
                    ? (value ? Color.green : Color.red)
                    : Color.secondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? (value ? Color.green : Color.red).opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
                )
                .opacity(isLocked ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLocked || authViewModel.isObserver)
    }
}

#Preview {
    NavigationStack {
        HomeView().environmentObject(AuthViewModel())
    }
}
