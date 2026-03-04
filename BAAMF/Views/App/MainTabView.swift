import SwiftUI
import Combine

struct MainTabView: View {

    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        TabView {
            // Home — current month lifecycle
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            // History — past months + scores
            NavigationStack {
                HistoryListView()
            }
            .tabItem {
                Label("History", systemImage: "clock.fill")
            }

            // Schedule — host assignments + swap requests
            NavigationStack {
                ScheduleView()
            }
            .tabItem {
                Label("Schedule", systemImage: "calendar")
            }

            // Admin — only visible to admins
            if authViewModel.isAdmin {
                NavigationStack {
                    AdminView()
                }
                .tabItem {
                    Label("Admin", systemImage: "gearshape.fill")
                }
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
}
