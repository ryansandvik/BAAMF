import SwiftUI

/// Admin-only screen for configuring default phase deadline durations.
/// Stored at `settings/defaults` in Firestore.
struct AdminSettingsView: View {

    @StateObject private var vm = AppSettingsViewModel()

    var body: some View {
        Form {
            Section {
                durationRow("Submissions", value: $vm.settings.submissionDays)
                durationRow("Veto Window", value: $vm.settings.vetoDays)
                durationRow("Voting Round 1", value: $vm.settings.votingR1Days)
                durationRow("Voting Round 2", value: $vm.settings.votingR2Days)
            } header: {
                Text("Default Phase Durations")
            } footer: {
                Text("When a phase opens, the deadline is pre-filled to this many days from now. The host or admin can override the date before confirming.")
            }

            if let error = vm.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    Task { await vm.save() }
                } label: {
                    HStack {
                        Text(vm.savedFeedback ? "Saved!" : "Save Defaults")
                            .fontWeight(.medium)
                        if vm.isSaving {
                            Spacer()
                            ProgressView()
                        } else if vm.savedFeedback {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .disabled(vm.isSaving)
            }
        }
        .navigationTitle("Phase Deadlines")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
    }

    // MARK: - Duration stepper row

    @ViewBuilder
    private func durationRow(_ label: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 1...30) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value.wrappedValue) day\(value.wrappedValue == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                    .font(.body)
            }
        }
    }
}
