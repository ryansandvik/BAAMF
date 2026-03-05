import SwiftUI
import FirebaseFirestore

/// Full detail view for a completed month: book info, event details, and all member scores.
struct HistoryDetailView: View {

    let month: ClubMonth
    let allMembers: [Member]
    var isAdmin: Bool = false

    @State private var scores: [BookScore] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var listener: ListenerRegistration?
    @State private var showEditScores = false

    private let db = FirestoreService.shared

    private var groupAverage: Double? {
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0) { $0 + $1.score } / Double(scores.count)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
            } else {
                content
            }
        }
        .navigationTitle(month.month.monthName + " " + String(month.year))
        .navigationBarTitleDisplayMode(.inline)
        .task { startListening() }
        .onDisappear { listener?.remove() }
        .toolbar {
            if isAdmin {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showEditScores = true
                    } label: {
                        Label("Edit Scores", systemImage: "square.and.pencil")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditScores) {
            EditCompletedMonthView(month: month)
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Main content

    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                bookCard
                if hasEventDetails { eventCard }
                scoresCard
            }
            .padding()
        }
    }

    // MARK: - Book card

    private var bookCard: some View {
        HStack(alignment: .top, spacing: 16) {
            if let coverUrl = month.selectedBookCoverUrl {
                CoverImage(url: coverUrl, size: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 70, height: 100)
                    .overlay {
                        Image(systemName: "book.fill")
                            .foregroundStyle(.secondary)
                            .font(.title)
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                if let title = month.selectedBookTitle {
                    Text(title)
                        .font(.title3.bold())
                        .lineLimit(4)
                }
                if let author = month.selectedBookAuthor {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let avg = groupAverage {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text(avg.scoreDisplay)
                            .font(.body.bold())
                        Text("group average")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }

                if month.isHistorical == true {
                    Label("Historical Entry", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Event card

    private var hasEventDetails: Bool {
        month.eventDate != nil
            || !(month.eventLocation ?? "").isEmpty
            || !(month.eventNotes ?? "").isEmpty
    }

    private var eventCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Event")
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            if let date = month.eventDate {
                Label(date.formatted(date: .long, time: .shortened), systemImage: "calendar")
                    .font(.footnote)
            }
            if let location = month.eventLocation, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.footnote)
            }
            if let notes = month.eventNotes, !notes.isEmpty {
                Label(notes, systemImage: "note.text")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Scores card

    private var scoresCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Scores")
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().padding(.horizontal)

            ForEach(scoredMembers) { row in
                HStack {
                    Text(row.name)
                        .font(.body)
                    Spacer()
                    if let score = row.score {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                            Text(score.scoreDisplay)
                                .font(.body.bold())
                        }
                    } else {
                        Text("—")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                if row.id != scoredMembers.last?.id {
                    Divider().padding(.horizontal)
                }
            }

            if let avg = groupAverage {
                Divider()
                HStack {
                    Text("Group Average")
                        .font(.subheadline.bold())
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
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

    // MARK: - Helpers

    private struct MemberScoreRow: Identifiable {
        let id: String
        let name: String
        let score: Double?
    }

    private var scoredMembers: [MemberScoreRow] {
        allMembers.map { member in
            let memberId = member.id ?? ""
            let score = scores.first { $0.scorerId == memberId }?.score
            return MemberScoreRow(id: memberId, name: member.name, score: score)
        }
        .sorted { ($0.score ?? -1) > ($1.score ?? -1) }
    }

    // MARK: - Data loading

    private func startListening() {
        guard let monthId = month.id else {
            isLoading = false
            return
        }
        listener = db.scoresRef(monthId: monthId)
            .addSnapshotListener { snapshot, error in
                Task { @MainActor in
                    isLoading = false
                    if let error {
                        errorMessage = error.localizedDescription
                        return
                    }
                    scores = snapshot?.documents
                        .compactMap { try? $0.data(as: BookScore.self) } ?? []
                }
            }
    }
}
