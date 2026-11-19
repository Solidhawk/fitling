import SwiftUI

/// The signed-in app: today's food first, the daily target and account second. Later phases add
/// the partner, training and the week menu as tabs.
struct HomeView: View {
    let profile: UserProfile
    let sync: SyncEngine
    let food: FoodServices
    let account: AccountViewModel

    var body: some View {
        TabView {
            DayView(profile: profile, sync: sync, food: food)
                .tabItem { Label("tab.today", systemImage: "fork.knife") }
            ProfileView(profile: profile, sync: sync, account: account)
                .tabItem { Label("profile.title", systemImage: "chart.pie") }
        }
    }
}
