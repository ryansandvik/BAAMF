import SwiftUI

/// Admin sheet for editing member scores on a completed or historical month.
/// Loads existing scores, lets the admin add/update/remove any score, and
/// batch-saves changes + recalculates `groupAvgScore`.
struct EditCompletedMonthView: View {

    @StateObject private var viewModel: EditCompletedMonthViewModel
    @Environment(\.dismiss) private var dismiss

    init(month: ClubMonth) {
        _viewModel = StateObject(wrappedValue: EditCompletedMonthViewModel(month: month))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading scores…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    form
                }
            }
            .navigationTitle("Edit Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
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
        }
        .task { viewModel.start() }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            // Month context header
            Section {

                HStack(spacing: 12) {
                    if let coverUrl = viewModel.month.selectedBookCoverUrl {
                        CoverImage(url: coverUrl, size: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.month.month.monthName + " " + String(viewModel.month.year))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let title = viewModel.month.selectedBookTitle {
                            Text(title)
                                .font(.body.bold())
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Submitter
            Section {
                Picker("Submitter", selection: $viewModel.selectedSubmitterId) {
                    Text("Unknown").tag("")
                    ForEach(viewModel.allMembers) { member in
                        Text(member.name).tag(member.id ?? "")
                    }
                }
            } header: {
                Text("Submitter")
            } footer: {
                Text("The member who originally pitched this book.")
            }

            // Score rows
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
                Button("Save") { viewModel.save() }
                    .disabled(viewModel.participating.isEmpty)
            }
        }
    }
}
