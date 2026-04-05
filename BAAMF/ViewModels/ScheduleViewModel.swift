import Foundation
import Combine
import FirebaseFirestore

/// Manages the host schedule for a selectable year and all swap requests.
@MainActor
final class ScheduleViewModel: ObservableObject {

    @Published private(set) var schedule: HostSchedule?
    @Published private(set) var allMembers: [Member] = []
    @Published private(set) var swapRequests: [SwapRequest] = []
    @Published var isLoading = true
    @Published var isActing = false
    @Published var errorMessage: String?

    /// The year currently being viewed/edited. Defaults to the current calendar year.
    @Published private(set) var selectedYear: Int = Calendar.current.component(.year, from: Date())

    private let db = FirestoreService.shared
    private var scheduleListener: ListenerRegistration?
    private var swapListener: ListenerRegistration?

    // Today's year and month — used for "is past" logic independent of selectedYear.
    var todayYear:  Int { Calendar.current.component(.year,  from: Date()) }
    var todayMonth: Int { Calendar.current.component(.month, from: Date()) }

    // MARK: - Lifecycle

    func start() {
        isLoading = true
        Task {
            allMembers = (try? await db.fetchAllMembers())?.sorted { $0.name < $1.name } ?? []
        }
        startListeners()
    }

    func stop() {
        scheduleListener?.remove()
        swapListener?.remove()
    }

    /// Switch the viewed year, restarting Firestore listeners for the new year.
    func changeYear(_ year: Int) {
        guard year != selectedYear else { return }
        selectedYear = year
        stop()
        schedule = nil
        swapRequests = []
        isLoading = true
        startListeners()
    }

    // MARK: - Derived helpers

    func hostId(for month: Int) -> String? {
        schedule?.assignments[String(month)]
    }

    func memberName(for userId: String) -> String {
        allMembers.first { $0.id == userId }?.name ?? "Unknown"
    }

    /// True if a month should be greyed out (it's already passed).
    /// - Past years: all months are past.
    /// - Future years: no months are past.
    /// - Current year: months before today's month are past.
    func isPastMonth(_ month: Int) -> Bool {
        if selectedYear < todayYear { return true }
        if selectedYear > todayYear { return false }
        return month < todayMonth
    }

    func pendingRequests(involving userId: String) -> [SwapRequest] {
        swapRequests.filter { $0.requesterId == userId || $0.targetId == userId }
    }

    // MARK: - Auto-generate schedule

    /// Returns an updated assignments dictionary with previously unassigned months distributed
    /// as evenly as possible among all members (fewest-first, alphabetical tiebreak).
    /// Does NOT save to Firestore — the caller reviews and saves.
    func autoGenerateAssignments(from existing: [String: String]) -> [String: String] {
        var result = existing
        let unassigned = (1...12).filter { month in
            let v = result[String(month)]
            return v == nil || v!.isEmpty
        }

        // If everything is already assigned, re-randomize all 12 months from
        // scratch so the admin can shuffle a few times before locking it in.
        let monthsToFill: [Int]
        if unassigned.isEmpty {
            monthsToFill = Array(1...12)
            result = [:]          // Clear existing so counts start at zero
        } else {
            monthsToFill = unassigned
        }

        // Virtual / observer members are excluded from automatic scheduling.
        // Shuffle so equal-count tiebreaks are random, not alphabetical.
        let memberIds = allMembers.filter { !$0.isVirtual && !$0.isObserver }.compactMap { $0.id }.shuffled()
        guard !memberIds.isEmpty else { return existing }

        // Tally how many months each member is already assigned (after any reset)
        var counts: [String: Int] = Dictionary(uniqueKeysWithValues: memberIds.map { ($0, 0) })
        for (_, memberId) in result where !memberId.isEmpty {
            counts[memberId, default: 0] += 1
        }

        for month in monthsToFill {
            // Pick the member with the fewest current assignments.
            // Because memberIds is pre-shuffled, equal-count ties resolve randomly.
            guard let pick = memberIds.min(by: { a, b in
                counts[a, default: 0] < counts[b, default: 0]
            }) else { continue }
            result[String(month)] = pick
            counts[pick, default: 0] += 1
        }

        return result
    }

    // MARK: - Create / update schedule (admin)

    func saveSchedule(assignments: [String: String]) async {
        isActing = true
        errorMessage = nil
        do {
            let oldAssignments = schedule?.assignments ?? [:]
            let batch = db.db.batch()

            // Update the schedule document
            batch.setData(["assignments": assignments],
                          forDocument: db.hostScheduleRef(year: selectedYear))

            // Propagate host changes to any month documents that already exist.
            // This ensures the home screen and month cards stay in sync when an
            // admin edits the schedule after documents have been auto-created.
            for (monthStr, newHostId) in assignments {
                guard let monthNum = Int(monthStr) else { continue }
                let oldHostId = oldAssignments[monthStr] ?? ""
                guard oldHostId != newHostId else { continue }   // no change

                let monthId = ClubMonth.monthId(year: selectedYear, month: monthNum)
                let snap = try await db.monthRef(monthId: monthId).getDocument()
                if snap.exists {
                    batch.updateData(["hostId": newHostId],
                                     forDocument: db.monthRef(monthId: monthId))
                }
            }

            try await batch.commit()
        } catch {
            errorMessage = error.localizedDescription
        }
        isActing = false
    }

