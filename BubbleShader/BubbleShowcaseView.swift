import SwiftUI

struct BubbleShowcaseView: View {
    @Binding var materialStyle: BubbleMaterialStyle

    private let preset: BubblePreset = .standard

    @State private var controls = BubbleControls(style: .bubble, preset: .standard)
    @State private var controlTab: BubbleControlTab = .visual

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let metrics = BubbleShowcaseMetrics(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets)

            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    BubbleStageView(
                        preset: preset,
                        materialStyle: materialStyle,
                        controls: controls,
                        bubbleSize: metrics.bubbleSize,
                        xOffset: metrics.bubbleXOffset,
                        yOffset: metrics.bubbleYOffset
                    )
                    .frame(height: metrics.stageHeight)

                    Spacer(minLength: 0)

                    BubbleControlPanel(
                        materialStyle: $materialStyle,
                        controlTab: $controlTab,
                        controls: $controls,
                        height: metrics.controlHeight,
                        bottomInset: metrics.bottomInset,
                        reset: resetControls
                    )
                }
                .padding(.top, metrics.topPadding)
            }
        }
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
        .onAppear {
            controls = BubbleControls(style: materialStyle, preset: preset)
        }
        .onChange(of: materialStyle) { _, newStyle in
            handleMaterialStyleChange(newStyle)
        }
    }

    // MARK: - Actions

    private func handleMaterialStyleChange(_ newStyle: BubbleMaterialStyle) {
        withAnimation(.easeInOut(duration: 0.35)) {
            controls = BubbleControls(style: newStyle, preset: preset)
            controlTab = defaultControlTab(for: newStyle)
        }
    }

    private func resetControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controls = BubbleControls(style: materialStyle, preset: preset)
        }
    }

    private func defaultControlTab(for style: BubbleMaterialStyle) -> BubbleControlTab {
        style == .liquidGlass ? .glass : .visual
    }
}

// MARK: - Layout Metrics

private struct BubbleShowcaseMetrics {
    let topPadding: CGFloat
    let bottomInset: CGFloat
    let controlHeight: CGFloat
    let stageHeight: CGFloat
    let bubbleSize: CGFloat
    let bubbleXOffset: CGFloat
    let bubbleYOffset: CGFloat

    init(size: CGSize, safeAreaInsets: EdgeInsets) {
        topPadding = min(size.height * 0.03, 22)
        bottomInset = max(safeAreaInsets.bottom, 12)

        let availableHeight = max(size.height - topPadding, 1)
        controlHeight = max(availableHeight * 0.5, 300)
        stageHeight = max(availableHeight - controlHeight, 1)
        bubbleSize = min(size.width * 0.84, stageHeight * 0.78)
        bubbleXOffset = size.width > size.height ? size.width * 0.1 : 0
        bubbleYOffset = max(18, safeAreaInsets.top * 0.5 + stageHeight * 0.03)
    }
}
