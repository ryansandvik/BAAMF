import SwiftUI

/// Shows all submitted books during the veto phase.
/// Members can cast "Read It" (already read) or "Hard Pass" (don't want to read) vetoes.
/// The host or admin closes the window and advances the month to voting.
struct VetoView: View {

    let month: ClubMonth
    let allMembers: [Member]

    @StateObject private var viewModel = VetoViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel

    // Confirmation dialogs
    @State private var pendingReadItBookId: String?
    @State private var pendingHardPassBook: Book?
    /// Set true when the user taps "No Thanks" on the replacement banner.
    /// Session-only — the banner reappears on next launch if they still need to resubmit.
    @State private var replacementBannerDismissed = false

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
        .task {
            if let monthId = month.id {
                viewModel.start(monthId: monthId)
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
        // Read It confirmation
        .confirmationDialog(
            "Read It — Remove This Book?",
            isPresented: Binding(
                get: { pendingReadItBookId != nil },
                set: { if !$0 { pendingReadItBookId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Yes, I've Already Read It", role: .destructive) {
                if let bookId = pendingReadItBookId {
                    Task { await castReadIt(bookId: bookId) }
                }
            }
            Button("Cancel", role: .cancel) { pendingReadItBookId = nil }
        } message: {
            Text("This will permanently remove the book from this month's submissions.")
        }
        // Hard Pass confirmation
        .confirmationDialog(
            "Hard Pass — Use a Charge?",
            isPresented: Binding(
                get: { pendingHardPassBook != nil },
                set: { if !$0 { pendingHardPassBook = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Use 1 Charge — Hard Pass", role: .destructive) {
                if let book = pendingHardPassBook {
                    Task { await castHardPass(book: book) }
                }
            }
            Button("Cancel", role: .cancel) { pendingHardPassBook = nil }
        } message: {
            if let book = pendingHardPassBook {
                Text("You'll use 1 Hard Pass charge (\(availableCharges - 1) remaining after this). If \(threshold) members Hard Pass \"\(book.title)\", it stays in voting but is penalized \u{2212}2 points in Round 1.")
            }
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {

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
                NavigationLink {
                    BookSearchView(month: month, onSubmitted: {})
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
        HStack(spacing: 12) {
            Image(systemName: "bolt.shield")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Hard Pass Charges")
                    .font(.footnote.bold())
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
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Read It button

    @ViewBuilder
    private func readItButton(_ book: Book) -> some View {
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
}
