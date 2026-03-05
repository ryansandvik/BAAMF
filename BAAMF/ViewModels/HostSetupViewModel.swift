import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class HostSetupViewModel: ObservableObject {

    // MARK: - Form state

    @Published var submissionMode: SubmissionMode = .open
    @Published var theme = ""
    @Published var hasEventDate = false
    @Published var eventDate: Date = {
        Calendar.current.date(byAdding: .weekOfYear, value: 6, to: Date()) ?? Date()
    }()
    @Published var eventEndDate: Date = {
        let start = Calendar.current.date(byAdding: .weekOfYear, value: 6, to: Date()) ?? Date()
        return Calendar.current.date(byAdding: .hour, value: 2, to: start) ?? start
    }()
    @Published var eventLocation = ""
    @Published var eventNotes = ""

    // MARK: - Async state

    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var savedSuccessfully = false

    private let db = FirestoreService.shared

    // MARK: - Pre-populate from existing month

    func load(from month: ClubMonth) {
        submissionMode = month.submissionMode
        theme          = month.theme ?? ""
        hasEventDate   = month.eventDate != nil
        if let start = month.eventDate {
            eventDate    = start
            // Use stored end date if available, otherwise default to 2h after start
            eventEndDate = month.eventEndDate
                ?? Calendar.current.date(byAdding: .hour, value: 2, to: start)
                ?? start
        }
        eventLocation = month.eventLocation ?? ""
        eventNotes    = month.eventNotes ?? ""
    }

    // MARK: - Admin: create a brand-new month document

    func createMonth(year: Int, month: Int, hostId: String) async {
        isSaving = true
        errorMessage = nil
        let monthId = ClubMonth.monthId(year: year, month: month)
        let data: [String: Any] = [
            "year":           year,
            "month":          month,
            "hostId":         hostId,
            "submissionMode": SubmissionMode.open.rawValue,
            "status":         MonthStatus.setup.rawValue
        ]
        do {
            try await db.monthRef(monthId: monthId).setData(data)
            savedSuccessfully = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    // MARK: - Host/admin: update event details only (no status change)

    func saveEventDetails(monthId: String) async {
        isSaving = true
        errorMessage = nil

        var data: [String: Any] = [:]

        if submissionMode == .theme {
            let trimmed = theme.trimmingCharacters(in: .whitespaces)
            data["theme"] = trimmed.isEmpty ? FieldValue.delete() : trimmed
        }

        if hasEventDate {
            data["eventDate"]    = Timestamp(date: eventDate)
            data["eventEndDate"] = Timestamp(date: eventEndDate)
        } else {
            data["eventDate"]    = FieldValue.delete()
            data["eventEndDate"] = FieldValue.delete()
        }

        let loc = eventLocation.trimmingCharacters(in: .whitespaces)
        data["eventLocation"] = loc.isEmpty ? FieldValue.delete() : loc

        let notes = eventNotes.trimmingCharacters(in: .whitespaces)
        data["eventNotes"] = notes.isEmpty ? FieldValue.delete() : notes

        do {
            try await db.monthRef(monthId: monthId).updateData(data)
            savedSuccessfully = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    // MARK: - Host/admin: save mode + event details → transition to submissions

    func saveSetup(monthId: String) async {
        isSaving = true
        errorMessage = nil

        var data: [String: Any] = [
            "submissionMode": submissionMode.rawValue,
            "status":         MonthStatus.submissions.rawValue
        ]

        if submissionMode == .theme, !theme.trimmingCharacters(in: .whitespaces).isEmpty {
            data["theme"] = theme.trimmingCharacters(in: .whitespaces)
        } else {
            data["theme"] = FieldValue.delete()
        }

        if hasEventDate {
            data["eventDate"]    = Timestamp(date: eventDate)
            data["eventEndDate"] = Timestamp(date: eventEndDate)
        } else {
            data["eventDate"]    = FieldValue.delete()
            data["eventEndDate"] = FieldValue.delete()
        }

        let loc = eventLocation.trimmingCharacters(in: .whitespaces)
        data["eventLocation"] = loc.isEmpty ? FieldValue.delete() : loc

        let notes = eventNotes.trimmingCharacters(in: .whitespaces)
        data["eventNotes"] = notes.isEmpty ? FieldValue.delete() : notes

        do {
            try await db.monthRef(monthId: monthId).updateData(data)
            savedSuccessfully = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
