import SwiftUI
import FirebaseFirestore

/// Single sheet for controlling month management.
/// • All users: view phase timeline.
/// • Host / admin only: advance/revert phases, edit event details.
struct MonthManagementView: View {

    let month: ClubMonth

    @StateObject private var setupViewModel = HostSetupViewModel()
    @StateObject private var settingsVM = AppSettingsViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    // Phase transition state
    @State private var targetStatus: MonthStatus?
    @State private var showAdvanceSheet = false      // forward transitions — has DatePicker
    @State private var showRevertConfirm = false     // backward transitions — destructive dialog
    @State private var proposedDeadline: Date = Date()
    @State private var isSavingPhase = false

    // Event details state
    @State private var isSavingDetails = false
    @State private var detailsSavedFeedback = false

    // Unsaved-changes guard
    @State private var showUnsavedChangesConfirm = false

    private let db = FirestoreService.shared
    private let allPhases = MonthStatus.allCases

    private var isHostOrAdmin: Bool {
        month.isHost(userId: authViewModel.currentUserId ?? "") || authViewModel.isAdmin
    }

    private var currentIndex: Int {
        allPhases.firstIndex(of: month.status) ?? 0
    }
    private var nextPhase: MonthStatus? {
        let i = currentIndex + 1
        return i < allPhases.count ? allPhases[i] : nil
    }
    private var previousPhase: MonthStatus? {
        let i = currentIndex - 1
        return i >= 0 ? allPhases[i] : nil
    }

    /// True when the target phase gets a deadline DatePicker.
    /// Deadlines are not used in pick4 mode.
    private var targetPhaseHasDeadline: Bool {
        guard let target = targetStatus else { return false }
        guard month.submissionMode != .pick4 else { return false }
        return deadlineKey(for: target) != nil
    }

    private func deadlineKey(for status: MonthStatus) -> String? {
        switch status {
        case .submissions: return "submissionDeadline"
        case .vetoes:      return "vetoDeadline"
        case .votingR1:    return "votingR1Deadline"
        case .votingR2:    return "votingR2Deadline"
        default:           return nil
        }
    }

