import SwiftUI

/// Round 1 voting view.
/// Members cast up to 2 votes for different books. Voter identities and live tallies
/// are hidden — only the user's own vote state is shown. Votes can be changed until
/// the host closes the round.
struct VotingR1View: View {

    let month: ClubMonth
    let allMembers: [Member]

    @StateObject private var viewModel = VotingViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel

    private var currentUserId: String { authViewModel.currentUserId ?? "" }

    private var votesCast: Int { viewModel.r1VotesCast(userId: currentUserId) }
    private var votesRemaining: Int { K.Voting.r1VotesPerMember - votesCast }
    private var hasFinishedVoting: Bool { votesRemaining == 0 }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading…")
            } else {
                mainContent
            }
        }
        .navigationTitle("Round 1 Voting")
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
                ForEach(viewModel.r1Books) { book in
                    r1BookRow(book)
                }
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Voting header

    private var votingHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: hasFinishedVoting ? "checkmark.circle.fill" : "hand.thumbsup")
                .font(.title3)
                .foregroundStyle(hasFinishedVoting ? Color.green : Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(hasFinishedVoting ? "Votes submitted!" : "Cast your 2 votes")
                    .font(.footnote.bold())

                HStack(spacing: 4) {
                    ForEach(0..<K.Voting.r1VotesPerMember, id: \.self) { i in
                        Image(systemName: i < votesCast ? "circle.fill" : "circle")
                            .font(.caption)
                            .foregroundStyle(i < votesCast ? Color.accentColor : Color.secondary)
                    }
                    Text(hasFinishedVoting
                         ? "Tap a voted book to change your vote."
                         : "\(votesRemaining) vote\(votesRemaining == 1 ? "" : "s") remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let deadline = month.votingR1Deadline {
                    let isPast = deadline < Date()
                    Label(
                        isPast
                            ? "Closed \(deadline.formatted(date: .abbreviated, time: .omitted))"
                            : "Closes \(deadline.formatted(date: .abbreviated, time: .shortened))",
                        systemImage: isPast ? "clock.badge.xmark" : "clock.badge"
                    )
                    .font(.caption2)
                    .foregroundStyle(isPast ? Color.red : Color.orange)
                    .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding()
        .cardStyle()
        .padding(.horizontal)
    }

    // MARK: - Book row

    @ViewBuilder
    private func r1BookRow(_ book: Book) -> some View {
        let voted = viewModel.hasVotedR1(book: book, userId: currentUserId)
        let canVote = !voted && votesRemaining > 0

        VStack(spacing: 0) {
            BookCard(
                book: book,
                submitterName: memberName(for: book.submitterId),
                showSubmitter: false  // anonymous during voting
            )

            Divider().padding(.horizontal)

            HStack(spacing: 12) {
                // Hard Pass penalty is a factual label, not a live tally
                if book.vetoType2Penalty {
                    Label("Hard Pass penalty (\u{2212}2 pts)", systemImage: "minus.circle")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.8))
                }
                Spacer()

                if voted {
                    // Tapping "Voted" removes the vote so the user can change their mind
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
        .cardStyle()
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func memberName(for userId: String) -> String {
        allMembers.first { $0.id == userId }?.name ?? "Unknown"
    }

    private func castVote(for book: Book) async {
        guard let bookId = book.id, let monthId = month.id else { return }
        await viewModel.castR1Vote(bookId: bookId, monthId: monthId, userId: currentUserId)
    }

    private func removeVote(for book: Book) async {
        guard let bookId = book.id, let monthId = month.id else { return }
        await viewModel.removeR1Vote(bookId: bookId, monthId: monthId, userId: currentUserId)
    }
}
