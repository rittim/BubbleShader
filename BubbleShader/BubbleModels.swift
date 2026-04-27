import SwiftUI

// MARK: - Material Selection

enum BubbleMaterialStyle: String, CaseIterable, Identifiable {
    case bubble
    case liquidGlass
    case glass

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bubble:
            "Bubble"
        case .liquidGlass:
            "Liquid"
        case .glass:
            "Glass"
        }
    }
}

// MARK: - Visual Preset

enum BubblePreset: Equatable {
    case standard

    var flareColor: Color {
        bubbleColor(255, 136, 63)
    }

    var artworkSun: Color {
        bubbleColor(255, 214, 161)
    }

    var artworkHaze: Color {
        bubbleColor(255, 169, 102)
    }

    var artworkShadow: Color {
        bubbleColor(18, 20, 29)
    }

    var artworkAccent: Color {
        bubbleColor(93, 130, 221)
    }

    var surfaceTint: Color {
        bubbleColor(158, 215, 255)
    }

    var refraction: Float {
        1.0
    }

    var chromaticSpread: Float {
        1.0
    }

    var lensAmount: Float {
        0.8
    }

    var wobble: Float {
        0.7
    }

    var glowStrength: Float {
        0.74
    }
}

// MARK: - Control Tabs

enum BubbleControlTab: Hashable {
    case visual
    case motion
    case glass

    var label: String {
        label(for: nil)
    }

    func label(for materialStyle: BubbleMaterialStyle?) -> String {
        switch self {
        case .visual:
            "Visual"
        case .motion:
            "Motion"
        case .glass:
            materialStyle == .bubble ? "Map" : "Glass"
        }
    }
}

// MARK: - Shader Controls

struct BubbleControls: Equatable {
    var refraction: Double
    var chromaticSpread: Double
    var lensAmount: Double
    var edgeDistortion: Double
    var wobble: Double
    var glowStrength: Double
    var flareStrength: Double
    var rimStrength: Double
    var highlightStrength: Double
    var iridescenceAmount: Double
    var iridescenceSpeed: Double
    var highlightTravel: Double
    var bloomRadius: Double
    var exposure: Double
    var imageShadowStrength: Double
    var shellDimStrength: Double
    var rimShadowStrength: Double
    var driftAmount: Double
    var shapeMorph: Double
    var motionSpeed: Double
    var environmentRotation: Double
    var environmentPitch: Double
    var environmentRoll: Double
    var environmentScaleY: Double
    var environmentExposure: Double
    var reflectionStrength: Double
    var environmentBlur: Double
    var studioArcStrength: Double
    var frostAmount: Double
    var veilStrength: Double
    var rimLight: Double
    var refractionBlur: Double

    // These defaults are tuned for the bundled portrait and environment map.
    init(style: BubbleMaterialStyle, preset: BubblePreset) {
        switch style {
        case .bubble:
            refraction = 0.70
            chromaticSpread = 1.89
            lensAmount = 0.50
            edgeDistortion = 0.0
            wobble = 0.70
            glowStrength = 0.34
            flareStrength = 0.0
            rimStrength = 0.58
            highlightStrength = 0.42
            iridescenceAmount = 0.32
            iridescenceSpeed = 1.80
            highlightTravel = 1.23
            bloomRadius = 0.97
            exposure = 0.98
            imageShadowStrength = 0.50
            shellDimStrength = 0.58
            rimShadowStrength = 0.49
            driftAmount = 1.0
            shapeMorph = 1.39
            motionSpeed = 1.94
            environmentRotation = 0.0
            environmentPitch = 0.0
            environmentRoll = 0.0
            environmentScaleY = 1.0
            environmentExposure = 2.0
            reflectionStrength = 0.32
            environmentBlur = 0.26
            studioArcStrength = 0.62
            frostAmount = 0.0
            veilStrength = 0.0
            rimLight = 1.0
            refractionBlur = 0.0

        case .liquidGlass:
            refraction = 0.97
            chromaticSpread = 2.14
            lensAmount = 0.20
            edgeDistortion = 0.23
            wobble = 0.008
            glowStrength = 0.03
            flareStrength = 0.02
            rimStrength = 1.18
            highlightStrength = 0.0
            iridescenceAmount = 0.0
            iridescenceSpeed = 0.0
            highlightTravel = 0.04
            bloomRadius = 1.0
            exposure = 1.12
            imageShadowStrength = 0.56
            shellDimStrength = 0.75
            rimShadowStrength = 1.01
            driftAmount = 0.01
            shapeMorph = 0.02
            motionSpeed = 0.24
            environmentRotation = -0.26
            environmentPitch = 0.41
            environmentRoll = -0.41
            environmentScaleY = 1.47
            environmentExposure = 10.98
            reflectionStrength = 2.5
            environmentBlur = 0.52
            studioArcStrength = 0.0
            frostAmount = 0.0
            veilStrength = 0.0
            rimLight = 2.0
            refractionBlur = 0.25

        case .glass:
            refraction = 0.75
            chromaticSpread = 1.91
            lensAmount = 0.35
            edgeDistortion = 2.20
            wobble = 1.5
            glowStrength = 0.555
            flareStrength = 1.24
            rimStrength = 0.0
            highlightStrength = 0.0
            iridescenceAmount = 0.61
            iridescenceSpeed = 1.268
            highlightTravel = 0.7
            bloomRadius = 1.0
            exposure = 1.12
            imageShadowStrength = 0.56
            shellDimStrength = 0.97
            rimShadowStrength = 1.48
            driftAmount = 1.5
            shapeMorph = 1.4
            motionSpeed = 1.0
            environmentRotation = -0.26
            environmentPitch = 0.41
            environmentRoll = -0.41
            environmentScaleY = 1.47
            environmentExposure = 10.98
            reflectionStrength = 0.44
            environmentBlur = 0.52
            studioArcStrength = 0.0
            frostAmount = 0.0
            veilStrength = 0.0
            rimLight = 0.09
            refractionBlur = 0.25
        }
    }
}

// MARK: - Color Helpers

private func bubbleColor(_ red: Double, _ green: Double, _ blue: Double) -> Color {
    Color(red: red / 255, green: green / 255, blue: blue / 255)
}
