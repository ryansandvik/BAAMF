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
