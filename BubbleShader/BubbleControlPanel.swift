import SwiftUI

struct BubbleControlPanel: View {
    @Binding var materialStyle: BubbleMaterialStyle
    @Binding var controlTab: BubbleControlTab
    @Binding var controls: BubbleControls

    let height: CGFloat
    let bottomInset: CGFloat
    let reset: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            Picker("Material", selection: $materialStyle) {
                ForEach(BubbleMaterialStyle.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Picker("Controls", selection: $controlTab) {
                ForEach(availableControlTabs, id: \.self) { tab in
                    Text(tab.label(for: materialStyle)).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(activeSliderRows) { spec in
                        BubbleSliderRow(
                            title: spec.title,
                            value: Binding(
                                get: { controls[keyPath: spec.keyPath] },
                                set: { controls[keyPath: spec.keyPath] = $0 }
                            ),
                            range: spec.range
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            HStack {
                Spacer()

                Button("Reset", action: reset)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16 + bottomInset)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background {
            Rectangle()
                .fill(.black.opacity(0.24))
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)
        }
    }

    // MARK: - Slider Selection

    private var availableControlTabs: [BubbleControlTab] {
        switch materialStyle {
        case .bubble:
            [.visual, .glass, .motion]
        case .liquidGlass:
            [.visual, .glass]
        case .glass:
            [.visual, .glass]
        }
    }

    private var activeSliderRows: [BubbleSliderSpec] {
        BubbleSliderCatalog.rows(for: materialStyle, tab: controlTab)
    }
}

// MARK: - Slider Row

private struct BubbleSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                Text(value.formatted(.number.precision(.fractionLength(2))))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Slider(value: $value, in: range)
                .tint(.white.opacity(0.95))
        }
    }
}

// MARK: - Slider Catalog

private struct BubbleSliderSpec: Identifiable {
    let title: String
    let keyPath: WritableKeyPath<BubbleControls, Double>
    let range: ClosedRange<Double>

    var id: String { title }

    init(_ title: String, _ keyPath: WritableKeyPath<BubbleControls, Double>, _ range: ClosedRange<Double>) {
        self.title = title
        self.keyPath = keyPath
        self.range = range
    }
}

private enum BubbleSliderCatalog {
    // Slider groups intentionally list only controls that affect the selected material path.
    static func rows(for style: BubbleMaterialStyle, tab: BubbleControlTab) -> [BubbleSliderSpec] {
        switch (style, tab) {
        case (.glass, .visual):
            glassVisualRows
        case (.glass, .glass):
            glassEnvironmentRows
        case (.glass, .motion):
            glassVisualRows
        case (.liquidGlass, .visual):
            liquidVisualRows
        case (.liquidGlass, .glass):
            liquidEnvironmentRows
        case (.liquidGlass, .motion):
            liquidVisualRows
        case (.bubble, .visual):
            bubbleVisualRows
        case (.bubble, .motion):
            motionRows
        case (.bubble, .glass):
            bubbleEnvironmentRows
        }
    }

    private static let bubbleVisualRows: [BubbleSliderSpec] = [
        .init("Refraction", \.refraction, 0.7...1.9),
        .init("Chroma", \.chromaticSpread, 0.0...2.6),
        .init("Lens", \.lensAmount, 0.2...1.4),
        .init("Edge Distort", \.edgeDistortion, 0.0...2.2),
        .init("Glow", \.glowStrength, 0.0...1.8),
        .init("Flare", \.flareStrength, 0.0...1.8),
        .init("Highlight", \.highlightStrength, 0.0...1.8),
        .init("Top Light", \.rimStrength, 0.0...1.8),
        .init("Iridescence", \.iridescenceAmount, 0.0...1.8),
        .init("Bloom Radius", \.bloomRadius, 0.35...1.9),
        .init("Exposure", \.exposure, 0.75...1.4),
        .init("Image Shadow", \.imageShadowStrength, 0.0...1.5),
        .init("Shell Dim", \.shellDimStrength, 0.0...1.5),
        .init("Rim Shadow", \.rimShadowStrength, 0.0...1.5)
    ]

