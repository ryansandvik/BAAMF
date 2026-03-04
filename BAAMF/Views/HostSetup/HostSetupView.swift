import SwiftUI
import Combine

/// Shown to the host (or admin) when the month is in "setup" status.
/// Sets the submission mode, optional theme, and event details.
/// On save, the month transitions to "submissions" status.
struct HostSetupView: View {

    let month: ClubMonth

    @StateObject private var viewModel = HostSetupViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            // MARK: Submission Mode
            Section {
                Picker("Mode", selection: $viewModel.submissionMode) {
                    ForEach([SubmissionMode.open, .theme, .pick4], id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Submission Mode")
            } footer: {
                Text(viewModel.submissionMode.description)
            }

            // Theme field — only shown in theme mode
            if viewModel.submissionMode == .theme {
                Section("Theme") {
                    TextField("e.g. Books set in space", text: $viewModel.theme)
                        .autocorrectionDisabled()
                }
            }

            // MARK: Event Details (all optional)
            Section("Event Details (Optional)") {
                Toggle("Set event date", isOn: $viewModel.hasEventDate.animation())
                if viewModel.hasEventDate {
                    DatePicker("Date & Time",
                               selection: $viewModel.eventDate,
                               displayedComponents: [.date, .hourAndMinute])
                }
                TextField("Location", text: $viewModel.eventLocation)
                    .autocorrectionDisabled()
                TextField("Notes", text: $viewModel.eventNotes, axis: .vertical)
                    .lineLimit(3, reservesSpace: false)
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
        .navigationTitle("Host Setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Open Submissions") {
                    Task { await viewModel.saveSetup(monthId: month.id ?? "") }
                }
                .fontWeight(.semibold)
                .disabled(viewModel.isSaving || !isValid)
            }
        }
        .onAppear { viewModel.load(from: month) }
        .onChange(of: viewModel.savedSuccessfully) { _, success in
            if success { dismiss() }
        }
        .overlay {
            if viewModel.isSaving {
                Color.black.opacity(0.1).ignoresSafeArea()
                ProgressView("Saving…")
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var isValid: Bool {
        if viewModel.submissionMode == .theme {
            return !viewModel.theme.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }
}
