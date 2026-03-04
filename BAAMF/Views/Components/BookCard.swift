import SwiftUI

/// Reusable card showing a submitted book's cover, title, author, submitter, and description.
struct BookCard: View {

    let book: Book
    let submitterName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Header row: cover + title/author/submitter
            HStack(alignment: .top, spacing: 12) {
                CoverImage(url: book.coverUrl, size: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Submitted by \(submitterName)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Pitch or description
            let displayText = book.displayDescription
            if !displayText.isEmpty {
                Text(displayText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
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
