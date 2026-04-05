import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class HostSetupViewModel: ObservableObject {

    // MARK: - Form state

    @Published var submissionMode: SubmissionMode = .open
    @Published var theme = ""
    @Published var hasEventDate = false
    @Published var eventDate: Date = Date()
    @Published var eventEndDate: Date = {
        Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
    }()
    @Published var eventLocation = ""
    /// Host's activity description. Supports markdown hyperlinks.
    @Published var eventDescription = ""
    /// Deadline for the submissions phase. Defaults to 7 days from now.
    /// Ignored (and cleared) when submissionMode is .pick4.
    @Published var submissionDeadline: Date = Calendar.current.date(
        byAdding: .day, value: 7, to: Date()) ?? Date()

    // MARK: - Async state

    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var savedSuccessfully = false

    private let db = FirestoreService.shared

    // MARK: - Original values (for unsaved-change detection)

    private var originalSubmissionMode: SubmissionMode = .open
    private var originalTheme: String = ""
    private var originalHasEventDate: Bool = false
    private var originalEventDate: Date = Date()
    private var originalEventEndDate: Date = Date()
    private var originalEventLocation: String = ""
    private var originalEventDescription: String = ""

    /// True if any event-detail field differs from what was last loaded from Firestore.
    var hasUnsavedChanges: Bool {
        submissionMode    != originalSubmissionMode   ||
        theme             != originalTheme            ||
        hasEventDate      != originalHasEventDate     ||
        (hasEventDate && eventDate    != originalEventDate)    ||
        (hasEventDate && eventEndDate != originalEventEndDate) ||
        eventLocation     != originalEventLocation    ||
        eventDescription  != originalEventDescription
    }

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
        eventLocation      = month.eventLocation ?? ""
        eventDescription   = month.eventDescription ?? ""
        submissionDeadline = month.submissionDeadline
            ?? Calendar.current.date(byAdding: .day, value: 7, to: Date())
            ?? Date()

        // Snapshot original values so hasUnsavedChanges starts false
        originalSubmissionMode   = submissionMode
        originalTheme            = theme
        originalHasEventDate     = hasEventDate
        originalEventDate        = eventDate
        originalEventEndDate     = eventEndDate
        originalEventLocation    = eventLocation
        originalEventDescription = eventDescription
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

        // eventNotes has been consolidated into eventDescription; always clear it.
        data["eventNotes"] = FieldValue.delete()

        let desc = eventDescription.trimmingCharacters(in: .whitespaces)
        data["eventDescription"] = desc.isEmpty ? FieldValue.delete() : desc

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

        // eventNotes has been consolidated into eventDescription; always clear it.
        data["eventNotes"] = FieldValue.delete()

        let desc = eventDescription.trimmingCharacters(in: .whitespaces)
        data["eventDescription"] = desc.isEmpty ? FieldValue.delete() : desc

        // Submission deadline — set for open/theme, cleared for pick-4
        if submissionMode != .pick4 {
            data["submissionDeadline"] = Timestamp(date: submissionDeadline)
        } else {
            data["submissionDeadline"] = FieldValue.delete()
        }

        do {
            try await db.monthRef(monthId: monthId).updateData(data)
            savedSuccessfully = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
