import SwiftUI

// MARK: - OnboardingView

/// Full-screen walkthrough shown once per user after their first login.
/// Persisted via @AppStorage("onboardingSeenV1") in RootView.
struct OnboardingView: View {

    var onFinish: () -> Void

    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        .welcome,
        .explore
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            // Navigation controls
            VStack(spacing: 16) {
                // Page dots
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: index == currentPage ? 20 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: currentPage)
                    }
                }

                // Primary button
                Button(action: advance) {
                    Text(currentPage == pages.count - 1 ? "Get Started" : "Next")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)

                // Skip — hidden on last page
                if currentPage < pages.count - 1 {
                    Button("Skip") {
                        onFinish()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    Color.clear.frame(height: 20)
                }
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
    }

    private func advance() {
        if currentPage < pages.count - 1 {
            withAnimation { currentPage += 1 }
        } else {
            onFinish()
        }
    }
}

// MARK: - Page content view

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero
                VStack(spacing: 12) {
                    Image(systemName: page.icon)
                        .font(.system(size: 52))
                        .foregroundStyle(page.iconColor)
                        .padding(.top, 80)

                    Text(page.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(page.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 28)

                // Info rows
                VStack(spacing: 12) {
                    ForEach(page.rows) { row in
                        OnboardingInfoRow(row: row)
                    }
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)

                Spacer(minLength: 140)
            }
        }
    }
}

// MARK: - Info row

private struct OnboardingInfoRow: View {
    let row: OnboardingRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.icon)
                .font(.title3)
                .foregroundStyle(row.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.subheadline.bold())
                Text(row.body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cardStyle(cornerRadius: 10)
    }
}

// MARK: - Data models

private struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let rows: [OnboardingRow]
}

private struct OnboardingRow: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let body: String
}

// MARK: - Page definitions

private extension OnboardingPage {

    static let welcome = OnboardingPage(
        icon: "books.vertical.fill",
        iconColor: .accentColor,
        title: "Welcome to BAAMF",
        subtitle: "Every month follows the same cycle. Here's the flow.",
        rows: [
            .init(icon: "tray.and.arrow.up.fill", color: .blue,
                  title: "Submit",
                  body: "Members nominate a book they want the club to read."),
            .init(icon: "bolt.shield.fill", color: .red,
                  title: "Veto",
                  body: "Members review nominations and can veto books before voting opens."),
            .init(icon: "checkmark.seal.fill", color: .green,
                  title: "Vote",
                  body: "Members cast their vote for the book they want to read. Most votes wins."),
            .init(icon: "star.fill", color: .orange,
                  title: "Score",
                  body: "After the meeting, members score the book and log their attendance.")
        ]
    )

    static let explore = OnboardingPage(
        icon: "square.grid.2x2.fill",
        iconColor: .accentColor,
        title: "Explore the App",
        subtitle: "A few more things worth knowing about.",
        rows: [
            .init(icon: "clock.fill", color: .secondary,
                  title: "History",
                  body: "Every past month lives in the History tab — scores, and attendance are logged here as well for future reference."),
            .init(icon: "calendar", color: .teal,
                  title: "Schedule",
                  body: "See who's hosting each month and check upcoming meeting dates. When the host enters event details, they're automatically added to your calendar."),
            .init(icon: "heart.fill", color: .pink,
                  title: "Your Favourites",
                  body: "See what books you liked most each year in the profile tab.")
        ]
    )
}
