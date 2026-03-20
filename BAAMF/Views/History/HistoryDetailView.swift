import SwiftUI
import FirebaseFirestore
import Combine

/// Full detail view for a completed month: book info, event details, and all member scores.
struct HistoryDetailView: View {

    let month: ClubMonth
    let allMembers: [Member]
    var isAdmin: Bool = false
    var currentUserId: String = ""

    @State private var scores: [BookScore] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var listener: ListenerRegistration?
    @State private var showEditMonth = false

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
                        showEditMonth = true
                    } label: {
                        Label("Edit Month", systemImage: "square.and.pencil")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditMonth) {
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
                if let monthId = month.id {
                    AttendanceCard(
                        monthId: monthId,
                        allMembers: allMembers,
                        currentUserId: currentUserId,
                        isAdmin: isAdmin
                    )
                }
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

                if let submitterId = month.selectedBookSubmitterId,
                   let submitter = allMembers.first(where: { $0.id == submitterId }) {
                    Text("Submitted by \(submitter.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .cardStyle()
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
        .cardStyle()
    }

    // MARK: - Scores card

    private var scoresCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Scores")
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().padding(.horizontal)

            ForEach(scoredMembers) { row in
                HStack(spacing: 10) {
                    MemberAvatar(name: row.name, photoURL: row.avatarUrl, size: 32)
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
        .cardStyle()
    }

    // MARK: - Helpers

    private struct MemberScoreRow: Identifiable {
        let id: String
        let name: String
        let avatarUrl: String?
        let score: Double?
    }

    private var scoredMembers: [MemberScoreRow] {
        allMembers.map { member in
            let memberId = member.id ?? ""
            let score = scores.first { $0.scorerId == memberId }?.score
            return MemberScoreRow(id: memberId, name: member.name, avatarUrl: member.photoURL, score: score)
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

// MARK: - Attendance card

private struct AttendanceCard: View {

    let monthId: String
    let allMembers: [Member]
    let currentUserId: String
    let isAdmin: Bool

    @StateObject private var vm: AttendanceViewModel
    @State private var showRoster = false

    init(monthId: String, allMembers: [Member], currentUserId: String, isAdmin: Bool) {
        self.monthId = monthId
        self.allMembers = allMembers
        self.currentUserId = currentUserId
        self.isAdmin = isAdmin
        _vm = StateObject(wrappedValue: AttendanceViewModel(monthId: monthId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Attendance")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                if vm.attendingCount > 0 || vm.notAttendingCount > 0 {
                    Button { showRoster = true } label: {
                        Text("\(vm.attendingCount) attended")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button { showRoster = true } label: {
                    Image(systemName: "person.2")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
            .padding(.horizontal)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().padding(.horizontal)

            // Member rows
            ForEach(sortedRows, id: \.id) { row in
                HStack(spacing: 10) {
                    MemberAvatar(name: row.name, photoURL: row.avatarUrl, size: 32)
                    Text(row.name)
                        .font(.body)
                    Spacer()
                    if isAdmin {
                        adminToggle(for: row)
                    } else {
                        attendanceLabel(for: row.status)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                if row.id != sortedRows.last?.id {
                    Divider().padding(.horizontal)
                }
            }
        }
        .cardStyle()
        .task { vm.start() }
        .onDisappear { vm.stop() }
        .sheet(isPresented: $showRoster) {
            AttendanceRosterSheet(allMembers: allMembers, records: vm.records)
        }
    }

    // MARK: - Admin per-row toggle

    @ViewBuilder
    private func adminToggle(for row: MemberAttendanceRow) -> some View {
        HStack(spacing: 6) {
            attendanceButton(label: "Attended",  value: true,  current: row.status, memberId: row.id)
            attendanceButton(label: "Didn't",    value: false, current: row.status, memberId: row.id)
        }
    }

    @ViewBuilder
    private func attendanceButton(label: String, value: Bool, current: Bool?, memberId: String) -> some View {
        let isSelected = current == value
        let color: Color = value ? .green : .red
        Button {
            Task {
                if isSelected {
                    // Tapping the active selection clears the record
                    await vm.clearAttendance(uid: memberId)
                } else {
                    await vm.setAttendance(attending: value, uid: memberId)
                }
            }
        } label: {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? color.opacity(0.12) : Color(.systemGray5))
                .foregroundStyle(isSelected ? color : Color.secondary)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? color.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Read-only label (non-admins)

    @ViewBuilder
    private func attendanceLabel(for status: Bool?) -> some View {
        switch status {
        case true:
            Label("Attended", systemImage: "checkmark.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(.green)
        case false:
            Label("Didn't attend", systemImage: "xmark.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(.red)
        case nil:
            Text("No response")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Row model

    private struct MemberAttendanceRow: Identifiable {
        let id: String
        let name: String
        let avatarUrl: String?
        let status: Bool?
    }

    private var sortedRows: [MemberAttendanceRow] {
        allMembers
            .map { member in
                let memberId = member.id ?? ""
                let status = vm.records.first { $0.id == memberId }?.attending
                return MemberAttendanceRow(id: memberId, name: member.name, avatarUrl: member.photoURL, status: status)
            }
            .sorted {
                return $0.name < $1.name
            }
    }
}