    var body: some View {
        NavigationStack {
            List {

                // MARK: Phase timeline (visible to all)
                Section {
                    phaseTimeline
                } header: {
                    Text("Current Phase")
                }

                // MARK: Phase controls (host / admin only)
                if isHostOrAdmin {
                    Section {
                        if let next = nextPhase {
                            Button {
                                targetStatus = next
                                proposedDeadline = settingsVM.settings.defaultDeadline(for: next) ?? Date()
                                showAdvanceSheet = true
                            } label: {
                                Label("Advance to \(next.displayName)",
                                      systemImage: "arrow.right.circle.fill")
                                    .foregroundStyle(.tint)
                                    .fontWeight(.medium)
                            }
                        } else {
                            Label("Month is complete", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.secondary)
                        }

                        if let prev = previousPhase {
                            Button(role: .destructive) {
                                targetStatus = prev
                                showRevertConfirm = true
                            } label: {
                                Label("Return to \(prev.displayName)",
                                      systemImage: "arrow.left.circle")
                            }
                        }
                    } header: {
                        Text("Phase Control")
                    } footer: {
                        Text("Changes take effect immediately for all members.")
                    }

                    // MARK: Event details
                    Section {
                        Toggle("Add Event Date", isOn: $setupViewModel.hasEventDate)
                        if setupViewModel.hasEventDate {
                            DatePicker("Start",
                                       selection: $setupViewModel.eventDate,
                                       displayedComponents: [.date, .hourAndMinute])
                            DatePicker("End",
                                       selection: $setupViewModel.eventEndDate,
                                       in: setupViewModel.eventDate...,
                                       displayedComponents: [.date, .hourAndMinute])
                        }
                        TextField("Location (optional)", text: $setupViewModel.eventLocation)
                        TextField("Notes (optional)",
                                  text: $setupViewModel.eventNotes,
                                  axis: .vertical)
                            .lineLimit(3...6)

                        if month.submissionMode == .theme {
                            TextField("Theme", text: $setupViewModel.theme)
                        }
                    } header: {
                        Text("Event Details")
                    }

                    Section {
                        Button {
                            Task { await saveDetails() }
                        } label: {
                            HStack {
                                Text(detailsSavedFeedback ? "Saved!" : "Save Event Details")
                                    .fontWeight(.medium)
                                if isSavingDetails {
                                    Spacer()
                                    ProgressView()
                                } else if detailsSavedFeedback {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .disabled(isSavingDetails)
                    }
                }

                // MARK: Error
                if let error = setupViewModel.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }

            }
            .navigationTitle("Manage Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if isHostOrAdmin && setupViewModel.hasUnsavedChanges {
                            showUnsavedChangesConfirm = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .interactiveDismissDisabled(isHostOrAdmin && setupViewModel.hasUnsavedChanges)
            .onAppear {
                if isHostOrAdmin { setupViewModel.load(from: month) }
            }
            .task { await settingsVM.load() }
            // Unsaved changes dialog
            .confirmationDialog(
                "Unsaved Changes",
                isPresented: $showUnsavedChangesConfirm,
                titleVisibility: .visible
            ) {
                Button("Save & Close") {
                    Task { await saveDetails(); dismiss() }
                }
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("You have unsaved event details. Would you like to save them before closing?")
            }
            // Backward transition: destructive confirmationDialog
            .confirmationDialog(
                revertTitle,
                isPresented: $showRevertConfirm,
                titleVisibility: .visible
            ) {
                Button("Return to \(targetStatus?.displayName ?? "")", role: .destructive) {
                    Task { await changePhase(deadline: nil) }
                }
                Button("Cancel", role: .cancel) { targetStatus = nil }
            } message: {
                Text(revertMessage)
            }
            // Forward transition: sheet with optional DatePicker
            .sheet(isPresented: $showAdvanceSheet) {
                advanceSheet
            }
            .overlay {
                if isSavingPhase {
                    ProgressView()
                        .padding(20)
                        .background(.ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Advance phase sheet

    @ViewBuilder
    private var advanceSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text(advanceMessage)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                if targetPhaseHasDeadline {
                    Section {
                        DatePicker(
                            "Deadline",
                            selection: $proposedDeadline,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    } header: {
                        Text("Phase Deadline")
                    } footer: {
                        Text("This phase will auto-advance when the deadline passes. You can always advance early from Phase Control.")
                    }
                }
            }
            .navigationTitle("Advance to \(targetStatus?.displayName ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAdvanceSheet = false
                        targetStatus = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Advance") {
                        showAdvanceSheet = false
                        let deadline = targetPhaseHasDeadline ? proposedDeadline : nil
                        Task { await changePhase(deadline: deadline) }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents(targetPhaseHasDeadline ? [.medium] : [.fraction(0.35)])
    }

    // MARK: - Phase timeline

    private var phaseTimeline: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(allPhases.enumerated()), id: \.element) { index, phase in
                    let isPast    = index < currentIndex
                    let isCurrent = index == currentIndex

                    HStack(spacing: 0) {
                        if index > 0 {
                            Rectangle()
                                .frame(width: 16, height: 2)
                                .foregroundStyle(isPast || isCurrent
                                                 ? Color.accentColor
                                                 : Color.secondary.opacity(0.25))
                                .padding(.bottom, 14)
                        }

                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .frame(width: 22, height: 22)
                                    .foregroundStyle(
                                        isPast    ? Color.accentColor :
                                        isCurrent ? Color.accentColor :
                                                    Color.secondary.opacity(0.2)
                                    )
                                if isPast {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                } else if isCurrent {
                                    Circle()
                                        .frame(width: 9, height: 9)
                                        .foregroundStyle(.white)
                                }
                            }
                            Text(phaseShortName(phase))
                                .font(.system(size: 9))
                                .foregroundStyle(isCurrent ? .primary : .secondary)
                                .multilineTextAlignment(.center)
                                .frame(width: 46)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func phaseShortName(_ status: MonthStatus) -> String {
        switch status {
        case .setup:        return "Setup"
        case .submissions:  return "Submit"
        case .vetoes:       return "Vetoes"
        case .votingR1:     return "Vote R1"
        case .votingR2:     return "Vote R2"
        case .reading:      return "Reading"
        case .scoring:      return "Scoring"
        case .complete:     return "Done"
        }
    }

    // MARK: - Confirmation strings

    private var revertTitle: String {
        guard let target = targetStatus else { return "Return to Previous Phase?" }
        return "Return to \(target.displayName)?"
    }

    private var revertMessage: String {
        guard let target = targetStatus else { return "" }
        switch (month.status, target) {
        case (.votingR1, .vetoes):
            return "All Round 1 votes will be cleared. Members will need to vote again when the round reopens."
        case (.votingR2, .votingR1):
            return "All Round 2 votes will be cleared and books will need to be re-advanced to Round 2."
        case (.reading, .votingR2):
            return "The selected book will be cleared and Round 2 voting will reopen."
        case (.vetoes, .submissions):
            return "All vetoes will be cleared and submissions will reopen. Any Hard Pass charges spent this month will be refunded."
        default:
            return "Going back to \(target.displayName) will reopen that phase. Any actions members have taken in the current phase may be affected."
        }
    }

    private var advanceMessage: String {
        guard let target = targetStatus else { return "" }
        switch (month.status, target) {
        case (.submissions, .vetoes):
            return "Submissions will close immediately. Members can no longer submit or edit books."
        case (.vetoes, .votingR1):
            return "The veto window will close and Round 1 voting will open for all members."
        case (.votingR1, .votingR2):
            return "Round 1 voting will close. Only the top-ranked books will advance to Round 2."
        case (.votingR2, .reading):
            return "Round 2 voting will close. The book with the most votes becomes the pick for this month."
        case (.reading, .scoring):
            return "The reading period will end. Members can now score the book at your event."
        case (.scoring, .complete):
            return "This will mark the month as complete and archive it in History."
        default:
            return "This will immediately move the club to the \(target.displayName) phase."
        }
    }

    // MARK: - Phase change routing

    private func changePhase(deadline: Date?) async {
        guard let target = targetStatus, let monthId = month.id else { return }
        isSavingPhase = true
        setupViewModel.errorMessage = nil
        do {
            switch (month.status, target) {
            // Special forward transitions
            case (.votingR1, .votingR2):
                try await advanceToR2(monthId: monthId, deadline: deadline)
            case (.votingR2, .reading):
                try await advanceToReading(monthId: monthId)
            // Special backward transitions (all clear deadlines)
            case (.vetoes, .submissions):
                try await revertToSubmissions(monthId: monthId)
            case (.votingR1, .vetoes):
                try await revertToVetoes(monthId: monthId)
            case (.votingR2, .votingR1):
                try await revertToVotingR1(monthId: monthId)
            case (.reading, .votingR2):
                try await revertToVotingR2(monthId: monthId)
            case (.scoring, .complete):
                try await finalizeScoring(monthId: monthId)
            // All other transitions: simple status update + optional deadline
            default:
                var update: [String: Any] = ["status": target.rawValue]
                if let dl = deadline, let key = deadlineKey(for: target) {
                    update[key] = Timestamp(date: dl)
                }
                try await db.monthRef(monthId: monthId).updateData(update)
            }
            dismiss()
        } catch {
            setupViewModel.errorMessage = error.localizedDescription
        }
        isSavingPhase = false
        targetStatus = nil
    }

    // MARK: - Forward transitions

    private func advanceToR2(monthId: String, deadline: Date?) async throws {
        let booksSnap = try await db.booksRef(monthId: monthId).getDocuments()

        struct BookScore {
            let ref: DocumentReference
            let netVotes: Int
        }

        let scores: [BookScore] = booksSnap.documents.compactMap { doc in
            let data = doc.data()
            guard !(data["isRemovedByVeto"] as? Bool ?? false) else { return nil }
            let rawVotes = (data["votingR1Voters"] as? [String] ?? []).count
            let penalty  = (data["vetoType2Penalty"] as? Bool ?? false)
                           ? K.Veto.type2PenaltyVotes : 0
            return BookScore(ref: doc.reference, netVotes: rawVotes + penalty)
        }.sorted { $0.netVotes > $1.netVotes }

        let cutoffScore: Int = scores.count >= K.Voting.r2AdvanceCount
            ? scores[K.Voting.r2AdvanceCount - 1].netVotes
            : (scores.last?.netVotes ?? 0)

        let batch = db.db.batch()
        var monthUpdate: [String: Any] = ["status": MonthStatus.votingR2.rawValue]
        if let dl = deadline {
            monthUpdate["votingR2Deadline"] = Timestamp(date: dl)
        }
        batch.updateData(monthUpdate, forDocument: db.monthRef(monthId: monthId))
        for score in scores where score.netVotes >= cutoffScore {
            batch.updateData(["advancedToR2": true], forDocument: score.ref)
        }
        try await batch.commit()
    }

    private func advanceToReading(monthId: String) async throws {
        let booksSnap = try await db.booksRef(monthId: monthId).getDocuments()

        let winner = booksSnap.documents
            .filter { ($0.data()["advancedToR2"] as? Bool) == true }
            .map { doc -> (id: String, data: [String: Any], r2Count: Int) in
                let data = doc.data()
                let r2Count = (data["votingR2Voters"] as? [String] ?? []).count
                return (doc.documentID, data, r2Count)
            }
            .sorted { $0.r2Count > $1.r2Count }
            .first

        var update: [String: Any] = ["status": MonthStatus.reading.rawValue]
        if let winner = winner {
            update["selectedBookId"]     = winner.id
            update["selectedBookTitle"]  = winner.data["title"]  as? String ?? ""
            update["selectedBookAuthor"] = winner.data["author"] as? String ?? ""
            if let coverUrl = winner.data["coverUrl"] as? String {
                update["selectedBookCoverUrl"] = coverUrl
            }
            if let submitterId = winner.data["submitterId"] as? String, !submitterId.isEmpty {
                update["selectedBookSubmitterId"] = submitterId
            }
        }

        try await db.monthRef(monthId: monthId).updateData(update)
        await autoCreateNextMonth()
    }

    private func autoCreateNextMonth() async {
        let (nextYear, nextMonthNum): (Int, Int) = month.month == 12
            ? (month.year + 1, 1)
            : (month.year, month.month + 1)

        let nextMonthId = ClubMonth.monthId(year: nextYear, month: nextMonthNum)

        guard let snap = try? await db.monthRef(monthId: nextMonthId).getDocument(),
              !snap.exists else { return }

        let scheduleSnap = try? await db.hostScheduleRef(year: nextYear).getDocument()
        let schedule     = try? scheduleSnap?.data(as: HostSchedule.self)
        let nextHostId   = schedule?.assignments[String(nextMonthNum)] ?? ""

        let data: [String: Any] = [
            "year":           nextYear,
            "month":          nextMonthNum,
            "hostId":         nextHostId,
            "submissionMode": SubmissionMode.open.rawValue,
            "status":         MonthStatus.setup.rawValue
        ]
        try? await db.monthRef(monthId: nextMonthId).setData(data)
    }

    // MARK: - Backward transitions
    // All backward transitions clear ALL deadline fields to prevent stale auto-advance.

    private var deadlineClearFields: [String: Any] {[
        "submissionDeadline": FieldValue.delete(),
        "vetoDeadline":       FieldValue.delete(),
        "votingR1Deadline":   FieldValue.delete(),
        "votingR2Deadline":   FieldValue.delete(),
    ]}

    private func revertToSubmissions(monthId: String) async throws {
        let booksSnap = try await db.booksRef(monthId: monthId).getDocuments()

        var refundMap: [String: Int] = [:]
        for doc in booksSnap.documents {
            let voters = doc.data()["vetoType2Voters"] as? [String] ?? []
            for userId in voters { refundMap[userId, default: 0] += 1 }
        }

        var memberCharges: [String: [[String: Any]]] = [:]
        for userId in refundMap.keys {
            let snap = try await db.userRef(uid: userId).getDocument()
            memberCharges[userId] = snap.data()?["vetoCharges"] as? [[String: Any]] ?? []
        }

        let batch = db.db.batch()
        var monthUpdate: [String: Any] = ["status": MonthStatus.submissions.rawValue]
        monthUpdate.merge(deadlineClearFields) { _, new in new }
        batch.updateData(monthUpdate, forDocument: db.monthRef(monthId: monthId))

        for doc in booksSnap.documents {
            batch.updateData(["vetoType2Voters": [], "vetoType2Penalty": false],
                             forDocument: doc.reference)
        }

        for (userId, count) in refundMap {
            var charges = memberCharges[userId] ?? []
            let removeCount = min(count, charges.count)
            guard removeCount > 0 else { continue }
            charges.removeLast(removeCount)
            batch.updateData(["vetoCharges": charges], forDocument: db.userRef(uid: userId))
        }

        try await batch.commit()
    }

    private func revertToVetoes(monthId: String) async throws {
        let booksSnap = try await db.booksRef(monthId: monthId).getDocuments()
        let batch = db.db.batch()
        var monthUpdate: [String: Any] = ["status": MonthStatus.vetoes.rawValue]
        monthUpdate.merge(deadlineClearFields) { _, new in new }
        batch.updateData(monthUpdate, forDocument: db.monthRef(monthId: monthId))
        for doc in booksSnap.documents {
            batch.updateData(["votingR1Voters": []], forDocument: doc.reference)
        }
        try await batch.commit()
    }

    private func revertToVotingR1(monthId: String) async throws {
        let booksSnap = try await db.booksRef(monthId: monthId).getDocuments()
        let batch = db.db.batch()
        var monthUpdate: [String: Any] = ["status": MonthStatus.votingR1.rawValue]
        monthUpdate.merge(deadlineClearFields) { _, new in new }
        batch.updateData(monthUpdate, forDocument: db.monthRef(monthId: monthId))
        for doc in booksSnap.documents {
            batch.updateData(["votingR2Voters": [], "advancedToR2": false],
                             forDocument: doc.reference)
        }
        try await batch.commit()
    }

    private func revertToVotingR2(monthId: String) async throws {
        var update: [String: Any] = [
            "status":                    MonthStatus.votingR2.rawValue,
            "selectedBookId":            FieldValue.delete(),
            "selectedBookTitle":         FieldValue.delete(),
            "selectedBookAuthor":        FieldValue.delete(),
            "selectedBookCoverUrl":      FieldValue.delete(),
            "selectedBookSubmitterId":   FieldValue.delete()
        ]
        update.merge(deadlineClearFields) { _, new in new }
        try await db.monthRef(monthId: monthId).updateData(update)
    }

    // MARK: - Finalize scoring

    private func finalizeScoring(monthId: String) async throws {
        let scoresSnap = try await db.scoresRef(monthId: monthId).getDocuments()
        let scoreValues = scoresSnap.documents.compactMap { $0.data()["score"] as? Double }

        var update: [String: Any] = ["status": MonthStatus.complete.rawValue]
        if !scoreValues.isEmpty {
            let avg = scoreValues.reduce(0, +) / Double(scoreValues.count)
            update["groupAvgScore"] = (avg * 10).rounded() / 10
        }

        try await db.monthRef(monthId: monthId).updateData(update)
    }

    // MARK: - Save event details

    private func saveDetails() async {
        guard let monthId = month.id else { return }
        isSavingDetails = true
        await setupViewModel.saveEventDetails(monthId: monthId)
        isSavingDetails = false
        if setupViewModel.errorMessage == nil {
            detailsSavedFeedback = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            detailsSavedFeedback = false
        }
    }
}