    // MARK: - Request a swap

    func requestSwap(requesterId: String,
                     requesterMonth: Int,
                     targetId: String,
                     targetMonth: Int) async {
        isActing = true
        errorMessage = nil
        let newId = UUID().uuidString
        let request = SwapRequest(
            requesterId: requesterId,
            targetId: targetId,
            requesterMonth: requesterMonth,
            targetMonth: targetMonth,
            status: .pending,
            createdAt: Date()
        )
        do {
            try db.swapRequestRef(year: selectedYear, requestId: newId).setData(from: request)
        } catch {
            errorMessage = error.localizedDescription
        }
        isActing = false
    }

    // MARK: - Respond to a swap request

    func respondToSwap(request: SwapRequest, accept: Bool) async {
        guard let requestId = request.id else { return }
        isActing = true
        errorMessage = nil

        do {
            if accept {
                var newAssignments = schedule?.assignments ?? [:]
                newAssignments[String(request.requesterMonth)] = request.targetId
                if request.targetMonth > 0 {
                    newAssignments[String(request.targetMonth)] = request.requesterId
                }

                let batch = db.db.batch()
                batch.updateData(["assignments": newAssignments],
                                 forDocument: db.hostScheduleRef(year: selectedYear))
                batch.updateData(["status": SwapRequestStatus.accepted.rawValue],
                                 forDocument: db.swapRequestRef(year: selectedYear,
                                                                requestId: requestId))

                try await applyAssignmentChange(batch: batch,
                                                month: request.requesterMonth,
                                                newHostId: request.targetId)
                if request.targetMonth > 0 {
                    try await applyAssignmentChange(batch: batch,
                                                    month: request.targetMonth,
                                                    newHostId: request.requesterId)
                }

                try await batch.commit()
            } else {
                try await db.swapRequestRef(year: selectedYear, requestId: requestId)
                    .updateData(["status": SwapRequestStatus.rejected.rawValue])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isActing = false
    }

    // MARK: - Cancel a swap request (requester withdraws)

    func cancelSwap(requestId: String) async {
        isActing = true
        errorMessage = nil
        do {
            try await db.swapRequestRef(year: selectedYear, requestId: requestId).delete()
        } catch {
            errorMessage = error.localizedDescription
        }
        isActing = false
    }

    // MARK: - Force swap (admin only)

    func forceSwap(month1: Int, month2: Int) async {
        guard var assignments = schedule?.assignments else { return }
        isActing = true
        errorMessage = nil

        let userId1 = assignments[String(month1)]
        let userId2 = assignments[String(month2)]
        assignments[String(month1)] = userId2
        assignments[String(month2)] = userId1

        do {
            let batch = db.db.batch()
            batch.updateData(["assignments": assignments],
                             forDocument: db.hostScheduleRef(year: selectedYear))
            if let newHost = userId2 {
                try await applyAssignmentChange(batch: batch, month: month1, newHostId: newHost)
            }
            if let newHost = userId1 {
                try await applyAssignmentChange(batch: batch, month: month2, newHostId: newHost)
            }
            try await batch.commit()
        } catch {
            errorMessage = error.localizedDescription
        }
        isActing = false
    }

    // MARK: - Private

    private func startListeners() {
        scheduleListener = db.hostScheduleRef(year: selectedYear)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.schedule = try? snapshot?.data(as: HostSchedule.self)
                }
            }

        swapListener = db.swapRequestsRef(year: selectedYear)
            .whereField("status", isEqualTo: SwapRequestStatus.pending.rawValue)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Permissions errors on the swap subcollection are non-fatal —
                    // the schedule is still shown; swap features are silently hidden
                    // until Firestore rules grant access.
                    if error != nil { return }
                    self.swapRequests = snapshot?.documents
                        .compactMap { try? $0.data(as: SwapRequest.self) } ?? []
                }
            }
    }

    /// If the month document already exists in Firestore, queues a hostId update on the batch.
    private func applyAssignmentChange(batch: WriteBatch,
                                       month: Int,
                                       newHostId: String) async throws {
        let monthId = ClubMonth.monthId(year: selectedYear, month: month)
        let snap = try await db.monthRef(monthId: monthId).getDocument()
        if snap.exists {
            batch.updateData(["hostId": newHostId], forDocument: db.monthRef(monthId: monthId))
        }
    }
}

// MARK: - HostSchedule convenience init (avoids touching @DocumentID in initialiser)

private extension HostSchedule {
    init(assignments: [String: String]) {
        self.assignments = assignments
    }
}
