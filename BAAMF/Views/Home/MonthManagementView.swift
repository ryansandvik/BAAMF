import SwiftUI
import FirebaseFirestore

/// Single sheet for the host/admin to control all month management:
/// phase transitions (forward and backward) and event detail editing.
/// Opened via the gear icon on the Home tab month header card.
struct MonthManagementView: View {

    let month: ClubMonth

    @StateObject private var setupViewModel = HostSetupViewModel()
    @Environment(\.dismiss) private var dismiss

    // Phase transition state
    @State private var targetStatus: MonthStatus?
    @State private var showPhaseConfirm = false
    @State private var isSavingPhase = false

    // Event details state
    @State private var isSavingDetails = false
    @State private var detailsSavedFeedback = false

    private let db = FirestoreService.shared
    private let allPhases = MonthStatus.allCases

    private var currentIndex: Int {
        allPhases.firstIndex(of: month.status) ?? 0
    }
    private var nextPhase: MonthStatus? {
        let i = currentIndex + 1
        return i < allPhases.count ? allPhases[i] : nil
    }
    private var previousPhase: MonthStatus? {
        let i = currentIndex - 1
        return i >= 0 ? allPhases[i] : nil
    }
    private var isGoingBackward: Bool {
        guard let target = targetStatus,
              let ti = allPhases.firstIndex(of: target) else { return false }
        return ti < currentIndex
    }

