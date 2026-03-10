import SwiftUI
import Combine

struct MainTabView: View {

    @EnvironmentObject private var authViewModel: AuthViewModel
    @ObservedObject private var badges  = BadgeService.shared
    @ObservedObject private var router  = DeepLinkRouter.shared

    @State private var selectedTab = 0

    // Per-tab navigation paths — lets us reset Profile stack on tab switch
    @State private var homePath      = NavigationPath()
    @State private var historyPath   = NavigationPath()
    @State private var schedulePath  = NavigationPath()
    @State private var profilePath   = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            // Home — current month lifecycle
            NavigationStack(path: $homePath) {
                HomeView()
            }
            .tag(0)
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .badge(badges.badgeCount)

            // History — past months + scores
            NavigationStack(path: $historyPath) {
                HistoryListView()
            }
            .tag(1)
            .tabItem {
                Label("History", systemImage: "clock.fill")
            }

            // Schedule — host assignments + swap requests
            NavigationStack(path: $schedulePath) {
                ScheduleView()
            }
            .tag(2)
            .tabItem {
                Label("Schedule", systemImage: "calendar")
            }

            // Profile — visible to all members; admin controls are gated inside
            NavigationStack(path: $profilePath) {
                ProfileView()
            }
            .tag(3)
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            // Pop each tab's navigation stack to root when leaving it
            if newTab != 0 { homePath     = NavigationPath() }
            if newTab != 1 { historyPath  = NavigationPath() }
            if newTab != 2 { schedulePath = NavigationPath() }
            if newTab != 3 { profilePath  = NavigationPath() }
        }
        // When a notification deep link arrives, bring the user to the Home tab.
        // HomeView then observes DeepLinkRouter and pushes the appropriate screen.
        .onChange(of: router.pendingLink) { _, link in
            if link != nil { selectedTab = 0 }
        }
        // Start badge listener on sign-in, stop on sign-out.
        .task {
            if let uid = authViewModel.currentUserId {
                BadgeService.shared.start(userId: uid)
            }
        }
        .onDisappear {
            BadgeService.shared.stop()
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
}
