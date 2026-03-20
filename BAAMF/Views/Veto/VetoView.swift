import SwiftUI

/// Shows all submitted books during the veto phase.
/// Members can cast "Read It" (already read) or "Hard Pass" (don't want to read) vetoes.
/// The host or admin closes the window and advances the month to voting.
struct VetoView: View {

    let month: ClubMonth
    let allMembers: [Member]

    @StateObject private var viewModel = VetoViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    // Confirmation dialogs
    @State private var pendingReadItBookId: String?
    @State private var pendingHardPassBook: Book?
    /// Set true when the user taps "No Thanks" on the replacement banner.
    /// Session-only — the banner reappears on next launch if they still need to resubmit.
    @State private var replacementBannerDismissed = false
    /// Set true when the user confirms they're done reviewing and have no vetoes to cast.
    /// Session-only dismissal of the "okay with selections" prompt.
    @State private var acceptedSelections = false
    /// Drives the replacement BookSearchView via navigationDestination (lifted out of
    /// LazyVStack to avoid the blank-screen bug with closure-based NavigationLink in lazy contexts).
    @State private var showingReplacementSearch = false
    /// Shows the combined Veto Guide sheet (Read It + Hard Pass).
    @State private var showVetoGuide = false
    /// Persisted flag — guide is shown automatically on first open only.
    @AppStorage("vetoGuideSeenV1") private var hasSeenVetoGuide = false

    private var currentUserId: String { authViewModel.currentUserId ?? "" }

    /// Sourced from the live ViewModel listener so charge counts update immediately
    /// after a Hard Pass — the parent's `allMembers` is a one-time snapshot and would lag.
    private var currentMember: Member? {
        viewModel.members.first { $0.id == currentUserId }
    }

    private var availableCharges: Int {
        currentMember?.availableVetoCharges() ?? 0
    }

    private var nextChargeDate: Date? {
        currentMember?.nextHardPassChargeDate()
    }

