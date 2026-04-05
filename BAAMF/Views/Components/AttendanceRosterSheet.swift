import SwiftUI

/// Full-screen sheet showing all members sorted by RSVP status,
/// with avatar and name. Opened from the attendance section/card.
struct AttendanceRosterSheet: View {

    let allMembers: [Member]
    let records: [AttendanceRecord]

    @Environment(\.dismiss) private var dismiss

    // MARK: - Data

    private struct MemberRow: Identifiable {
        let id: String
        let name: String
        let photoURL: String?
        let isMaybe: Bool
        let status: Bool?   // true = going, false = not going, nil = no response / maybe
    }

    private var goingRows: [MemberRow] {
        allMembers
            .filter { member in
                guard let rec = records.first(where: { $0.id == member.id }) else { return false }
                return rec.attending && rec.isMaybe != true
            }
            .map { MemberRow(id: $0.id ?? "", name: $0.name, photoURL: $0.photoURL, isMaybe: false, status: true) }
            .sorted { $0.name < $1.name }
    }

    private var maybeRows: [MemberRow] {
        allMembers
            .filter { member in
                records.first(where: { $0.id == member.id })?.isMaybe == true
            }
            .map { MemberRow(id: $0.id ?? "", name: $0.name, photoURL: $0.photoURL, isMaybe: true, status: nil) }
            .sorted { $0.name < $1.name }
    }

    private var notGoingRows: [MemberRow] {
        allMembers
            .filter { member in
                guard let rec = records.first(where: { $0.id == member.id }) else { return false }
                return !rec.attending && rec.isMaybe != true
            }
            .map { MemberRow(id: $0.id ?? "", name: $0.name, photoURL: $0.photoURL, isMaybe: false, status: false) }
            .sorted { $0.name < $1.name }
    }

    private var noResponseRows: [MemberRow] {
        allMembers
            .filter { member in records.first(where: { $0.id == member.id }) == nil }
            .map { MemberRow(id: $0.id ?? "", name: $0.name, photoURL: $0.photoURL, isMaybe: false, status: nil) }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                if !goingRows.isEmpty {
                    Section {
                        ForEach(goingRows) { row in memberRow(row) }
                    } header: {
                        Label("Going (\(goingRows.count))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if !maybeRows.isEmpty {
                    Section {
                        ForEach(maybeRows) { row in memberRow(row) }
                    } header: {
                        Label("Maybe (\(maybeRows.count))", systemImage: "questionmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if !noResponseRows.isEmpty {
                    Section {
                        ForEach(noResponseRows) { row in memberRow(row) }
                    } header: {
                        Label("No Response (\(noResponseRows.count))", systemImage: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                if !notGoingRows.isEmpty {
                    Section {
                        ForEach(notGoingRows) { row in memberRow(row) }
                    } header: {
                        Label("Not Going (\(notGoingRows.count))", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Attendance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func memberRow(_ row: MemberRow) -> some View {
        HStack(spacing: 12) {
            MemberAvatar(name: row.name, photoURL: row.photoURL, size: 38)
            Text(row.name)
                .font(.body)
        }
        .padding(.vertical, 2)
    }
}
