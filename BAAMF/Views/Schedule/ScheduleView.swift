import SwiftUI

/// Shows the host schedule for the current year.
/// Members can request swaps on their own future months; admins can force-swap
/// any two months or set up / edit the full schedule.
struct ScheduleView: View {

    @StateObject private var viewModel = ScheduleViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var showSetupSheet = false
    @State private var showRequestSwap = false
    @State private var swapSourceMonth: Int?
    @State private var showForceSwap = false
    @State private var forceSwapMonth: Int?

    private var currentUserId: String { authViewModel.currentUserId ?? "" }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading schedule…")
            } else if viewModel.schedule == nil {
                noScheduleView
            } else {
                scheduleList
            }
        }
        .navigationTitle("Schedule")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                yearPicker
            }
        }
        .task { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .sheet(isPresented: $showSetupSheet) {
            SetupScheduleSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showRequestSwap) {
            if let month = swapSourceMonth {
                RequestSwapSheet(viewModel: viewModel,
                                 requesterMonth: month,
                                 requesterId: currentUserId)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Year picker

    private var yearPicker: some View {
        Menu {
            Picker("Year", selection: Binding(
                get: { viewModel.selectedYear },
                set: { viewModel.changeYear($0) }
            )) {
                Text(String(viewModel.todayYear)).tag(viewModel.todayYear)
                Text(String(viewModel.todayYear + 1)).tag(viewModel.todayYear + 1)
            }
        } label: {
            HStack(spacing: 3) {
                Text(String(viewModel.selectedYear))
                    .fontWeight(.semibold)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.tint)
        }
    }

    // MARK: - No schedule placeholder

    private var noScheduleView: some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                "No Schedule Set",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("The " + String(viewModel.selectedYear) + " host rotation hasn't been created yet.")
            )
            if authViewModel.isAdmin {
                Button {
                    showSetupSheet = true
                } label: {
                    Label("Set Up Schedule", systemImage: "plus.circle.fill")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Schedule list

    private var scheduleList: some View {
        List {
            Section(String(viewModel.selectedYear) + " Host Schedule") {
                ForEach(1...12, id: \.self) { month in
                    monthRow(month)
                }
            }

            let myRequests = viewModel.pendingRequests(involving: currentUserId)
            if !myRequests.isEmpty {
                Section("Swap Requests") {
                    ForEach(myRequests) { request in
                        swapRequestRow(request)
                    }
                }
            }

            if authViewModel.isAdmin {
                Section("Admin") {
                    Button {
                        showSetupSheet = true
                    } label: {
                        Label("Edit Schedule", systemImage: "pencil")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Month row

    @ViewBuilder
    private func monthRow(_ month: Int) -> some View {
        let hostId = viewModel.hostId(for: month) ?? ""
        let hostName = hostId.isEmpty ? "Unassigned" : viewModel.memberName(for: hostId)
        let isMe = hostId == currentUserId
        let isPast = viewModel.isPastMonth(month)
        let hasPendingSwap = viewModel.swapRequests.contains {
            $0.requesterMonth == month || $0.targetMonth == month
        }

        HStack(spacing: 12) {
            Text(month.monthName)
                .font(.body)
                .foregroundStyle(isPast ? .secondary : .primary)
                .frame(width: 80, alignment: .leading)

            Text(hostName)
                .font(.body)
                .foregroundStyle(isPast ? .secondary : (isMe ? Color.accentColor : .primary))
                .lineLimit(1)

            if isMe {
                Text("You")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }

            if hasPendingSwap {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()

            if authViewModel.isAdmin {
                adminMenuButton(for: month)
            } else if isMe && !isPast {
                Button {
                    swapSourceMonth = month
                    showRequestSwap = true
                } label: {
                    Text("Swap")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func adminMenuButton(for month: Int) -> some View {
        Menu {
            ForEach(1...12, id: \.self) { other in
                if other != month {
                    let otherHostId = viewModel.hostId(for: other) ?? ""
                    let otherName = otherHostId.isEmpty
                        ? "Unassigned" : viewModel.memberName(for: otherHostId)
                    Button("Swap with \(other.monthName) (\(otherName))") {
                        Task { await viewModel.forceSwap(month1: month, month2: other) }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
    }

    // MARK: - Swap request row

    @ViewBuilder
    private func swapRequestRow(_ request: SwapRequest) -> some View {
        let isRequester = request.requesterId == currentUserId
        let otherName = isRequester
            ? viewModel.memberName(for: request.targetId)
            : viewModel.memberName(for: request.requesterId)
        let theirMonth = isRequester ? request.targetMonth : request.requesterMonth
        let myMonth = isRequester ? request.requesterMonth : request.targetMonth

        VStack(alignment: .leading, spacing: 8) {
            if isRequester {
                let returnDesc = request.targetMonth == 0
                    ? "no return swap"
                    : "their \(request.targetMonth.monthName)"
                Text("You asked \(otherName) to swap — you give \(request.requesterMonth.monthName), \(returnDesc).")
                    .font(.footnote)
            } else {
                let returnDesc = request.targetMonth == 0
                    ? "no return swap needed"
                    : "they want your \(request.targetMonth.monthName) in return"
                Text("\(otherName) wants to give you \(request.requesterMonth.monthName) (\(returnDesc)).")
                    .font(.footnote)
            }

            HStack(spacing: 10) {
                if isRequester {
                    Button(role: .destructive) {
                        guard let id = request.id else { return }
                        Task { await viewModel.cancelSwap(requestId: id) }
                    } label: {
                        Text("Cancel Request")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        Task { await viewModel.respondToSwap(request: request, accept: true) }
                    } label: {
                        Text("Accept")
                            .font(.caption.bold())
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Color.green.opacity(0.12))
                            .foregroundStyle(.green)
                            .overlay(Capsule().strokeBorder(Color.green.opacity(0.4), lineWidth: 1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await viewModel.respondToSwap(request: request, accept: false) }
                    } label: {
                        Text("Decline")
                            .font(.caption.bold())
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Color(.systemGray5))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.isActing { ProgressView().scaleEffect(0.7) }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Setup / Edit Schedule Sheet

private struct SetupScheduleSheet: View {

    @ObservedObject var viewModel: ScheduleViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var assignments: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(1...12, id: \.self) { month in
                        Picker(month.monthName, selection: assignmentBinding(for: month)) {
                            Text("Unassigned").tag("")
                            ForEach(viewModel.allMembers) { member in
                                Text(member.name).tag(member.id ?? "")
                            }
                        }
                    }
                } header: {
                    Text(String(viewModel.selectedYear) + " Host Assignments")
                } footer: {
                    Text("Assign a host for each month, then tap Save.")
                }

                Section {
                    Button {
                        assignments = viewModel.autoGenerateAssignments(from: assignments)
                    } label: {
                        Label("Auto-Assign Remaining", systemImage: "wand.and.stars")
                    }
                    .disabled(viewModel.allMembers.isEmpty)
                } footer: {
                    Text("Distributes unassigned months evenly among all members. Already-assigned months are left as-is. Review before saving.")
                }
            }
            .navigationTitle("Set Up Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.saveSchedule(assignments: assignments)
                            if viewModel.errorMessage == nil { dismiss() }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.isActing)
                }
            }
            .onAppear {
                assignments = viewModel.schedule?.assignments ?? [:]
            }
        }
    }

    private func assignmentBinding(for month: Int) -> Binding<String> {
        Binding(
            get: { assignments[String(month)] ?? "" },
            set: { assignments[String(month)] = $0 }
        )
    }
}

// MARK: - Request Swap Sheet

private struct RequestSwapSheet: View {

    @ObservedObject var viewModel: ScheduleViewModel
    let requesterMonth: Int
    let requesterId: String

    @Environment(\.dismiss) private var dismiss

    @State private var targetMemberId = ""
    @State private var targetMonth = 0

    private var targetMonthOptions: [(label: String, value: Int)] {
        guard !targetMemberId.isEmpty else { return [("No return swap", 0)] }
        var opts: [(String, Int)] = [("No return swap (just take my month)", 0)]
        for m in 1...12 {
            if viewModel.hostId(for: m) == targetMemberId && m != requesterMonth {
                opts.append((m.monthName, m))
            }
        }
        return opts
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("You are offering to give up \(requesterMonth.monthName).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: { Text("Your Month") }

                Section {
                    Picker("Member", selection: $targetMemberId) {
                        Text("Select a member…").tag("")
                        ForEach(viewModel.allMembers.filter { $0.id != requesterId }) { member in
                            Text(member.name).tag(member.id ?? "")
                        }
                    }
                    .onChange(of: targetMemberId) { _, _ in targetMonth = 0 }
                } header: { Text("Swap With") }

                if !targetMemberId.isEmpty {
                    Section {
                        Picker("Their Month", selection: $targetMonth) {
                            ForEach(targetMonthOptions, id: \.value) { opt in
                                Text(opt.label).tag(opt.value)
                            }
                        }
                    } header: {
                        Text("Return Swap (Optional)")
                    } footer: {
                        Text("If you pick a month, both months swap once accepted. Leave as 'No return swap' to just offload your month.")
                    }
                }
            }
            .navigationTitle("Request Swap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send Request") {
                        Task {
                            await viewModel.requestSwap(
                                requesterId: requesterId,
                                requesterMonth: requesterMonth,
                                targetId: targetMemberId,
                                targetMonth: targetMonth
                            )
                            if viewModel.errorMessage == nil { dismiss() }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(targetMemberId.isEmpty || viewModel.isActing)
                }
            }
        }
    }
}

#Preview {
    NavigationStack { ScheduleView() }
        .environmentObject(AuthViewModel())
}
