import Combine
import SwiftUI

/// The signed-in app: today's food, training, the week menu, the partner, and the daily target
/// with the account.
struct HomeView: View {
    let profile: UserProfile
    let sync: SyncEngine
    let food: FoodServices
    let account: AccountViewModel
    let health: any HealthReading
    let shopping: ShoppingServices
    /// Owned here rather than by the partner tab, so the partner catches up with finished days
    /// and plans its reminders whichever tab is open.
    @State private var partner: PartnerViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(
        profile: UserProfile, sync: SyncEngine, food: FoodServices, reminders: any ReminderDelivery,
        health: any HealthReading, shopping: ShoppingServices, account: AccountViewModel
    ) {
        self.profile = profile
        self.health = health
        self.shopping = shopping
        self.sync = sync
        self.food = food
        self.account = account
        _partner = State(initialValue: PartnerViewModel(profile: profile, context: sync.context, delivery: reminders))
    }

    var body: some View {
        TabView {
            DayView(profile: profile, sync: sync, food: food, partner: partner)
                .tabItem { Label("tab.today", systemImage: "fork.knife") }
            TrainingTabView(profile: profile, sync: sync, health: health)
                .tabItem { Label("training.title", systemImage: "dumbbell") }
            MenuTabView(profile: profile, sync: sync, shopping: shopping)
                .tabItem { Label("menu.title", systemImage: "frying.pan") }
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
