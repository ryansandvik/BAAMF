import SwiftUI

/// Round 2 voting view.
/// Shows only the books that advanced from Round 1. Each member casts 1 final vote.
/// Live R2 tallies are hidden; only the user's own vote state is shown. The R1 net
/// score (previous round, now closed) is shown as context. Votes can be changed until
/// the host closes the round.
struct VotingR2View: View {

    let month: ClubMonth
    let allMembers: [Member]

    @StateObject private var viewModel = VotingViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel

    private var currentUserId: String { authViewModel.currentUserId ?? "" }

    private var hasVoted: Bool { viewModel.r2VotesCast(userId: currentUserId) > 0 }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading…")
            } else {
                mainContent
            }
        }
        .navigationTitle("Round 2")
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
    }

    // MARK: - Main content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                votingHeader

                if viewModel.r2Books.isEmpty {
                    ContentUnavailableView(
                        "No Books in Round 2",
                        systemImage: "rosette",
                        description: Text("The host hasn't advanced books from Round 1 yet.")
                    )
                } else {
                    ForEach(viewModel.r2Books) { book in
                        r2BookRow(book)
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Voting header

    private var votingHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: hasVoted ? "checkmark.circle.fill" : "rosette")
                .font(.title3)
                .foregroundStyle(hasVoted ? Color.green : Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(hasVoted ? "Vote submitted!" : "Cast your final vote")
                    .font(.footnote.bold())
                Text(hasVoted
                     ? "Tap your voted book to change your vote before the round closes."
                     : "The book with the most votes becomes the book of the month.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Book row

    @ViewBuilder
    private func r2BookRow(_ book: Book) -> some View {
        let voted = viewModel.hasVotedR2(book: book, userId: currentUserId)
        let canVote = !hasVoted  // only 1 vote allowed in R2

        VStack(spacing: 0) {
            BookCard(
                book: book,
                submitterName: memberName(for: book.submitterId),
                showSubmitter: false  // anonymous during voting
            )

            Divider().padding(.horizontal)

            HStack(spacing: 12) {
                // R1 net score is a closed-round result — fine to display
                Text("Round 1: \(book.r1NetVotes) net vote\(book.r1NetVotes == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if voted {
                    // Tapping removes the vote so the user can pick a different book
                    Button {
                        Task { await removeVote(for: book) }
                    } label: {
                        Label("Voted", systemImage: "checkmark.circle.fill")
                            .font(.caption.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color.green.opacity(0.12))
                            .foregroundStyle(Color.green)
                            .overlay(Capsule().strokeBorder(Color.green.opacity(0.5), lineWidth: 1))
                            .clipShape(Capsule())
                    }
                    .disabled(viewModel.isActing)
                } else {
                    Button {
                        Task { await castVote(for: book) }
                    } label: {
                        Text("Vote")
                            .font(.caption.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(canVote ? Color.accentColor : Color.secondary.opacity(0.2))
                            .foregroundStyle(canVote ? Color.white : Color.secondary)
                            .clipShape(Capsule())
                    }
                    .disabled(!canVote || viewModel.isActing)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func memberName(for userId: String) -> String {
        allMembers.first { $0.id == userId }?.name ?? "Unknown"
    }

    private func castVote(for book: Book) async {
        guard let bookId = book.id, let monthId = month.id else { return }
        await viewModel.castR2Vote(bookId: bookId, monthId: monthId, userId: currentUserId)
    }

    private func removeVote(for book: Book) async {
        guard let bookId = book.id, let monthId = month.id else { return }
        await viewModel.removeR2Vote(bookId: bookId, monthId: monthId, userId: currentUserId)
    }
}
