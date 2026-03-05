import SwiftUI

/// Scoring view — shown during the `.scoring` phase.
/// Each member enters a 1–7 score for the month's selected book.
/// All scores are visible to everyone in real time (not anonymous).
struct ScoringView: View {

    let month: ClubMonth
    let allMembers: [Member]

    @StateObject private var viewModel = ScoringViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel

    private var currentUserId: String { authViewModel.currentUserId ?? "" }

    // Local score selection state
    @State private var selectedScore: Double = 4.0
    @State private var hasInitialized = false

    // Admin: enter score on behalf of another member
    @State private var adminTargetMember: Member?

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading scores…")
            } else {
                mainContent
            }
        }
        .navigationTitle("Score This Month's Book")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let monthId = month.id {
                viewModel.start(monthId: monthId)
            }
        }
        .onDisappear { viewModel.stop() }
        .onChange(of: viewModel.scores) { _, _ in
            // Seed the picker with the user's existing score on first load
            if !hasInitialized, let existing = viewModel.myScore(userId: currentUserId) {
                selectedScore = existing
                hasInitialized = true
            } else if !hasInitialized {
                hasInitialized = true   // no existing score — keep default 4.0
            }
        }
        .sheet(item: $adminTargetMember) { member in
            AdminScoreSheet(
                memberName: member.name,
                existingScore: viewModel.myScore(userId: member.id ?? ""),
                onSubmit: { score in
                    Task {
                        guard let monthId = month.id else { return }
                        await viewModel.submitScore(score,
                                                    monthId: monthId,
                                                    bookId: month.selectedBookId ?? "",
                                                    userId: member.id ?? "")
                    }
                }
            )
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                bookCard
                scoreEntryCard
                scoresListCard
                if authViewModel.isAdmin {
                    adminScoringCard
                }
            }
            .padding()
        }
    }

    // MARK: - Book card

    private var bookCard: some View {
        HStack(alignment: .top, spacing: 16) {
            if let coverUrl = month.selectedBookCoverUrl {
                CoverImage(url: coverUrl, size: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 64, height: 90)
                    .overlay {
                        Image(systemName: "book.fill")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("This Month's Book")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                if let title = month.selectedBookTitle {
                    Text(title)
                        .font(.headline)
                        .lineLimit(3)
                }
                if let author = month.selectedBookAuthor {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Score entry card

    private var scoreEntryCard: some View {
        VStack(spacing: 16) {

            // Big score display
            Text(selectedScore.scoreDisplay)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.25), value: selectedScore)

            // Quick-select buttons 1–7
            HStack(spacing: 8) {
                ForEach(1...7, id: \.self) { whole in
                    let value = Double(whole)
                    Button {
                        selectedScore = value
                    } label: {
                        Text("\(whole)")
                            .font(.body.bold())
                            .frame(width: 40, height: 40)
                            .background(
                                selectedScore == value
                                    ? Color.accentColor
                                    : (Int(selectedScore) == whole
                                        ? Color.accentColor.opacity(0.15)
                                        : Color(.systemGray5))
                            )
                            .foregroundStyle(
                                selectedScore == value ? Color.white : Color.primary
                            )
                            .clipShape(Circle())
                    }
                }
            }

            // Fine-tune row (half-point adjustment)
            HStack {
                Button {
                    selectedScore = max(K.Scoring.minScore, selectedScore - K.Scoring.step)
                } label: {
                    Label("−½", systemImage: "")
                        .labelStyle(.titleOnly)
                        .font(.footnote.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                .disabled(selectedScore <= K.Scoring.minScore)

                Spacer()

                Text("Half-points allowed but discouraged")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                Spacer()

                Button {
                    selectedScore = min(K.Scoring.maxScore, selectedScore + K.Scoring.step)
                } label: {
                    Label("+½", systemImage: "")
                        .labelStyle(.titleOnly)
                        .font(.footnote.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                .disabled(selectedScore >= K.Scoring.maxScore)
            }

            Divider()

            // Submit / Update button
            Button {
                Task { await submitScore() }
            } label: {
                HStack {
                    if viewModel.isActing {
                        ProgressView().tint(.white)
                    }
                    let alreadyScored = viewModel.hasScored(userId: currentUserId)
                    Text(alreadyScored ? "Update Score" : "Submit Score")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.isActing)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Member scores list

    private var scoresListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("All Scores")
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().padding(.horizontal)

            ForEach(allMembers) { member in
                let memberId = member.id ?? ""
                let score = viewModel.myScore(userId: memberId)

                HStack {
                    Text(member.name)
                        .font(.body)

                    Spacer()

                    if let score {
                        Text(score.scoreDisplay)
                            .font(.body.bold())
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text("—")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                if member.id != allMembers.last?.id {
                    Divider().padding(.horizontal)
                }
            }

            if let avg = viewModel.groupAverage {
                Divider()
                HStack {
                    Text("Group Average")
                        .font(.subheadline.bold())
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.footnote)
                        Text(avg.scoreDisplay)
                            .font(.subheadline.bold())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Admin: enter scores on behalf

    private var adminScoringCard: some View {
        let unscored = allMembers.filter { !viewModel.hasScored(userId: $0.id ?? "") }

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Enter Scores on Behalf")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(unscored.count) remaining")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if unscored.isEmpty {
                Divider().padding(.horizontal)
                Text("All members have scored.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
            } else {
                Divider().padding(.horizontal)
                ForEach(unscored) { member in
                    HStack {
                        Text(member.name)
                            .font(.body)
                        Spacer()
                        Button("Enter Score") {
                            adminTargetMember = member
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)

                    if member.id != unscored.last?.id {
                        Divider().padding(.horizontal)
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func submitScore() async {
        guard let monthId = month.id else { return }
        let bookId = month.selectedBookId ?? ""
        await viewModel.submitScore(selectedScore,
                                    monthId: monthId,
                                    bookId: bookId,
                                    userId: currentUserId)
    }
}

// MARK: - Admin Score Sheet

/// A self-contained sheet for an admin to enter a score on behalf of a member.
private struct AdminScoreSheet: View {

    let memberName: String
    let existingScore: Double?
    let onSubmit: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedScore: Double

    init(memberName: String, existingScore: Double?, onSubmit: @escaping (Double) -> Void) {
        self.memberName = memberName
        self.existingScore = existingScore
        self.onSubmit = onSubmit
        _selectedScore = State(initialValue: existingScore ?? 4.0)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Score for \(memberName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                Text(selectedScore.scoreDisplay)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.25), value: selectedScore)

                HStack(spacing: 8) {
                    ForEach(1...7, id: \.self) { whole in
                        let value = Double(whole)
                        Button {
                            selectedScore = value
                        } label: {
                            Text("\(whole)")
                                .font(.body.bold())
                                .frame(width: 40, height: 40)
                                .background(
                                    selectedScore == value
                                        ? Color.accentColor
                                        : Color(.systemGray5)
                                )
                                .foregroundStyle(selectedScore == value ? .white : .primary)
                                .clipShape(Circle())
                        }
                    }
                }

                HStack {
                    Button {
                        selectedScore = max(K.Scoring.minScore, selectedScore - K.Scoring.step)
                    } label: {
                        Text("−½")
                            .font(.footnote.bold())
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    .disabled(selectedScore <= K.Scoring.minScore)

                    Spacer()

                    Button {
                        selectedScore = min(K.Scoring.maxScore, selectedScore + K.Scoring.step)
                    } label: {
                        Text("+½")
                            .font(.footnote.bold())
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    .disabled(selectedScore >= K.Scoring.maxScore)
                }

                Button {
                    onSubmit(selectedScore)
                    dismiss()
                } label: {
                    Text(existingScore != nil ? "Update Score" : "Submit Score")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Spacer()
            }
            .padding(.horizontal, 32)
            .navigationTitle("Enter Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
