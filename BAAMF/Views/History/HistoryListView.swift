import SwiftUI

/// Lists all completed months with their winning book and group average score.
struct HistoryListView: View {

    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading history…")
            } else if viewModel.months.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "clock",
                    description: Text("Completed months will appear here.")
                )
            } else {
                monthList
            }
        }
        .navigationTitle("History")
        .task { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Month list

    private var monthList: some View {
        List {
            ForEach(viewModel.months) { month in
                NavigationLink {
                    HistoryDetailView(month: month, allMembers: viewModel.allMembers)
                } label: {
                    monthRow(month)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color(.secondarySystemGroupedBackground))
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Month row

    private func monthRow(_ month: ClubMonth) -> some View {
        HStack(spacing: 14) {
            // Book cover
            if let coverUrl = month.selectedBookCoverUrl {
                CoverImage(url: coverUrl, size: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 44, height: 60)
                    .overlay {
                        Image(systemName: "book.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
            }

            // Text info
            VStack(alignment: .leading, spacing: 4) {
                Text("\(month.month.monthName) \(month.year)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let title = month.selectedBookTitle {
                    Text(title)
                        .font(.body.bold())
                        .lineLimit(2)
                }
                if let author = month.selectedBookAuthor {
                    Text(author)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Group average
            if let avg = month.groupAvgScore {
                VStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.footnote)
                    Text(avg.scoreDisplay)
                        .font(.footnote.bold())
                }
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack { HistoryListView() }
}