    var body: some View {
        NavigationStack {
            List {

                // MARK: Phase timeline
                Section {
                    phaseTimeline
                } header: {
                    Text("Current Phase")
                }

                // MARK: Phase controls
                Section {
                    if let next = nextPhase {
                        Button {
                            targetStatus = next
                            showPhaseConfirm = true
                        } label: {
                            Label("Advance to \(next.displayName)",
                                  systemImage: "arrow.right.circle.fill")
                                .foregroundStyle(.tint)
                                .fontWeight(.medium)
                        }
                    } else {
                        Label("Month is complete", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.secondary)
                    }

                    if let prev = previousPhase {
                        Button(role: .destructive) {
                            targetStatus = prev
                            showPhaseConfirm = true
                        } label: {
                            Label("Return to \(prev.displayName)",
                                  systemImage: "arrow.left.circle")
                        }
                    }
                } header: {
                    Text("Phase Control")
                } footer: {
                    Text("Changes take effect immediately for all members.")
                }

                // MARK: Event details (inline editing)
                Section {
                    Toggle("Add Event Date", isOn: $setupViewModel.hasEventDate)
                    if setupViewModel.hasEventDate {
                        DatePicker("Date & Time",
                                   selection: $setupViewModel.eventDate,
                                   displayedComponents: [.date, .hourAndMinute])
                    }
                    TextField("Location (optional)", text: $setupViewModel.eventLocation)
                    TextField("Notes (optional)",
                              text: $setupViewModel.eventNotes,
                              axis: .vertical)
                        .lineLimit(3...6)

                    if month.submissionMode == .theme {
                        TextField("Theme", text: $setupViewModel.theme)
                    }
                } header: {
                    Text("Event Details")
                }

                Section {
                    Button {
                        Task { await saveDetails() }
                    } label: {
                        HStack {
                            Text(detailsSavedFeedback ? "Saved!" : "Save Event Details")
                                .fontWeight(.medium)
                            if isSavingDetails {
                                Spacer()
                                ProgressView()
                            } else if detailsSavedFeedback {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .disabled(isSavingDetails)
                }

                // MARK: Error
                if let error = setupViewModel.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Manage Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                setupViewModel.load(from: month)
            }
            // Phase transition confirmation
            .confirmationDialog(
                confirmTitle,
                isPresented: $showPhaseConfirm,
                titleVisibility: .visible
            ) {
                Button(confirmActionLabel, role: isGoingBackward ? .destructive : nil) {
                    Task { await changePhase() }
                }
                Button("Cancel", role: .cancel) { targetStatus = nil }
            } message: {
                Text(confirmMessage)
            }
            .overlay {
                if isSavingPhase {
                    ProgressView()
                        .padding(20)
                        .background(.ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Phase timeline

    private var phaseTimeline: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(allPhases.enumerated()), id: \.element) { index, phase in
                    let isPast    = index < currentIndex
                    let isCurrent = index == currentIndex

                    HStack(spacing: 0) {
                        // Connector line (skip for first item)
                        if index > 0 {
                            Rectangle()
                                .frame(width: 16, height: 2)
                                .foregroundStyle(isPast || isCurrent
                                                 ? Color.accentColor
                                                 : Color.secondary.opacity(0.25))
                                .padding(.bottom, 14)
                        }

                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .frame(width: 22, height: 22)
                                    .foregroundStyle(
                                        isPast    ? Color.accentColor :
                                        isCurrent ? Color.accentColor :
                                                    Color.secondary.opacity(0.2)
                                    )
                                if isPast {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                } else if isCurrent {
                                    Circle()
                                        .frame(width: 9, height: 9)
                                        .foregroundStyle(.white)
                                }
                            }
                            Text(phaseShortName(phase))
                                .font(.system(size: 9))
                                .foregroundStyle(isCurrent ? .primary : .secondary)
                                .multilineTextAlignment(.center)
                                .frame(width: 46)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func phaseShortName(_ status: MonthStatus) -> String {
        switch status {
        case .setup:        return "Setup"
        case .submissions:  return "Submit"
        case .vetoes:       return "Vetoes"
        case .votingR1:     return "Vote R1"
        case .votingR2:     return "Vote R2"
        case .scoring:      return "Scoring"
        case .complete:     return "Done"
        }
    }

    // MARK: - Confirmation strings

    private var confirmTitle: String {
        guard let target = targetStatus else { return "Change Phase?" }
        return isGoingBackward
            ? "Return to \(target.displayName)?"
            : "Advance to \(target.displayName)?"
    }

    private var confirmActionLabel: String {
        guard let target = targetStatus else { return "Confirm" }
        return isGoingBackward ? "Return to \(target.displayName)" : "Advance"
    }

    private var confirmMessage: String {
        guard let target = targetStatus else { return "" }
        if isGoingBackward {
            return "Going back to \(target.displayName) will reopen that phase. Any actions members have taken in the current phase may be affected."
        }
        switch (month.status, target) {
        case (.submissions, .vetoes):
            return "Submissions will close immediately. Members can no longer submit or edit books."
        case (.vetoes, .votingR1):
            return "The veto window will close and Round 1 voting will open for all members."
        case (.votingR1, .votingR2):
            return "Round 1 voting will close. Only the top-ranked books will advance to Round 2."
        case (.votingR2, .scoring):
            return "Voting will close. The winning book will be announced and members can submit their scores."
        case (.scoring, .complete):
            return "This will mark the month as complete and archive it in History."
        default:
            return "This will immediately move the club to the \(target.displayName) phase."
        }
    }

    // MARK: - Actions

    private func changePhase() async {
        guard let target = targetStatus, let monthId = month.id else { return }
        isSavingPhase = true
        setupViewModel.errorMessage = nil
        do {
            try await db.monthRef(monthId: monthId)
                .updateData(["status": target.rawValue])
            dismiss()
        } catch {
            setupViewModel.errorMessage = error.localizedDescription
        }
        isSavingPhase = false
        targetStatus = nil
    }

    private func saveDetails() async {
        guard let monthId = month.id else { return }
        isSavingDetails = true
        await setupViewModel.saveEventDetails(monthId: monthId)
        isSavingDetails = false
        if setupViewModel.errorMessage == nil {
            detailsSavedFeedback = true
            // Reset feedback after 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            detailsSavedFeedback = false
        }
    }
}
