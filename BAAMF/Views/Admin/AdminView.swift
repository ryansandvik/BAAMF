import SwiftUI
import Combine

// Typed navigation destination for Profile's NavigationStack.
enum ProfileNavDestination: Hashable {
    case schedule
}

/// Profile tab — visible to all members.
struct ProfileView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var showLogHistoricalBook = false

    var body: some View {
        List {

            // MARK: User info
            Section {
                Label(
                    authViewModel.currentMember?.name ?? "Member",
                    systemImage: "person.circle.fill"
                )
                .foregroundStyle(.primary)
            }

            // MARK: My Favourites
            if let uid = authViewModel.currentMember?.id {
                FavoritesBooksSection(userId: uid)
            }

            // MARK: Notifications
            if let uid = authViewModel.currentMember?.id {
                NotificationsSection(userId: uid)
            }

            // MARK: Admin controls (admins only)
            if authViewModel.isAdmin {
                Section("Admin") {
                    NavigationLink(value: ProfileNavDestination.schedule) {
                        Label("Manage Schedule", systemImage: "calendar.badge.plus")
                    }

                    Button {
                        showLogHistoricalBook = true
                    } label: {
                        Label("Log Historical Book", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    }
                }
            }

            // MARK: Sign out
            Section {
                Button(role: .destructive) {
                    authViewModel.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Profile")
        .navigationDestination(for: ProfileNavDestination.self) { destination in
            switch destination {
            case .schedule:
                ScheduleView()
            }
        }
        .sheet(isPresented: $showLogHistoricalBook) {
            LogHistoricalBookView()
        }
    }
}

// MARK: - Favourites section

private struct FavoritesBooksSection: View {

    let userId: String

    @StateObject private var viewModel: FavoriteBooksViewModel

    init(userId: String) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: FavoriteBooksViewModel(userId: userId))
    }

    var body: some View {
        Section {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if viewModel.favorites.isEmpty {
                Text(viewModel.availableYears.isEmpty
                     ? "No completed months yet."
                     : "You haven't scored any books for \(viewModel.selectedYear).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.favorites) { entry in
                    FavoriteBookRow(entry: entry)
                }
            }
        } header: {
            // Section header with inline year picker
            HStack {
                Text("My Favourites")
                Spacer()
                if viewModel.availableYears.count > 1 {
                    Menu {
                        ForEach(viewModel.availableYears, id: \.self) { year in
                            Button(String(year)) {
                                viewModel.selectedYear = year
                                viewModel.yearChanged()
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(String(viewModel.selectedYear))
                            Image(systemName: "chevron.up.chevron.down")
                                .imageScale(.small)
                        }
                        .font(.footnote.bold())
                        .foregroundStyle(Color.accentColor)
                        .textCase(nil)
                    }
                }
            }
        }
        .task { viewModel.start() }
    }
}

// MARK: - Favourite book row

private struct FavoriteBookRow: View {

    let entry: FavoriteEntry

    var body: some View {
        HStack(spacing: 12) {
            if let coverUrl = entry.month.selectedBookCoverUrl {
                CoverImage(url: coverUrl, size: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 30, height: 44)
                    .overlay {
                        Image(systemName: "book.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                if let title = entry.month.selectedBookTitle {
                    Text(title)
                        .font(.body)
                        .lineLimit(2)
                }
                if let author = entry.month.selectedBookAuthor {
                    Text(author)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(entry.month.month.monthName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Personal score badge
            VStack(spacing: 2) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.footnote)
                Text(entry.personalScore.scoreDisplay)
                    .font(.footnote.bold())
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Notifications section

private struct NotificationsSection: View {

    let userId: String

    @StateObject private var viewModel: NotificationPrefsViewModel

    init(userId: String) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: NotificationPrefsViewModel(userId: userId))
    }

    var body: some View {
        Section("Notifications") {
            Toggle(isOn: Binding(
                get: { viewModel.nominations },
                set: { viewModel.nominations = $0; viewModel.saveDebounced() }
            )) {
                Label("Nominations & Voting", systemImage: "hand.raised")
            }

            Toggle(isOn: Binding(
                get: { viewModel.reading },
                set: { viewModel.reading = $0; viewModel.saveDebounced() }
            )) {
                Label("Book Chosen", systemImage: "book.fill")
            }

            Toggle(isOn: Binding(
                get: { viewModel.scoring },
                set: { viewModel.scoring = $0; viewModel.saveDebounced() }
            )) {
                Label("Time to Score", systemImage: "star")
            }

            Toggle(isOn: Binding(
                get: { viewModel.swaps },
                set: { viewModel.swaps = $0; viewModel.saveDebounced() }
            )) {
                Label("Hosting Swap Requests", systemImage: "arrow.left.arrow.right")
            }
        }
        .task { viewModel.load() }
    }
}

#Preview {
    NavigationStack { ProfileView() }
        .environmentObject(AuthViewModel())
}
