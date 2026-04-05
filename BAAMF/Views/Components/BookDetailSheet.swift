import SwiftUI
import FirebaseFirestore

/// Full-detail view for a submitted book: cover, title, author, description, page count, rating.
///
/// Usage — pass a pre-loaded book when you already have it (reading phase on home screen),
/// or pass `monthId` + `bookId` to fetch from Firestore (history detail view).
struct BookDetailSheet: View {

    /// Pre-loaded book. When nil the view fetches using monthId + bookId.
    var preloadedBook: Book? = nil
    var monthId: String? = nil
    var bookId: String? = nil
    /// Pass allMembers to resolve voter UIDs to names in the votes section.
    var allMembers: [Member] = []

    @State private var book: Book?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let db = FirestoreService.shared

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let book {
                    bookContent(book)
                } else if let error = errorMessage {
                    ContentUnavailableView("Couldn't Load Book",
                                          systemImage: "book.closed",
                                          description: Text(error))
                } else {
                    ContentUnavailableView("No Book Info",
                                          systemImage: "book.closed")
                }
            }
            .navigationTitle("Book Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Content

    private func bookContent(_ book: Book) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header: cover + title/author/meta
                HStack(alignment: .top, spacing: 16) {
                    CoverImage(url: book.coverUrl, size: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(.title3.bold())
                            .lineLimit(4)
                        Text(book.author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            if let pages = book.pageCount, pages > 0 {
                                Label("\(pages) pages", systemImage: "book")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let rating = book.googleRating {
                                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding()
                .cardStyle()

                // Description
                let displayText = book.displayDescription
                if !displayText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Text(displayText)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .padding()
                    .cardStyle()
                }

                // Votes — shown whenever we have voter data
                let r2Voters = book.votingR2Voters
                let r1Voters = book.votingR1Voters
                if !r2Voters.isEmpty || !r1Voters.isEmpty {
                    votesSection(book: book, r1Voters: r1Voters, r2Voters: r2Voters)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Votes section

    @ViewBuilder
    private func votesSection(book: Book, r1Voters: [String], r2Voters: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Votes")
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().padding(.horizontal)

            if !r2Voters.isEmpty {
                voteRow(
                    round: "Round 2",
                    voters: r2Voters,
                    color: .yellow
                )
            }

            if !r2Voters.isEmpty && !r1Voters.isEmpty {
                Divider().padding(.horizontal)
            }

            if !r1Voters.isEmpty {
                voteRow(
                    round: "Round 1",
                    voters: r1Voters,
                    color: .secondary
                )
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func voteRow(round: String, voters: [String], color: Color) -> some View {
        let names = voters
            .compactMap { uid in allMembers.first { $0.id == uid }?.name }
            .sorted()
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(round, systemImage: "hand.thumbsup.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(color)
                Spacer()
                Text("\(voters.count) vote\(voters.count == 1 ? "" : "s")")
                    .font(.subheadline.bold())
                    .foregroundStyle(color)
            }
            if !names.isEmpty {
                Text(names.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - Loading

    private func load() async {
        if let preloaded = preloadedBook {
            book = preloaded
            return
        }
        guard let monthId, let bookId else { return }
        isLoading = true
        do {
            let snap = try await db.bookRef(monthId: monthId, bookId: bookId).getDocument()
            book = try snap.data(as: Book.self)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
