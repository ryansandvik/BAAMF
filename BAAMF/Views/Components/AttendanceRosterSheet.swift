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
        let status: Bool?   // true = going, false = not going, nil = no response
    }

    private var goingRows: [MemberRow]       { rowsWithStatus(true)  }
    private var notGoingRows: [MemberRow]    { rowsWithStatus(false) }
    private var noResponseRows: [MemberRow]  { rowsWithStatus(nil)   }

    private func rowsWithStatus(_ status: Bool?) -> [MemberRow] {
        allMembers
            .filter { member in
                let recorded = records.first { $0.id == member.id }?.attending
                switch status {
                case true:  return recorded == true
                case false: return recorded == false
                case nil:   return recorded == nil
                }
            }
            .map { MemberRow(id: $0.id ?? "", name: $0.name, photoURL: $0.photoURL, status: status) }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                if !goingRows.isEmpty {
                    Section {
                        ForEach(goingRows) { row in
                            memberRow(row)
                        }
                    } header: {
                        Label("Going (\(goingRows.count))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if !noResponseRows.isEmpty {
                    Section {
                        ForEach(noResponseRows) { row in
                            memberRow(row)
                        }
                    } header: {
                        Label("No Response (\(noResponseRows.count))", systemImage: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                if !notGoingRows.isEmpty {
                    Section {
                        ForEach(notGoingRows) { row in
                            memberRow(row)
                        }
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
