import SwiftUI

/// Sheet allowing the host or admin to update an active month's event details.
/// Edits date, location, notes, and theme — does NOT change the month's status.
struct EditMonthDetailsView: View {

    let month: ClubMonth

    @StateObject private var viewModel = HostSetupViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {

                // MARK: When
                Section {
                    Toggle("Add Event Date", isOn: $viewModel.hasEventDate)
                    if viewModel.hasEventDate {
                        FiveMinuteDatePicker("Start", selection: $viewModel.eventDate)
                            .onChange(of: viewModel.eventDate) { old, new in
                                let delta = new.timeIntervalSince(old)
                                if delta != 0 {
                                    viewModel.eventEndDate = viewModel.eventEndDate.addingTimeInterval(delta)
                                }
                            }
                        FiveMinuteDatePicker("End", selection: $viewModel.eventEndDate)
                    }
                } header: {
                    Text("When")
                }

                // MARK: Where & Activity
                Section {
                    TextField("Location (optional)", text: $viewModel.eventLocation)
                    TextField("Activity description (optional)", text: $viewModel.eventDescription, axis: .vertical)
                        .lineLimit(4...8)
                } header: {
                    Text("Where & Activity")
                } footer: {
                    Text("Describe what members should bring, prepare, or know about. Supports links: [text](url)")
                        .font(.caption)
                }

                // MARK: Theme (only shown for theme-mode months)
                if month.submissionMode == .theme {
                    Section {
                        TextField("Theme", text: $viewModel.theme)
                    } header: {
                        Text("Theme")
                    } footer: {
                        Text("Members submit books that fit this theme.")
                    }
                }

                // MARK: Error
                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Edit Event Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.isSaving)
                }
            }
            .onChange(of: viewModel.savedSuccessfully) { _, success in
                if success { dismiss() }
            }
            .onAppear {
                viewModel.load(from: month)
            }
        }
    }

    private func save() async {
        guard let monthId = month.id else { return }
        await viewModel.saveEventDetails(monthId: monthId)
    }
}
