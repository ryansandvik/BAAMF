import SwiftUI

/// Sheet for editing, swapping, or deleting a user's own book submission.
/// Only reachable while the month is in `.submissions` status.
struct BookEditView: View {

    let book: Book
    let month: ClubMonth
    let submitterName: String
    /// Called after the book is deleted so SubmissionsView can react if needed.
    let onDeleted: () -> Void

    @StateObject private var viewModel = SubmissionsViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var pitch: String
    @State private var isSavingPitch = false
    @State private var showDeleteConfirmation = false
    /// Set to true when a swap completes so BookEditView dismisses itself.
    @State private var swapCompleted = false

    init(book: Book, month: ClubMonth, submitterName: String, onDeleted: @escaping () -> Void) {
        self.book = book
        self.month = month
        self.submitterName = submitterName
        self.onDeleted = onDeleted
        _pitch = State(initialValue: book.pitchOverride ?? "")
    }

    private var pitchChanged: Bool {
        pitch.trimmingCharacters(in: .whitespacesAndNewlines) != (book.pitchOverride ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Current book preview
                    BookCard(book: book, submitterName: submitterName)
                        .padding(.horizontal)

                    Divider()

                    // Pitch editor
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Pitch (Optional)")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)
                        Text("Replace the book description with your own pitch to the club.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        TextEditor(text: $pitch)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .font(.body)
                    }
                    .padding(.horizontal)

                    // Error
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .padding(.horizontal)
                    }

                    Divider()

                    // Action buttons
                    VStack(spacing: 12) {

                        // Swap book — navigates to BookSearchView in swap mode
                        NavigationLink {
                            BookSearchView(
                                month: month,
                                onSubmitted: { swapCompleted = true },
                                existingBookId: book.id
                            )
                        } label: {
                            Label("Swap Book", systemImage: "arrow.2.squarepath")
                                .font(.body.bold())
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray5))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        // Delete
                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Submission", systemImage: "trash")
                                .font(.body.bold())
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .foregroundStyle(.red)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Edit Submission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if pitchChanged {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await savePitch() }
                        }
                        .fontWeight(.semibold)
                        .disabled(isSavingPitch)
                    }
                }
            }
            // Dismiss the sheet after a successful swap
            .onChange(of: swapCompleted) { _, done in
                if done { dismiss() }
            }
            // Dismiss the sheet after a successful pitch save
            .onChange(of: viewModel.errorMessage) { _, error in
                if error == nil && isSavingPitch { dismiss() }
            }
            .confirmationDialog(
                "Delete Submission",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task { await deleteBook() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove your book from this month's submissions.")
            }
        }
    }

    // MARK: - Actions

    private func savePitch() async {
        guard let bookId = book.id, let monthId = month.id else { return }
        isSavingPitch = true
        await viewModel.updateBookPitch(bookId: bookId, monthId: monthId, pitch: pitch)
        isSavingPitch = false
        if viewModel.errorMessage == nil { dismiss() }
    }

    private func deleteBook() async {
        guard let bookId = book.id, let monthId = month.id else { return }
        await viewModel.deleteBook(bookId: bookId, monthId: monthId)
        if viewModel.errorMessage == nil {
            onDeleted()
            dismiss()
        }
    }
}
