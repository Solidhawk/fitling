import SwiftUI

struct RootView: View {
    var body: some View {
        ProgressView()
            .accessibilityLabel(Text("common.loading"))
            .accessibilityIdentifier("root.loading")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.paper)
    }
}
