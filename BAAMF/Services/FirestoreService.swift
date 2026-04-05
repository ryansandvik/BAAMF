import Foundation
import FirebaseFirestore

/// Central access point for Firestore collection/document references.
/// Feature-specific reads and writes live in their ViewModels; this service
/// just provides the canonical path constants and convenience accessors.
final class FirestoreService {

    static let shared = FirestoreService()
    let db = Firestore.firestore()

    private init() {}

    // MARK: - Collection references

    func usersRef() -> CollectionReference {
        db.collection(K.Firestore.users)
    }

    func userRef(uid: String) -> DocumentReference {
        usersRef().document(uid)
    }

    func hostScheduleRef(year: Int) -> DocumentReference {
        db.collection(K.Firestore.hostSchedule).document(String(year))
    }

    func monthsRef() -> CollectionReference {
        db.collection(K.Firestore.months)
    }

    func monthRef(monthId: String) -> DocumentReference {
        monthsRef().document(monthId)
    }

    func booksRef(monthId: String) -> CollectionReference {
        monthRef(monthId: monthId).collection(K.Firestore.books)
    }

    func bookRef(monthId: String, bookId: String) -> DocumentReference {
        booksRef(monthId: monthId).document(bookId)
    }

    func votesR1Ref(monthId: String) -> CollectionReference {
        monthRef(monthId: monthId).collection(K.Firestore.votesR1)
    }

    func votesR2Ref(monthId: String) -> CollectionReference {
        monthRef(monthId: monthId).collection(K.Firestore.votesR2)
    }

    func scoresRef(monthId: String) -> CollectionReference {
        monthRef(monthId: monthId).collection(K.Firestore.scores)
    }

    func inviteCodesRef() -> CollectionReference {
        db.collection("inviteCodes")
    }

    func inviteCodeRef(code: String) -> DocumentReference {
        inviteCodesRef().document(code.uppercased())
    }

    func attendanceRef(monthId: String) -> CollectionReference {
        monthRef(monthId: monthId).collection("attendance")
    }

    func attendanceDocRef(monthId: String, uid: String) -> DocumentReference {
        attendanceRef(monthId: monthId).document(uid)
    }

    func rollCallsRef(monthId: String) -> CollectionReference {
        monthRef(monthId: monthId).collection("rollCalls")
    }

    func settingsRef() -> DocumentReference {
        db.collection("settings").document("defaults")
    }

    func swapRequestsRef(year: Int) -> CollectionReference {
        hostScheduleRef(year: year).collection(K.Firestore.swapRequests)
    }

    func swapRequestRef(year: Int, requestId: String) -> DocumentReference {
        swapRequestsRef(year: year).document(requestId)
    }

    // MARK: - Common one-shot reads

    func fetchMember(uid: String) async throws -> Member {
        let snapshot = try await userRef(uid: uid).getDocument()
        guard let member = try? snapshot.data(as: Member.self) else {
            throw AppError.memberNotFound
        }
        return member
    }

    func fetchAllMembers() async throws -> [Member] {
        let snapshot = try await usersRef().getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Member.self) }
    }

    // MARK: - Codable write helpers

    /// Writes an Encodable value as a new document with an auto-generated ID.
    /// Throws on encoding or network failure.
    @discardableResult
    func addDocument<T: Encodable>(to collection: CollectionReference, value: T) throws -> DocumentReference {
        try collection.addDocument(from: value)
    }
}

// MARK: - App-level errors

enum AppError: LocalizedError {
    case memberNotFound
    case monthNotFound
    case permissionDenied
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .memberNotFound:   return "Member profile not found."
        case .monthNotFound:    return "No active month found."
        case .permissionDenied: return "You don't have permission to do that."
        case .unknown(let msg): return msg
        }
    }
}
