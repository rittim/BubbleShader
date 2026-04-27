import SwiftUI

struct ContentView: View {
    @State private var materialStyle: BubbleMaterialStyle = .bubble

    // MARK: - Body

    var body: some View {
        BubbleShowcaseView(materialStyle: $materialStyle)
    }
}

#Preview {
    ContentView()
}
