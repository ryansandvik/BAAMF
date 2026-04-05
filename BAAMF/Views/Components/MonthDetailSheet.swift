import SwiftUI

/// Full event-detail sheet shown when a user taps the month card header.
/// Displays host, date/time, location, and the host's activity description
/// (with markdown hyperlink support).
struct MonthDetailSheet: View {

    let month: ClubMonth
    let hostName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── Month title ───────────────────────────────────────────
                    Text(month.month.monthName + " \(month.year)")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // ── Host ──────────────────────────────────────────────────
                    detailRow(icon: "person.fill", label: "Host", value: hostName)

                    // ── Date / time ───────────────────────────────────────────
                    if let start = month.eventDate {
                        if let end = month.eventEndDate {
                            detailRow(
                                icon: "calendar",
                                label: "Date",
                                value: start.formatted(date: .long, time: .omitted)
                            )
                            detailRow(
                                icon: "clock",
                                label: "Time",
                                value: "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
                            )
                        } else {
                            detailRow(
                                icon: "calendar",
                                label: "Date & Time",
                                value: start.formatted(date: .long, time: .shortened)
                            )
                        }
                    }

                    // ── Location ──────────────────────────────────────────────
                    if let location = month.eventLocation, !location.isEmpty {
                        detailRow(icon: "mappin.and.ellipse", label: "Location", value: location)
                    }

                    // ── Activity description (merge legacy Notes field if present) ─
                    let legacyNotes = month.eventNotes ?? ""
                    let description = month.eventDescription ?? ""
                    let combinedDesc: String = {
                        if description.isEmpty { return legacyNotes }
                        if legacyNotes.isEmpty { return description }
                        return description + "\n\n" + legacyNotes
                    }()
                    if !combinedDesc.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Activity Details", systemImage: "list.bullet.clipboard")
                                .font(.footnote.bold())
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.5)

                            // Render as markdown so [text](url) links are tappable.
                            // Falls back to plain text if markdown parsing fails.
                            if let attributed = try? AttributedString(
                                markdown: combinedDesc,
                                options: AttributedString.MarkdownParsingOptions(
                                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                                )
                            ) {
                                Text(attributed)
                                    .font(.body)
                                    .tint(.accentColor)
                            } else {
                                Text(combinedDesc)
                                    .font(.body)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .cardStyle()
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Event Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Row helper

    @ViewBuilder
    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardStyle()
    }
}
