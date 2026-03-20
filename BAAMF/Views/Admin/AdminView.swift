import SwiftUI
import Combine
import PhotosUI

// Typed navigation destination for Profile's NavigationStack.
enum ProfileNavDestination: Hashable {
    case schedule
    case adminSettings
}

/// Profile tab — visible to all members.
struct ProfileView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var showLogHistoricalBook = false
    @State private var showDeleteAccount = false
    @State private var generatedCode: String?
    @State private var showCodeAlert = false
    @State private var codeGenerationError: String?
    @State private var isGeneratingCode = false

    var body: some View {
        List {

            // MARK: User info + avatar
            if let member = authViewModel.currentMember, let uid = member.id {
                Section {
                    AvatarHeaderRow(member: member, uid: uid)
                }
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

                    NavigationLink(value: ProfileNavDestination.adminSettings) {
                        Label("Phase Deadlines", systemImage: "clock.badge.checkmark")
                    }

                    Button {
                        showLogHistoricalBook = true
                    } label: {
                        Label("Log Historical Book", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    }

                    Button {
                        Task {
                            isGeneratingCode = true
                            do {
                                generatedCode = try await authViewModel.generateInviteCode()
                                showCodeAlert = true
                            } catch {
                                codeGenerationError = error.localizedDescription
                                showCodeAlert = true
                            }
                            isGeneratingCode = false
                        }
                    } label: {
                        HStack {
                            Label("Generate Invite Code", systemImage: "person.badge.plus")
                            if isGeneratingCode {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isGeneratingCode)
                }
            }

            // MARK: Sign out / account
            Section {
                Button(role: .destructive) {
                    authViewModel.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }

                Button(role: .destructive) {
                    showDeleteAccount = true
                } label: {
                    Label("Delete Account", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Profile")
        .navigationDestination(for: ProfileNavDestination.self) { destination in
            switch destination {
            case .schedule:
                ScheduleView()
            case .adminSettings:
                AdminSettingsView()
            }
        }
        .sheet(isPresented: $showLogHistoricalBook) {
            LogHistoricalBookView()
        }
        .sheet(isPresented: $showDeleteAccount) {
            DeleteAccountView()
                .environmentObject(authViewModel)
        }
        .alert(generatedCode != nil ? "Invite Code Ready" : "Error", isPresented: $showCodeAlert) {
            if let code = generatedCode {
                Button("Copy Code") {
                    UIPasteboard.general.string = code
                }
                Button("Done", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            if let code = generatedCode {
                Text("Share this code with the new member:\n\n\(code)\n\nExpires in 24 hours.")
            } else if let error = codeGenerationError {
                Text(error)
            }
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
                     : "You haven't scored any books for \(String(viewModel.selectedYear)).")
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

// MARK: - Avatar header row

private struct AvatarHeaderRow: View {

    let member: Member
    let uid: String

    @StateObject private var vm: ProfilePictureViewModel

    init(member: Member, uid: String) {
        self.member = member
        self.uid = uid
        _vm = StateObject(wrappedValue: ProfilePictureViewModel(uid: uid))
    }

    var body: some View {
        HStack(spacing: 14) {
            PhotosPicker(
                selection: $vm.selectedItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                ZStack(alignment: .bottomTrailing) {
                    MemberAvatar(name: member.name, photoURL: member.photoURL, size: 60)

                    if vm.isUploading {
                        Circle()
                            .fill(.black.opacity(0.4))
                            .frame(width: 60, height: 60)
                            .overlay(ProgressView().tint(.white))
                    } else {
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            )
                            .shadow(radius: 1)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(vm.isUploading)

            VStack(alignment: .leading, spacing: 3) {
                Text(member.name)
                    .font(.headline)
                Text(member.email)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .alert("Upload Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }
}

#Preview {
    NavigationStack { ProfileView() }
        .environmentObject(AuthViewModel())
}
