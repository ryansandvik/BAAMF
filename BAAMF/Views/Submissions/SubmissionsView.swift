import SwiftUI
import Combine

/// Shows all submitted books for the current month.
/// Members can submit their own book from here (if eligible).
struct SubmissionsView: View {

    let month: ClubMonth
    let allMembers: [Member]

    @StateObject private var viewModel = SubmissionsViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var editingBook: Book?

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading submissions…")
            } else {
                mainContent
            }
        }
        .navigationTitle("Submissions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { submitToolbarButton }
        .task {
            if let monthId = month.id {
                viewModel.start(monthId: monthId)
            }
        }
        .onDisappear { viewModel.stop() }
        .sheet(item: $editingBook) { book in
            BookEditView(
                book: book,
                month: month,
                submitterName: memberName(for: book.submitterId),
                onDeleted: {}
            )
            .environmentObject(authViewModel)
        }
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

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.eligibleBooks.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    modeHeader
                    ForEach(viewModel.eligibleBooks) { book in
                        bookRow(for: book)
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Mode header

    @ViewBuilder
    private var modeHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: modeIcon)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(month.submissionMode.displayName)
                    .font(.footnote.bold())
                if month.submissionMode == .theme, let theme = month.theme {
                    Text("Theme: \(theme)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if month.submissionMode == .pick4 {
                    Text("\(viewModel.eligibleBooks.count) of 4 books submitted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var modeIcon: String {
        switch month.submissionMode {
        case .open:   return "person.2"
        case .theme:  return "paintbrush"
        case .pick4:  return "list.number"
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "No Submissions Yet",
            systemImage: "tray",
            description: Text(
                canSubmit
                    ? "Be the first to submit a book!"
                    : "Waiting for members to submit books."
            )
        )
    }

    // MARK: - Submit toolbar button

    @ToolbarContentBuilder
    private var submitToolbarButton: some ToolbarContent {
        if canSubmit {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    BookSearchView(month: month, onSubmitted: {
                        // Real-time listener handles refresh automatically
                    })
                } label: {
                    Label("Submit", systemImage: "plus")
                }
            }
        }
    }

    // MARK: - Book row

    @ViewBuilder
    private func bookRow(for book: Book) -> some View {
        let isOwned = book.submitterId == authViewModel.currentUserId
        let canEdit = isOwned && month.status == .submissions

        if canEdit {
            Button { editingBook = book } label: {
                BookCard(
                    book: book,
                    submitterName: memberName(for: book.submitterId),
                    showSubmitter: month.submissionMode == .pick4,
                    isOwned: true
                )
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
        } else {
            BookCard(
                book: book,
                submitterName: memberName(for: book.submitterId),
                showSubmitter: month.submissionMode == .pick4
            )
            .padding(.horizontal)
        }
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        guard let userId = authViewModel.currentUserId else { return false }
        let isHost = month.isHost(userId: userId)
        return viewModel.canSubmit(userId: userId, month: month, isHost: isHost || authViewModel.isAdmin)
    }

    private func memberName(for userId: String) -> String {
        allMembers.first { $0.id == userId }?.name ?? "Unknown"
    }
}
