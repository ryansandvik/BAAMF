import SwiftUI
import Combine

/// Searches Google Books and lets the user select a book to submit.
struct BookSearchView: View {

    let month: ClubMonth
    let onSubmitted: () -> Void
    /// When non-nil, selecting a book swaps the existing submission rather than creating a new one.
    var existingBookId: String? = nil

    @StateObject private var viewModel = BookSearchViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var didSubmit = false

    var body: some View {
        VStack(spacing: 0) {

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by title or author", text: $viewModel.query)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { viewModel.search() }

                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Results
            Group {
                if viewModel.isSearching {
                    Spacer()
                    ProgressView("Searching…")
                    Spacer()
                } else if let error = viewModel.errorMessage {
                    Spacer()
                    ContentUnavailableView("Search Failed",
                                          systemImage: "wifi.slash",
                                          description: Text(error))
                    Spacer()
                } else if viewModel.hasSearched && viewModel.results.isEmpty {
                    Spacer()
                    ContentUnavailableView("No Results",
                                          systemImage: "book.closed",
                                          description: Text("Try a different title or author."))
                    Spacer()
                } else if !viewModel.hasSearched {
                    Spacer()
                    ContentUnavailableView("Search for a Book",
                                          systemImage: "magnifyingglass",
                                          description: Text("Enter a title or author above and tap Search."))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.results) { item in
                                NavigationLink {
                                    BookSubmitView(
                                        book: item,
                                        month: month,
                                        existingBookId: existingBookId,
                                        onSubmitted: {
                                            onSubmitted()
                                            didSubmit = true
                                        }
                                    )
                                } label: {
                                    SearchResultRow(item: item)
                                        .padding(.horizontal)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .navigationTitle(existingBookId != nil ? "Swap Book" : "Search Books")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: didSubmit) { _, submitted in
            if submitted { dismiss() }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Search") { viewModel.search() }
                    .disabled(viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty
                              || viewModel.isSearching)
            }
        }
    }
}

// MARK: - Search result row

private struct SearchResultRow: View {
    let item: GoogleBooksItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImage(url: item.coverUrl, size: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(item.author)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let pages = item.pageCount {
                        Text("\(pages) pages")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let rating = item.rating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
