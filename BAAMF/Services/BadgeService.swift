import Foundation
import Combine
import FirebaseFirestore
import UserNotifications

/// Computes and maintains the app icon badge count based on the current user's
/// outstanding actions. Watches all three month slots (previous, current, next)
/// and their books so badges fire regardless of which calendar slot an active
/// phase falls in — e.g. when next month opens submissions while the current
/// month is still in reading.
///
/// Start on sign-in, stop on sign-out.
///
/// Badge triggers (per active month):
///   • Host setup pending (.setup status)
///   • Submissions open and user hasn't filled their slot (mode-aware)
///   • Veto window open and user hasn't hard-passed any book
///   • User's book was Read It–vetoed and no replacement submitted
///   • Round 1 voting open and user hasn't cast both votes
///   • Round 2 voting open and user hasn't cast their vote
@MainActor
final class BadgeService: ObservableObject {

    static let shared = BadgeService()

    /// Published so MainTabView can bind a `.badge` modifier to the Home tab item.
    @Published private(set) var badgeCount: Int = 0

    private let db = FirestoreService.shared

    // One listener per month slot
    private var monthListeners: [String: ListenerRegistration] = [:]
    private var bookListeners:  [String: ListenerRegistration] = [:]

    // Cached data keyed by monthId
    private var months: [String: ClubMonth] = [:]
    private var books:  [String: [Book]]    = [:]

    private var userId: String = ""

    private init() {}

    // MARK: - Lifecycle

    func start(userId: String) {
        guard !userId.isEmpty else { return }
        stop() // clean slate if called again
        self.userId = userId
        let ids = HomeViewModel.adjacentMonthIds()
        for id in [ids.previous, ids.current, ids.next] {
            startMonthListener(monthId: id)
        }
    }

    func stop() {
        monthListeners.values.forEach { $0.remove() }
        bookListeners.values.forEach  { $0.remove() }
        monthListeners = [:]
        bookListeners  = [:]
        months = [:]
        books  = [:]
        userId = ""
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
    }

    // MARK: - Firestore listeners

    private func startMonthListener(monthId: String) {
        monthListeners[monthId] = db.monthRef(monthId: monthId)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let month = try? snapshot?.data(as: ClubMonth.self) {
                        self.months[monthId] = month
                        // Open a books listener for any month in an action-requiring phase
                        if month.needsBooksForBadge {
                            self.startBooksListener(monthId: monthId)
                        }
                    } else {
                        self.months.removeValue(forKey: monthId)
                        self.books.removeValue(forKey: monthId)
                        self.bookListeners[monthId]?.remove()
                        self.bookListeners.removeValue(forKey: monthId)
                    }
                    self.applyBadge()
                }
            }
    }

    private func startBooksListener(monthId: String) {
        guard bookListeners[monthId] == nil else { return }
        bookListeners[monthId] = db.booksRef(monthId: monthId)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.books[monthId] = snapshot?.documents
                        .compactMap { try? $0.data(as: Book.self) } ?? []
                    self.applyBadge()
                }
            }
    }

    // MARK: - Badge computation

    private func applyBadge() {
        let count = computeBadgeCount()
        badgeCount = count
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
    }

    func computeBadgeCount() -> Int {
        let uid = userId
        guard !uid.isEmpty else { return 0 }
        return months.values.reduce(0) { total, month in
            total + badgeCount(for: month, uid: uid)
        }
    }

    /// Contribution of a single month to the total badge count.
    private func badgeCount(for month: ClubMonth, uid: String) -> Int {
        guard month.id != nil, month.isHistorical != true else { return 0 }
        var count = 0
        let monthBooks    = books[month.id ?? ""] ?? []
        let eligibleBooks = monthBooks.filter { !$0.isRemovedByVeto }
        let userBooks     = monthBooks.filter { $0.submitterId == uid }

        switch month.status {

        case .setup:
            if month.hostId == uid { count += 1 }

        case .submissions:
            let hasSubmitted = eligibleBooks.contains { $0.submitterId == uid }
            switch month.submissionMode {
            case .open, .theme:
                if !hasSubmitted { count += 1 }
            case .pick4:
                if month.hostId == uid && eligibleBooks.count < 4 { count += 1 }
            }

        case .vetoes:
            // Badge until the user has opened the veto screen. Opening VetoView writes
            // their uid to `vetoReviewedBy`, which clears this badge reactively.
            let hasReviewed = (month.vetoReviewedBy ?? []).contains(uid)
            if !hasReviewed { count += 1 }

            // Extra badge if user's book was Read It–vetoed and needs replacement
            let wasReadItVetoed = userBooks.contains {
                $0.isRemovedByVeto && !$0.vetoType2Penalty
            }
            if wasReadItVetoed {
                let hasReplacement: Bool
                switch month.submissionMode {
                case .open, .theme:
                    hasReplacement = eligibleBooks.contains { $0.submitterId == uid }
                case .pick4:
                    hasReplacement = eligibleBooks.count >= 4
                }
                if !hasReplacement { count += 1 }
            }

        case .votingR1:
            let votesCast = monthBooks.filter {
                !$0.isRemovedByVeto && $0.votingR1Voters.contains(uid)
            }.count
            if votesCast < K.Voting.r1VotesPerMember { count += 1 }

        case .votingR2:
            let r2Books = monthBooks.filter { $0.isEligibleForR2 }
            let hasVotedR2 = r2Books.contains { $0.votingR2Voters.contains(uid) }
            if !hasVotedR2 { count += 1 }

        default:
            break
        }

        return count
    }
}

// MARK: - ClubMonth helper

private extension ClubMonth {
    /// True for statuses where we need the books subcollection to compute badge state.
    var needsBooksForBadge: Bool {
        switch status {
        case .submissions, .vetoes, .votingR1, .votingR2: return true
        default: return false
        }
    }
}
