import Foundation

/// `K` is the namespace for all app-wide constants.
enum K {

    // MARK: - Firestore collection names
    enum Firestore {
        static let users        = "users"
        static let hostSchedule = "hostSchedule"
        static let months       = "months"
        static let books        = "books"
        static let votesR1      = "votes_r1"
        static let votesR2      = "votes_r2"
        static let scores        = "scores"
        static let swapRequests  = "swapRequests"
    }

    // MARK: - Google Books API
    // Store your key in a Config.xcconfig (git-ignored) and reference it via Info.plist.
    // See README for setup. Fallback empty string will surface as a runtime error on search.
    enum GoogleBooks {
        static let apiKey: String = {
            Bundle.main.object(forInfoDictionaryKey: "GOOGLE_BOOKS_API_KEY") as? String ?? ""
        }()
        static let baseURL = "https://www.googleapis.com/books/v1/volumes"
        static let maxResults = 20  // Fetches extra so culling doesn't leave too few results
    }

    // MARK: - Scoring
    enum Scoring {
        static let minScore: Double = 1.0
        static let maxScore: Double = 7.0
        static let step: Double = 0.5
    }

    // MARK: - Voting
    enum Voting {
        static let r1VotesPerMember = 2
        static let r2VotesPerMember = 1
        /// Number of books that advance to Round 2 (plus ties at 2nd place).
        static let r2AdvanceCount = 2
    }

    // MARK: - Veto
    enum Veto {
        static let maxCharges = 2
        static let cooldownMonths = 12
        /// Minimum fraction of voting members needed for a Type 2 veto penalty to apply.
        static let type2ThresholdFraction: Double = 0.25
        static let type2PenaltyVotes = -2
    }
}
