import Combine
import SwiftUI

/// The signed-in app: today's food, the partner, and the daily target with the account. Later
/// phases add training and the week menu as tabs.
struct HomeView: View {
    let profile: UserProfile
    let sync: SyncEngine
    let food: FoodServices
    let account: AccountViewModel
    /// Owned here rather than by the partner tab, so the partner catches up with finished days
    /// and plans its reminders whichever tab is open.
    @State private var partner: PartnerViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(profile: UserProfile, sync: SyncEngine, food: FoodServices, reminders: any ReminderDelivery, account: AccountViewModel) {
        self.profile = profile
        self.sync = sync
        self.food = food
        self.account = account
        _partner = State(initialValue: PartnerViewModel(profile: profile, context: sync.context, delivery: reminders))
    }

    var body: some View {
        TabView {
            DayView(profile: profile, sync: sync, food: food)
                .tabItem { Label("tab.today", systemImage: "fork.knife") }
            PartnerTabView(viewModel: partner, context: sync.context)
                .tabItem { Label("partner.title", systemImage: "face.smiling") }
            ProfileView(profile: profile, sync: sync, account: account)
                .tabItem { Label("profile.title", systemImage: "chart.pie") }
        }
        .task { partner.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { partner.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            partner.refresh()
        }
    }
}
