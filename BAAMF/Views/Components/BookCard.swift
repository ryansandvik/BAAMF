import SwiftUI

/// Reusable card showing a submitted book's cover, title, author, and description.
/// `showSubmitter` should only be true for Pick-4 mode — Open/Theme submissions are anonymous.
struct BookCard: View {

    let book: Book
    let submitterName: String
    var showSubmitter: Bool = false
    /// When true, a pencil indicator is shown so the user knows they can tap to edit.
    var isOwned: Bool = false

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Header row: cover + title/author/submitter + owned indicator
            HStack(alignment: .top, spacing: 12) {
                CoverImage(url: book.coverUrl, size: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if showSubmitter {
                        Text("Submitted by \(submitterName)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if isOwned {
                        Label("Your submission", systemImage: "pencil")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                }

                if isOwned {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Pitch or description
            let displayText = book.displayDescription
            if !displayText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 4)
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)

                    if displayText.count > 150 {
                        Button(isExpanded ? "Show less" : "Read more") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                    }
                }
            }

            // Metadata chips
            HStack(spacing: 8) {
                if let pages = book.pageCount {
                    MetaChip(icon: "book", text: "\(pages) pages")
                }
                if let rating = book.googleRating {
                    MetaChip(icon: "star", text: String(format: "%.1f", rating))
                }
                if book.pitchOverride != nil && !book.pitchOverride!.isEmpty {
                    MetaChip(icon: "quote.bubble", text: "Pitched")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Cover Image

struct CoverImage: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let urlString = url, let imageURL = URL(string: urlString) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure, .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(.systemGray5))
            .overlay(
                Image(systemName: "book.closed")
                    .foregroundStyle(.secondary)
            )
    }
}

// MARK: - Meta chip

private struct MetaChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
    }
}
