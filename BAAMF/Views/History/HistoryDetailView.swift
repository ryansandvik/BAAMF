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
    @State private var showBookDetail = false

    // Votes in history
    @State private var votedBooks: [Book] = []
    @State private var isLoadingVotes = false

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
        .task {
            guard let monthId = month.id else { return }
            await fetchVotedBooks(monthId: monthId)
        }
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
                if !votedBooks.isEmpty || isLoadingVotes {
                    votesCard
                }
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
        let canShowDetail = month.selectedBookId != nil && month.id != nil

        return Button {
            if canShowDetail { showBookDetail = true }
        } label: {
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

                    if canShowDetail {
                        Label("Tap for details", systemImage: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                            .padding(.top, 2)
                    }
                }

                Spacer()

                if canShowDetail {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            .padding()
            .cardStyle()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showBookDetail) {
            BookDetailSheet(
                monthId: month.id,
                bookId: month.selectedBookId,
                allMembers: allMembers
            )
        }
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

    // MARK: - Votes card

    private var votesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Votes")
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().padding(.horizontal)

            if isLoadingVotes {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                // Show R2 books sorted by vote count descending
                let r2Books = votedBooks
                    .filter { $0.advancedToR2 }
                    .sorted { $0.votingR2Voters.count > $1.votingR2Voters.count }

                ForEach(r2Books) { book in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(book.title)
                                    .font(.subheadline.bold())
                                    .lineLimit(2)
                                Text(book.author)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 3) {
                                Image(systemName: "hand.thumbsup.fill")
                                    .font(.caption2)
                                    .foregroundStyle(book.id == month.selectedBookId ? .yellow : .secondary)
                                Text("\(book.votingR2Voters.count)")
                                    .font(.body.bold())
                                    .foregroundStyle(book.id == month.selectedBookId ? .primary : .secondary)
                            }
                        }

                        // Voter names
                        let voters = book.votingR2Voters.compactMap { uid in
                            allMembers.first { $0.id == uid }?.name
                        }.sorted()
                        if !voters.isEmpty {
                            Text(voters.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No votes")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)

                    if book.id != r2Books.last?.id {
                        Divider().padding(.horizontal)
                    }
                }

                if r2Books.isEmpty {
                    Text("No Round 2 data available")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }
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

    private func fetchVotedBooks(monthId: String) async {
        isLoadingVotes = true
        if let snap = try? await db.booksRef(monthId: monthId).getDocuments() {
            votedBooks = snap.documents.compactMap { try? $0.data(as: Book.self) }
        }
        isLoadingVotes = false
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
    /// Stable member order captured once when records first load.
    /// Sorted initially by attendance status (attended → didn't → no response),
    /// then alphabetically. Stays frozen so names don't jump while an admin toggles.
    @State private var frozenOrder: [String]? = nil

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
                        attendanceLabel(for: row)
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
        .onChange(of: vm.isLoading) { _, loading in
            // Capture order once records are first available; never re-sort after that.
            guard !loading, frozenOrder == nil else { return }
            frozenOrder = allMembers
                .sorted { a, b in
                    let idA = a.id ?? ""
                    let idB = b.id ?? ""
                    let recordA = vm.records.first { $0.id == idA }
                    let recordB = vm.records.first { $0.id == idB }
                    // attended (true) → didn't (false) → no response (nil or isMaybe)
                    func rank(_ r: AttendanceRecord?) -> Int {
                        guard let r, r.isMaybe != true else { return 2 }
                        return r.attending ? 0 : 1
                    }
                    let rankA = rank(recordA)
                    let rankB = rank(recordB)
                    if rankA != rankB { return rankA < rankB }
                    return a.name < b.name
                }
                .compactMap { $0.id }
        }
        .sheet(isPresented: $showRoster) {
            AttendanceRosterSheet(allMembers: allMembers, records: vm.records)
        }
    }

    // MARK: - Admin per-row toggle

    @ViewBuilder
    private func adminToggle(for row: MemberAttendanceRow) -> some View {
        HStack(spacing: 6) {
            attendanceButton(label: "Attended", value: true,  current: row.status, isMaybe: false, memberId: row.id)
            attendanceButton(label: "Didn't",   value: false, current: row.status, isMaybe: false, memberId: row.id)
        }
    }

    @ViewBuilder
    private func attendanceButton(label: String, value: Bool, current: Bool?, isMaybe: Bool, memberId: String) -> some View {
        let isSelected = !isMaybe && current == value
        let color: Color = value ? .green : .red
        Button {
            Task {
                if isSelected {
                    await vm.clearAttendance(uid: memberId)
                } else {
                    await vm.setAttendance(attending: value, uid: memberId)
                }
            }
        } label: {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(isSelected ? color.opacity(0.12) : Color(.systemGray5))
                .foregroundStyle(isSelected ? color : Color.secondary)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? color.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Read-only label (non-admins)

    @ViewBuilder
    private func attendanceLabel(for row: MemberAttendanceRow) -> some View {
        switch row.status {
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
        let isMaybe: Bool
        let status: Bool?
    }

    private var sortedRows: [MemberAttendanceRow] {
        // Use the frozen order when available so names don't jump while toggling.
        // Fall back to alphabetical until records load the first time.
        let orderedIds = frozenOrder ?? allMembers.sorted { $0.name < $1.name }.compactMap { $0.id }
        return orderedIds.compactMap { id in
            guard let member = allMembers.first(where: { $0.id == id }) else { return nil }
            let record = vm.records.first { $0.id == id }
            // In history, "maybe" is treated as no response — event is past, they either came or didn't.
            let status: Bool? = (record?.isMaybe == true) ? nil : record?.attending
            return MemberAttendanceRow(id: id, name: member.name, avatarUrl: member.photoURL, isMaybe: false, status: status)
        }
    }
}