    private static let bubbleEnvironmentRows: [BubbleSliderSpec] = [
        .init("Env Rotate", \.environmentRotation, -1.0...1.0),
        .init("Env Pitch", \.environmentPitch, -1.0...1.0),
        .init("Env Roll", \.environmentRoll, -1.0...1.0),
        .init("Env Scale Y", \.environmentScaleY, 0.3...2.0),
        .init("Env Boost", \.environmentExposure, 0.2...24.0),
        .init("Env Blur", \.environmentBlur, 0.0...1.0),
        .init("Reflect", \.reflectionStrength, 0.0...2.5),
        .init("Studio Arc", \.studioArcStrength, 0.0...2.0)
    ]

    private static let glassVisualRows: [BubbleSliderSpec] = [
        .init("Refraction", \.refraction, 0.7...1.9),
        .init("Chroma", \.chromaticSpread, 0.0...2.6),
        .init("Lens", \.lensAmount, 0.2...1.4),
        .init("Edge Distort", \.edgeDistortion, 0.0...2.2),
        .init("Refract Blur", \.refractionBlur, 0.0...1.0),
        .init("Highlight", \.highlightStrength, 0.0...1.8),
        .init("Exposure", \.exposure, 0.5...1.5),
        .init("Shell Dim", \.shellDimStrength, 0.0...1.5),
        .init("Rim Shadow", \.rimShadowStrength, 0.0...1.5)
    ]

    private static let liquidVisualRows: [BubbleSliderSpec] = [
        .init("Refraction", \.refraction, 0.7...1.9),
        .init("Lens", \.lensAmount, 0.2...1.4),
        .init("Refract Blur", \.refractionBlur, 0.0...1.0),
        .init("Glass Chroma", \.chromaticSpread, 0.0...2.6),
        .init("Highlight", \.highlightStrength, 0.0...1.8),
        .init("Edge Shape", \.edgeDistortion, 0.0...2.2),
        .init("Exposure", \.exposure, 0.75...1.4),
        .init("Shadow", \.imageShadowStrength, 0.0...1.5),
        .init("Rim Shadow", \.rimShadowStrength, 0.0...1.5)
    ]

    private static let glassEnvironmentRows: [BubbleSliderSpec] = [
        .init("Env Rotate", \.environmentRotation, -1.0...1.0),
        .init("Env Pitch", \.environmentPitch, -1.0...1.0),
        .init("Env Roll", \.environmentRoll, -1.0...1.0),
        .init("Env Scale Y", \.environmentScaleY, 0.3...2.0),
        .init("Env Boost", \.environmentExposure, 0.2...24.0),
        .init("Env Blur", \.environmentBlur, 0.0...1.0),
        .init("Reflect", \.reflectionStrength, 0.0...2.5),
        .init("Studio Arc", \.studioArcStrength, 0.0...2.0),
        .init("Frost", \.frostAmount, 0.0...1.2),
        .init("Veil", \.veilStrength, 0.0...1.5),
        .init("Rim Light", \.rimLight, 0.0...2.0)
    ]

    private static let liquidEnvironmentRows: [BubbleSliderSpec] = [
        .init("Env Rotate", \.environmentRotation, -1.0...1.0),
        .init("Env Pitch", \.environmentPitch, -1.0...1.0),
        .init("Env Roll", \.environmentRoll, -1.0...1.0),
        .init("Env Scale Y", \.environmentScaleY, 0.3...2.0),
        .init("Env Boost", \.environmentExposure, 0.2...24.0),
        .init("Reflect", \.reflectionStrength, 0.0...2.5),
        .init("Env Blur", \.environmentBlur, 0.0...1.0),
        .init("Studio Arc", \.studioArcStrength, 0.0...2.0),
        .init("Frost", \.frostAmount, 0.0...1.2),
        .init("Veil", \.veilStrength, 0.0...1.5),
        .init("Rim Shine", \.rimLight, 0.0...2.0)
    ]

    private static let motionRows: [BubbleSliderSpec] = [
        .init("Flow", \.wobble, 0.0...1.5),
        .init("Drift", \.driftAmount, 0.0...1.5),
        .init("Morph", \.shapeMorph, 0.0...1.4),
        .init("Iridescence Speed", \.iridescenceSpeed, 0.0...2.2),
        .init("Highlight Travel", \.highlightTravel, 0.0...1.6),
        .init("Speed", \.motionSpeed, 0.2...2.0)
    ]
}
