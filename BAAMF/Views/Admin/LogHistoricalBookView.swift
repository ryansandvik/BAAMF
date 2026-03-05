import SwiftUI

/// Admin sheet for logging a book club month that predates the app.
/// Presented modally from the Profile admin section.
struct LogHistoricalBookView: View {

    @StateObject private var viewModel = LogHistoricalBookViewModel()
    @Environment(\.dismiss) private var dismiss

    // Book picker sheet
    @State private var showBookPicker = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading members…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    form
                }
            }
            .navigationTitle("Log Historical Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showBookPicker) { bookPickerSheet }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onChange(of: viewModel.didSave) { _, saved in
                if saved { dismiss() }
            }
            .onChange(of: viewModel.selectedYear)  { _, _ in viewModel.checkMonthExists() }
            .onChange(of: viewModel.selectedMonth) { _, _ in viewModel.checkMonthExists() }
        }
        .task { viewModel.start() }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            monthSection
            hostSection
            bookSection
            scoresSection
        }
    }

    // MARK: - Month section

    private var monthSection: some View {
        Section("Month") {
            Picker("Year", selection: $viewModel.selectedYear) {
                ForEach(viewModel.availableYears, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }

            Picker("Month", selection: $viewModel.selectedMonth) {
                ForEach(1...12, id: \.self) { m in
                    Text(viewModel.monthNames[m - 1]).tag(m)
                }
            }

            if viewModel.monthAlreadyExists {
                Label("A record already exists for this month.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Host section

    private var hostSection: some View {
        Section("Host") {
            Picker("Host", selection: $viewModel.selectedHostId) {
                ForEach(viewModel.allMembers) { member in
                    Text(member.name).tag(member.id ?? "")
                }
            }
        }
    }

    // MARK: - Book section

    private var bookSection: some View {
        Section("Book") {
            if viewModel.bookTitle.isEmpty {
                Button {
                    showBookPicker = true
                } label: {
                    Label("Search for Book…", systemImage: "magnifyingglass")
                }
            } else {
                // Show selected book with option to change
                HStack(spacing: 12) {
                    if !viewModel.bookCoverUrl.isEmpty {
                        CoverImage(url: viewModel.bookCoverUrl, size: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 36, height: 50)
                            .overlay {
                                Image(systemName: "book.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.bookTitle)
                            .font(.body.bold())
                            .lineLimit(2)
                        Text(viewModel.bookAuthor)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button("Change") {
                        showBookPicker = true
                    }
                    .font(.footnote)
                    .foregroundStyle(.tint)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Scores section

    private var scoresSection: some View {
        Section {
            ForEach(viewModel.allMembers) { member in
                if let userId = member.id {
                    // Row 1 — participation toggle
                    Toggle(member.name, isOn: Binding(
                        get: { viewModel.participating.contains(userId) },
                        set: { _ in viewModel.toggleParticipation(for: userId) }
                    ))
                    .tint(.accentColor)

                    // Row 2 — score stepper (only when participating)
                    if viewModel.participating.contains(userId) {
                        HStack {
                            Label("Score", systemImage: "star.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .labelStyle(.titleAndIcon)
                                .imageScale(.small)
                            Spacer()
                            Stepper(
                                value: Binding(
                                    get: { viewModel.memberScores[userId] ?? 4.0 },
                                    set: { viewModel.memberScores[userId] = $0 }
                                ),
                                in: 1.0...7.0,
                                step: 0.5
                            ) {
                                Text((viewModel.memberScores[userId] ?? 4.0).scoreDisplay)
                                    .font(.body.bold())
                                    .monospacedDigit()
                                    .frame(minWidth: 28, alignment: .trailing)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.participating)
        } header: {
            Text("Member Scores")
        } footer: {
            Text("Toggle off members who didn't participate. Scores range 1–7.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if viewModel.isSaving {
                ProgressView()
            } else {
                Button("Save") {
                    viewModel.save()
                }
                .disabled(!viewModel.canSave)
            }
        }
    }

    // MARK: - Book picker sheet

    private var bookPickerSheet: some View {
        NavigationStack {
            HistoricalBookPickerView { item in
                viewModel.applyBook(item)
                showBookPicker = false
            }
        }
    }
}

// MARK: - Book picker (embedded search)

/// Lightweight book search that calls `onSelect` when the user taps a result.
/// Reuses `BookSearchViewModel` and the same search-bar pattern as `BookSearchView`.
private struct HistoricalBookPickerView: View {

    let onSelect: (GoogleBooksItem) -> Void

    @StateObject private var searchVM = BookSearchViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by title or author", text: $searchVM.query)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { searchVM.search() }

                if !searchVM.query.isEmpty {
                    Button { searchVM.clear() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            Group {
                if searchVM.isSearching {
                    Spacer()
                    ProgressView("Searching…")
                    Spacer()
                } else if let error = searchVM.errorMessage {
                    Spacer()
                    ContentUnavailableView("Search Failed",
                                          systemImage: "wifi.slash",
                                          description: Text(error))
                    Spacer()
                } else if searchVM.hasSearched && searchVM.results.isEmpty {
                    Spacer()
                    ContentUnavailableView("No Results",
                                          systemImage: "book.closed",
                                          description: Text("Try a different title or author."))
                    Spacer()
                } else if !searchVM.hasSearched {
                    Spacer()
                    ContentUnavailableView("Search for a Book",
                                          systemImage: "magnifyingglass",
                                          description: Text("Enter a title or author above and tap Search."))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(searchVM.results) { item in
                                Button {
                                    onSelect(item)
                                } label: {
                                    PickerResultRow(item: item)
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
        .navigationTitle("Select Book")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Search") { searchVM.search() }
                    .disabled(searchVM.query.trimmingCharacters(in: .whitespaces).isEmpty
                              || searchVM.isSearching)
            }
        }
    }
}

// MARK: - Picker result row

private struct PickerResultRow: View {
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

            Image(systemName: "checkmark.circle")
                .font(.title3)
                .foregroundStyle(.tint)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    LogHistoricalBookView()
}
