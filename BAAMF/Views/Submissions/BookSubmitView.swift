import SwiftUI
import Combine

/// Final confirmation step before submitting a book.
/// Shows book metadata and lets the member optionally write a pitch.
struct BookSubmitView: View {

    let book: GoogleBooksItem
    let month: ClubMonth
    /// When non-nil, the submit action replaces the book at this document ID instead
    /// of creating a new submission.
    var existingBookId: String? = nil
    let onSubmitted: () -> Void

    @StateObject private var viewModel = SubmissionsViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var pitch = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Book preview card
                HStack(alignment: .top, spacing: 16) {
                    CoverImage(url: book.coverUrl, size: 80)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(.title3.bold())
                            .lineLimit(3)
                        Text(book.author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            if let pages = book.pageCount {
                                Label("\(pages) pages", systemImage: "book")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let rating = book.rating {
                                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Divider()

                // Google Books description
                if !book.description.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)
                        Text(book.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Pitch override
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Pitch (Optional)")
                        .font(.footnote.bold())
                        .foregroundStyle(.secondary)
                    Text("Replace the description with your own pitch to the club.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    TextEditor(text: $pitch)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .font(.body)
                }

                // Error
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                // Submit / Swap button
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if viewModel.isSubmitting {
                            ProgressView().tint(.white)
                        }
                        Text(existingBookId != nil ? "Swap Book" : "Submit Book")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(viewModel.isSubmitting)
            }
            .padding()
        }
        .navigationTitle(existingBookId != nil ? "Swap Book" : "Submit Book")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.submittedSuccessfully) { _, success in
            if success {
                onSubmitted()
                dismiss()
            }
        }
    }

    private func submit() async {
        guard let userId = authViewModel.currentUserId,
              let monthId = month.id else { return }

        if let existingId = existingBookId {
            await viewModel.swapBook(existingBookId: existingId,
                                     monthId: monthId,
                                     newBook: book,
                                     pitch: pitch)
        } else {
            await viewModel.submitBook(book, pitch: pitch, monthId: monthId, submitterId: userId)
        }
    }
}
