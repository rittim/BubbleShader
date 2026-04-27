import SwiftUI

struct BubbleStageView: View {
    let preset: BubblePreset
    let materialStyle: BubbleMaterialStyle
    let controls: BubbleControls
    let bubbleSize: CGFloat
    let xOffset: CGFloat
    let yOffset: CGFloat

    // MARK: - Body

    var body: some View {
        ZStack {
            if materialStyle == .bubble {
                Ellipse()
                    .fill(.black.opacity(0.36))
                    .frame(width: bubbleSize * 0.9, height: bubbleSize * 0.24)
                    .blur(radius: bubbleSize * 0.08)
                    .offset(y: bubbleSize * 0.55)
            }

            if materialStyle == .liquidGlass {
                Ellipse()
                    .fill(.black.opacity(0.20))
                    .frame(width: bubbleSize * 0.86, height: bubbleSize * 0.19)
                    .blur(radius: bubbleSize * 0.065)
                    .offset(y: bubbleSize * 0.54)
            }

            if materialStyle == .glass {
                Ellipse()
                    .fill(.black.opacity(0.28))
                    .frame(width: bubbleSize * 0.88, height: bubbleSize * 0.20)
                    .blur(radius: bubbleSize * 0.07)
                    .offset(y: bubbleSize * 0.55)
            }

            BubbleMetalBubbleView(
                preset: preset,
                materialStyle: materialStyle,
                controls: controls
            )
            .frame(width: bubbleSize, height: bubbleSize)
        }
        .frame(maxWidth: .infinity)
        .offset(x: xOffset, y: yOffset)
    }
}