    private var threshold: Int {
        viewModel.hardPassThreshold(memberCount: allMembers.count)
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading…")
            } else {
                mainContent
            }
        }
        .navigationTitle("Veto Window")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showVetoGuide = true } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .task {
            if let monthId = month.id {
                viewModel.start(monthId: monthId)
                // Mark as reviewed immediately so BadgeService clears the badge
                // as soon as the user opens this screen.
                await viewModel.markVetoReviewed(monthId: monthId, userId: currentUserId)
            }
            // Show the guide automatically the very first time the user opens Vetoes.
            if !hasSeenVetoGuide {
                hasSeenVetoGuide = true
                showVetoGuide = true
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
        // Replacement search — lifted out of LazyVStack to avoid the blank-screen bug
        // that occurs when closure-based NavigationLink is used inside a lazy container.
        .navigationDestination(isPresented: $showingReplacementSearch) {
            BookSearchView(month: month, onSubmitted: {})
        }
        // Veto guide sheet (auto-shown first time; also reachable via toolbar button)
        .sheet(isPresented: $showVetoGuide) {
            vetoGuideSheet
        }
        // Read It confirmation
        .sheet(isPresented: Binding(
            get: { pendingReadItBookId != nil },
            set: { if !$0 { pendingReadItBookId = nil } }
        )) {
            ConfirmActionSheet(
                title: "Read It — Remove This Book?",
                message: "This will permanently remove the book from this month's submissions."
            ) {
                SheetActionButton(label: "Yes, I've Already Read It", role: .destructive) {
                    if let bookId = pendingReadItBookId {
                        Task { await castReadIt(bookId: bookId) }
                    }
                }
                Divider()
                SheetActionButton(label: "Cancel", role: .cancel) {
                    pendingReadItBookId = nil
                }
            }
        }
        // Hard Pass confirmation
        .sheet(item: $pendingHardPassBook) { book in
            ConfirmActionSheet(
                title: "Hard Pass — Use a Charge?",
                message: "You'll use 1 charge (\(availableCharges - 1) remaining after this). If \(threshold) members Hard Pass \"\(book.title)\", it stays in voting but receives a \u{2212}2 point penalty in Round 1."
            ) {
                SheetActionButton(label: "Use 1 Charge — Hard Pass", role: .destructive) {
                    Task { await castHardPass(book: book) }
                }
                Divider()
                SheetActionButton(label: "Cancel", role: .cancel) {
                    pendingHardPassBook = nil
                }
            }
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {

                if let deadline = month.vetoDeadline {
                    phaseDeadlineRow(deadline)
                }

                chargesHeader

                // Replacement banner — shown when the user's book was Read It'd
                if !replacementBannerDismissed &&
                    viewModel.canResubmit(userId: currentUserId, month: month) {
                    replacementBanner
                }

                if viewModel.eligibleBooks.isEmpty && viewModel.removedBooks.isEmpty {
                    ContentUnavailableView(
                        "No Books",
                        systemImage: "tray",
                        description: Text("No books were submitted this month.")
                    )
                } else {
                    // Eligible books
                    ForEach(viewModel.eligibleBooks) { book in
                        vetoBookRow(book)
                    }

                    // Removed books (collapsed section for transparency)
                    if !viewModel.removedBooks.isEmpty {
                        removedSection
                    }

                    // "Okay with selections" — lets members signal they've reviewed
                    // the veto window without needing to take any action.
                    if !acceptedSelections && !viewModel.eligibleBooks.isEmpty {
                        okayWithSelectionsCard
                    } else if acceptedSelections {
                        acceptedConfirmation
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Replacement banner

    private var replacementBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Book Was Removed")
                        .font(.headline)
                    Text("A member has already read your submission. You can submit a replacement before the veto window closes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button {
                    showingReplacementSearch = true
                } label: {
                    Text("Submit Replacement")
                        .font(.footnote.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Button("No Thanks") {
                    withAnimation { replacementBannerDismissed = true }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Charges header

    private var chargesHeader: some View {
        Button {
            showVetoGuide = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bolt.shield")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Hard Pass Charges")
                        .font(.footnote.bold())
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        ForEach(0..<K.Veto.maxCharges, id: \.self) { i in
                            Image(systemName: i < availableCharges ? "circle.fill" : "circle")
                                .font(.caption)
                                .foregroundStyle(i < availableCharges ? Color.accentColor : Color.secondary)
                        }
                        Text(availableCharges == 0
                             ? "No charges available"
                             : "\(availableCharges) of \(K.Veto.maxCharges) available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let next = nextChargeDate {
                        Text("Next charge available: \(next.formatted(.dateTime.month(.wide).year()))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .padding()
        .cardStyle()
        .padding(.horizontal)
    }

    // MARK: - Veto book row

    @ViewBuilder
    private func vetoBookRow(_ book: Book) -> some View {
        VStack(spacing: 0) {
            BookCard(
                book: book,
                submitterName: memberName(for: book.submitterId),
                showSubmitter: month.submissionMode == .pick4
            )

            Divider()
                .padding(.horizontal)

            HStack(spacing: 12) {
                readItButton(book)
                Divider().frame(height: 36)
                hardPassSection(book)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .cardStyle()
        .padding(.horizontal)
    }

    // MARK: - Read It button

    @ViewBuilder
    private func readItButton(_ book: Book) -> some View {
        if authViewModel.isObserver {
            // Observers can browse but cannot veto
            Color.clear.frame(maxWidth: .infinity)
        } else if book.submitterId == currentUserId {
            // Can't Read It your own submission — show a non-interactive label instead
            VStack(spacing: 3) {
                Image(systemName: "person.fill")
                    .font(.subheadline)
                Text("Your Pick")
                    .font(.caption2.bold())
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.secondary)
        } else {
            Button {
                pendingReadItBookId = book.id
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "book.closed")
                        .font(.subheadline)
                    Text("Read It")
                        .font(.caption2.bold())
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.orange)
            }
            .disabled(viewModel.isActing)
        }
    }

    // MARK: - Hard Pass section

    @ViewBuilder
    private func hardPassSection(_ book: Book) -> some View {
        let alreadyPassed = viewModel.hasHardPassed(book: book, userId: currentUserId)
        let count = book.vetoType2Voters.count

        VStack(alignment: .leading, spacing: 4) {
            // Threshold progress
            HStack(spacing: 4) {
                ForEach(0..<threshold, id: \.self) { i in
                    Image(systemName: i < count ? "circle.fill" : "circle")
                        .font(.caption2)
                        .foregroundStyle(i < count ? Color.red : Color.secondary.opacity(0.5))
                }
                Text("\(count)/\(threshold) hard passed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if book.vetoType2Penalty {
                // Threshold met — book is penalized in Round 1
                Label("Penalized", systemImage: "minus.circle.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.red)
            } else if alreadyPassed {
                Label("Hard Pass cast", systemImage: "checkmark.circle.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.red)
            } else if availableCharges > 0 {
                Button {
                    pendingHardPassBook = book
                } label: {
                    Label("Hard Pass", systemImage: "bolt.shield")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }
                .disabled(viewModel.isActing)
            } else {
                Text("No charges available")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Removed books section

    private var removedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Removed (\(viewModel.removedBooks.count))")
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ForEach(viewModel.removedBooks) { book in
                HStack(spacing: 12) {
                    CoverImage(url: book.coverUrl, size: 44)
                        .opacity(0.4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(book.author)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Label("Read It — removed", systemImage: "book.closed")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.7))
                    }
                    Spacer()
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Veto guide sheet

    private var vetoGuideSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // MARK: Read It
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Read It")
                            .font(.headline)

                        infoRow(icon: "book.closed.fill", color: .orange,
                                title: "Remove a Book You've Already Read",
                                body: "Tap Read It on any book you've previously read. It's permanently removed from the pool so the club isn't voting on a book you can't enjoy fresh.")

                        infoRow(icon: "arrow.2.circlepath", color: .teal,
                                title: "Submitter Gets a Replacement",
                                body: "If your submission is removed by a Read It, you'll get a notification and can submit a replacement book before the veto window closes.")

                        infoRow(icon: "person.fill", color: .secondary,
                                title: "Can't Use on Your Own Submission",
                                body: "You can't Read It a book you submitted yourself. The action button is replaced with a \"Your Pick\" label instead.")
                    }

                    Divider()

                    // MARK: Hard Pass
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Hard Pass")
                            .font(.headline)

                        // Current charge status
                        HStack(spacing: 8) {
                            ForEach(0..<K.Veto.maxCharges, id: \.self) { i in
                                Image(systemName: i < availableCharges ? "bolt.shield.fill" : "bolt.shield")
                                    .font(.title2)
                                    .foregroundStyle(i < availableCharges ? Color.accentColor : Color.secondary.opacity(0.4))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(availableCharges == 0 ? "No charges available" : "\(availableCharges) of \(K.Veto.maxCharges) available")
                                    .font(.subheadline.bold())
                                if let next = nextChargeDate {
                                    Text("Refreshes \(next.formatted(.dateTime.month(.wide).year()))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle(cornerRadius: 10)

                        infoRow(icon: "bolt.shield.fill", color: .red,
                                title: "Cast a Hard Pass",
                                body: "Tap Hard Pass on any book you strongly don't want to read. Each Hard Pass costs 1 charge.")

                        infoRow(icon: "person.3.fill", color: .orange,
                                title: "Threshold (\(threshold) of \(allMembers.count) members)",
                                body: "If \(threshold) or more members Hard Pass the same book, it receives a \u{2212}2 vote penalty in Round 1. The book stays in voting — it's just harder to win.")

                        infoRow(icon: "calendar.badge.clock", color: .teal,
                                title: "12-Month Cooldown",
                                body: "Each charge cools down for 12 months from the first of the month you used it. A charge used in March 2025 is available again March 1, 2026.")

                        infoRow(icon: "arrow.clockwise", color: .blue,
                                title: "Maximum \(K.Veto.maxCharges) Charges",
                                body: "You can hold up to \(K.Veto.maxCharges) charges at once. Unused charges carry over month to month — saving them gives you more flexibility later.")
                    }

                    Spacer(minLength: 0)
                }
                .padding()
            }
            .navigationTitle("Veto Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showVetoGuide = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func infoRow(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                Text(body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .cardStyle(cornerRadius: 10)
    }

    // MARK: - Okay with selections

    private var okayWithSelectionsCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No Vetoes?")
                        .font(.footnote.bold())
                    Text("Tap below to confirm you're happy with the current selections.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    acceptedSelections = true
                }
                // Brief pause so the confirmation tick is visible, then return home.
                Task {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    dismiss()
                }
            } label: {
                Text("I'm okay with these selections")
                    .font(.footnote.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .disabled(viewModel.isActing)
        }
        .padding()
        .cardStyle()
        .padding(.horizontal)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var acceptedConfirmation: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("You're all set — no vetoes cast.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal)
        .cardStyle()
        .padding(.horizontal)
        .transition(.opacity)
    }

    // MARK: - Actions

    private func castReadIt(bookId: String) async {
        guard let monthId = month.id else { return }
        await viewModel.castReadItVeto(bookId: bookId, monthId: monthId)
        pendingReadItBookId = nil
    }

    private func castHardPass(book: Book) async {
        guard let bookId = book.id, let monthId = month.id else { return }
        await viewModel.castHardPassVeto(bookId: bookId,
                                         monthId: monthId,
                                         userId: currentUserId,
                                         memberCount: allMembers.count)
        pendingHardPassBook = nil
    }

    private func memberName(for userId: String) -> String {
        allMembers.first { $0.id == userId }?.name ?? "Unknown"
    }

    // MARK: - Phase deadline row

    private func phaseDeadlineRow(_ date: Date) -> some View {
        let isPast = date < Date()
        return Label(
            isPast
                ? "Closed \(date.formatted(date: .abbreviated, time: .omitted))"
                : "Closes \(date.formatted(date: .abbreviated, time: .shortened))",
            systemImage: isPast ? "clock.badge.xmark" : "clock.badge"
        )
        .font(.caption.bold())
        .foregroundStyle(isPast ? Color.red : Color.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
}
