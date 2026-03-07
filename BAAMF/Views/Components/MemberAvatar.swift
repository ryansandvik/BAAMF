import SwiftUI

/// Circular member avatar.
/// Shows the member's profile photo if available; falls back to their initials on a tinted background.
struct MemberAvatar: View {

    let name: String
    let photoURL: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let urlString = photoURL, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    // MARK: - Initials fallback

    private var initialsView: some View {
        Circle()
            .fill(avatarColor)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        switch parts.count {
        case 0:  return "?"
        case 1:  return String(parts[0].prefix(1)).uppercased()
        default: return (String(parts[0].prefix(1)) + String(parts[parts.count - 1].prefix(1))).uppercased()
        }
    }

    /// Deterministic color based on name — same name always gets the same color.
    private var avatarColor: Color {
        let palette: [Color] = [
            .blue, .purple, .pink, .orange, .green, .teal, .indigo, .cyan
        ]
        let hash = abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        return palette[hash % palette.count]
    }
}

#Preview {
    HStack(spacing: 16) {
        MemberAvatar(name: "Ryan Sandvik",  photoURL: nil, size: 64)
        MemberAvatar(name: "Jane Doe",      photoURL: nil, size: 64)
        MemberAvatar(name: "Alice",         photoURL: nil, size: 40)
        MemberAvatar(name: "Bob Smith",     photoURL: nil, size: 32)
    }
    .padding()
}
