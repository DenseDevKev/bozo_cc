import SwiftUI

struct PlaceholderOverviewView: View {
    var body: some View {
        ContentUnavailableView(
            "Ultra Controller",
            systemImage: "headphones",
            description: Text("Protocol foundation is not connected yet.")
        )
        .accessibilityIdentifier("overview.placeholder")
    }
}
