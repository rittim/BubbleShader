#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>

using namespace metal;

// MARK: - Function Constants

constant bool showcaseUseGlass [[function_constant(0)]];

// MARK: - Shared Math Helpers

static inline float3 iridescence(float t) {
    return 0.5 + 0.5 * cos(6.2831853 * (float3(0.0, 0.18, 0.34) + t));
}

static inline float ellipseGlow(float2 point, float2 center, float2 radius, float rotation, float softness) {
    float s = sin(rotation);
    float c = cos(rotation);
    float2 shifted = point - center;
    float2 rotated = float2(
        shifted.x * c - shifted.y * s,
        shifted.x * s + shifted.y * c
    );
    float2 normalized = rotated / max(radius, float2(0.0001));
    float ellipse = dot(normalized, normalized);
    return exp(-ellipse * softness);
}

static inline float bubbleLuminance(float3 color) {
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

static inline float3 bubbleBrightPass(float3 color, float threshold) {
    float value = bubbleLuminance(color);
    float weight = smoothstep(threshold, 1.0, value);
    return color * (weight * value);
}

static inline float2 equirectangularUV(float3 direction, float verticalScale) {
    float3 dir = normalize(direction);
    float u = atan2(dir.z, dir.x) * 0.15915494309 + 0.5;
    float v = acos(clamp(dir.y, -1.0, 1.0)) * 0.31830988618;
    float scaledV = (v - 0.5) * max(verticalScale, 0.001) + 0.5;
    return float2(fract(u), clamp(scaledV, 0.001, 0.999));
}

static inline float3 rotateYDirection(float3 direction, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float3(
        direction.x * c - direction.z * s,
        direction.y,
        direction.x * s + direction.z * c
    );
}

static inline float3 rotateXDirection(float3 direction, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float3(
        direction.x,
        direction.y * c - direction.z * s,
        direction.y * s + direction.z * c
    );
}

static inline float3 rotateZDirection(float3 direction, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float3(
        direction.x * c - direction.y * s,
        direction.x * s + direction.y * c,
        direction.z
    );
}

static inline float3 sampleEnvironmentFiltered(
    texture2d<half> environmentMap,
    sampler environmentSampler,
    float3 direction,
    float rotationY,
    float rotationX,
    float rotationZ,
    float verticalScale,
    float blur
) {
    float3 dir = normalize(rotateZDirection(rotateXDirection(rotateYDirection(direction, rotationY), rotationX), rotationZ));
    float maxMip = max(float(environmentMap.get_num_mip_levels()) - 1.0, 0.0);
    // Even "zero blur" needs a small mip floor because reflected 2:1 maps are minified by sphere curvature.
    float antiAliasMipFloor = min(maxMip, 1.5);
    float mipLevel = clamp(mix(antiAliasMipFloor, maxMip, clamp(blur, 0.0, 1.0)), 0.0, maxMip);
    return float3(environmentMap.sample(environmentSampler, equirectangularUV(dir, verticalScale), level(mipLevel)).rgb);
}

// MARK: - SwiftUI Layer Shader

[[ stitchable ]] half4 bubbleGlass(
    float2 position,
    SwiftUI::Layer layer,
    float4 bounds,
    float time,
    float refraction,
    float chroma,
    float lens,
    float wobble,
    float glow,
    float flareStrength,
    float edgeDistort,
    float shapeMorph
) {
    float2 size = bounds.zw;
    float2 uv = (position - bounds.xy) / size;
    float2 centered = uv * 2.0 - 1.0;
    float radius = length(centered);
    float angle = atan2(centered.y, centered.x);
    float silhouetteWarp =
        0.985
        + shapeMorph * 0.010 * sin(angle * 2.0 + time * 0.48 + 0.35)
        + shapeMorph * 0.008 * cos(angle * 3.0 - time * 0.34 - 0.8)
        + shapeMorph * 0.005 * sin(angle * 5.0 + time * 0.28 + 1.1);
    float warpedRadius = radius / max(silhouetteWarp, 0.001);

    if (warpedRadius >= 1.0) {
        return half4(0.0);
    }

    float edge = clamp(warpedRadius, 0.0, 1.0);
    float sphereZ = sqrt(max(0.0001, 1.0 - edge * edge));
    float3 normal = normalize(float3(centered, sphereZ));
    float rimMask = smoothstep(0.48, 1.0, edge);
    float centerMask = 1.0 - rimMask;
    float shellMask = smoothstep(0.64, 0.985, edge);
    float shellBand = smoothstep(0.70, 0.92, edge) * (1.0 - smoothstep(0.90, 0.995, edge));

    float swirlA = sin(time * 0.34 + centered.y * 3.2 + centered.x * 1.6);
    float swirlB = cos(time * 0.28 - centered.x * 2.8 + centered.y * 2.1);
    float2 innerFlow = float2(swirlA, swirlB) * wobble * (0.0004 + 0.0014 * centerMask);

    float radialScale = 0.485 - lens * (0.055 * centerMask + 0.01 * rimMask);
    float edgeRefraction = 0.35 + edgeDistort * 0.85;
    float2 centerBulge = centered * centerMask * (0.008 + lens * 0.045);
    float2 bulge = normal.xy * refraction * (0.010 + 0.012 * centerMask + 0.014 * rimMask + 0.016 * rimMask * rimMask * edgeRefraction);
    float2 edgeDir = radius > 0.0001 ? centered / radius : float2(0.0, -1.0);
    float2 edgePull = edgeDir * lens * shellMask * (0.012 + 0.020 * edgeDistort);
    float3 viewDir = float3(0.0, 0.0, -1.0);
    float3 refracted = refract(viewDir, normal, 1.0 / 1.12);
    float2 prismFlow = refracted.xy * (0.004 + shellBand * 0.010) * (0.65 + refraction * 0.35);
    float2 baseUV = 0.5 + centered * radialScale - centerBulge - bulge - edgePull - prismFlow + innerFlow;
    baseUV = clamp(baseUV, float2(0.02), float2(0.98));

    float fresnel = pow(1.0 - max(normal.z, 0.0), 4.1);

    float dispersionMask = pow(rimMask, 2.1);
    float chromaAmount = chroma * (0.0012 + (0.0048 + 0.0058 * edgeDistort) * dispersionMask + shellBand * 0.004);
    float2 chromaDirection = edgeDir + refracted.xy * 0.34;
    chromaDirection = normalize(chromaDirection + float2(0.0001, 0.0));
    float2 chromaOffset = chromaDirection * chromaAmount;
    float2 greenOffset = refracted.xy * chroma * (0.0003 + shellBand * 0.0014);

    float2 redUV = clamp(baseUV + chromaOffset * 1.18, float2(0.02), float2(0.98));
    float2 greenUV = clamp(baseUV + greenOffset, float2(0.02), float2(0.98));
    float2 blueUV = clamp(baseUV - chromaOffset * 0.92, float2(0.02), float2(0.98));

    float2 redPos = bounds.xy + redUV * size;
    float2 greenPos = bounds.xy + greenUV * size;
    float2 bluePos = bounds.xy + blueUV * size;

    half4 redSample = layer.sample(redPos);
    half4 greenSample = layer.sample(greenPos);
    half4 blueSample = layer.sample(bluePos);

    float3 color = float3(redSample.r, greenSample.g, blueSample.b);
    color = mix(float3(greenSample.rgb), color, 0.76);

    float centerLift = centerMask * 0.05;
    float thickness = smoothstep(0.22, 0.98, edge);

    float keyLight = pow(max(dot(normal, normalize(float3(-0.52, 0.68, 0.52))), 0.0), 32.0);
    float fillLight = pow(max(dot(normal, normalize(float3(0.8, -0.08, 0.6))), 0.0), 20.0) * 0.16;
    float backSheen = pow(max(dot(normal, normalize(float3(0.0, -0.94, 0.32))), 0.0), 18.0) * 0.14;

    float3 film = iridescence(edge * 0.35 + time * 0.02) * fresnel * (0.18 + glow * 0.03);
    float3 edgeFilm = iridescence(edge * 0.92 + time * 0.03 + 0.2) * shellBand * (0.12 + chroma * 0.05);
    float edgeCaustic = pow(rimMask, 3.0) * (0.08 + 0.12 * glow);
    float chromaFringe = pow(shellBand, 1.2) * (0.05 + glow * 0.04);
    float flareStreak = ellipseGlow(centered, float2(-0.12, -0.34), float2(0.84, 0.08), -0.24, 2.4);
    float flareGhost = ellipseGlow(centered, float2(0.34, 0.02), float2(0.18, 0.07), -0.20, 4.0);
    float flareOrb = ellipseGlow(centered, float2(0.48, 0.24), float2(0.12, 0.12), 0.0, 5.8);
    float3 flareColorA = float3(0.30, 0.27, 0.22);
    float3 flareColorB = float3(0.16, 0.11, 0.24);
    float3 flareColorC = float3(0.10, 0.16, 0.26);
    float flareAmount = flareStrength * (0.10 + glow * 0.08 + chroma * 0.03);

    color *= 0.98 + centerLift;
    color *= 1.0 - thickness * 0.022;
    color *= 1.0 - shellMask * 0.19;
    color += film;
    color += edgeFilm;
    color += iridescence(edge * 1.12 + time * 0.05 + 0.4) * edgeCaustic;
    color += chromaFringe * float3(0.16, 0.05, 0.20);
    color += flareStreak * flareColorA * flareAmount;
    color += flareGhost * flareColorB * (flareAmount * 0.82);
    color += flareOrb * flareColorC * (flareAmount * 0.68);
    color += keyLight * float3(0.2, 0.2, 0.2);
    color += fillLight * float3(0.08, 0.12, 0.18);
    color += backSheen * float3(0.05, 0.07, 0.10);
    color += fresnel * glow * 0.05;

    float bubbleShadow = smoothstep(0.74, 1.0, edge) * 0.06;
    color -= bubbleShadow;

    float alpha = 1.0 - smoothstep(0.965, 1.0, edge);
    return half4(half3(clamp(color, 0.0, 1.0)), half(alpha));
}

// MARK: - Showcase Pipeline Data

struct ShowcaseBubbleVertex {
    float2 position;
    float2 uv;
};

struct ShowcaseBubbleFrameUniforms {
    float4 viewportAndTime;
};

struct ShowcaseBubbleMaterialUniforms {
    float4 opticsA;
    float4 opticsB;
    float4 opticsC;
    float4 grading;
    float4 animation;
    float4 surfaceModel;
    float4 glassA;
    float4 glassB;
    float4 flareColor;
    float4 surfaceTint;
    float4 artworkShadow;
    float4 artworkAccent;
    float4 artworkHaze;
    float4 artworkSun;
};

struct ShowcaseBubbleVertexOut {
    float4 position [[position]];
    float2 uv;
    float2 local;
};

// MARK: - Vertex Shader

vertex ShowcaseBubbleVertexOut showcaseBubbleVertex(
    const device ShowcaseBubbleVertex *vertices [[buffer(0)]],
    uint vertexID [[vertex_id]]
) {
    ShowcaseBubbleVertex quadVertex = vertices[vertexID];

    ShowcaseBubbleVertexOut out;
    out.position = float4(quadVertex.position, 0.0, 1.0);
    out.uv = quadVertex.uv;
    out.local = quadVertex.position;
    return out;
}

// MARK: - Fragment Shader

fragment half4 showcaseBubbleFragment(
    ShowcaseBubbleVertexOut in [[stage_in]],
    constant ShowcaseBubbleFrameUniforms &frame [[buffer(1)]],
    constant ShowcaseBubbleMaterialUniforms &material [[buffer(2)]],
    texture2d<half> portrait [[texture(0)]],
    texture2d<half> environmentMap [[texture(1)]],
    sampler portraitSampler [[sampler(0)]]
) {
    float time = frame.viewportAndTime.z;
    float2 centered = in.local;
    float radius = length(centered);
    float angle = atan2(centered.y, centered.x);

    float refraction = material.opticsA.x;
    float chroma = material.opticsA.y;
    float lens = material.opticsA.z;
    float wobble = material.opticsA.w;
    float glow = material.opticsB.x;
    float flareStrength = material.opticsB.y;
    float edgeDistort = material.opticsB.z;
    float shapeMorph = material.opticsB.w;
    float rimStrength = material.opticsC.x;
    float highlightStrength = material.opticsC.y;
    float driftAmount = material.opticsC.z;
    float imageScale = material.opticsC.w;
    float exposure = material.grading.x;
    float imageShadowStrength = material.grading.y;
    float shellDimStrength = material.grading.z;
    float rimShadowStrength = material.grading.w;
    float iridescenceAmount = material.animation.x;
    float iridescenceSpeed = material.animation.y;
    float highlightTravel = material.animation.z;
    float bloomRadiusScale = material.animation.w;
    float liquidGlass = showcaseUseGlass ? 1.0 : 0.0;
    float envRoll = material.surfaceModel.x * 3.14159265;
    float envRotation = material.surfaceModel.y * 3.14159265;
    float reflectionStrength = material.surfaceModel.z;
    float environmentBlur = material.surfaceModel.w;
    float frostAmount = material.glassA.x;
    float rimLight = material.glassA.y;
    float refractionBlur = material.glassA.z;
    float envExposure = material.glassA.w;
    float veilStrength = material.glassB.x;
    float studioArcStrength = material.glassB.y;
    float envPitch = material.glassB.z * 1.57079633;
    float envScaleY = max(material.glassB.w, 0.001);
    float activeShapeMorph = mix(shapeMorph, shapeMorph * 0.18, liquidGlass);

    float silhouetteWarp =
        0.985
        + activeShapeMorph * 0.010 * sin(angle * 2.0 + time * 0.48 + 0.35)
        + activeShapeMorph * 0.008 * cos(angle * 3.0 - time * 0.34 - 0.8)
        + activeShapeMorph * 0.005 * sin(angle * 5.0 + time * 0.28 + 1.1);
    float warpedRadius = radius / max(silhouetteWarp, 0.001);

    if (warpedRadius >= 1.0) {
        return half4(0.0);
    }

    float edge = clamp(warpedRadius, 0.0, 1.0);
    float sphereZ = sqrt(max(0.0001, 1.0 - edge * edge));
    float3 normal = normalize(float3(centered, sphereZ));
    float rimMask = smoothstep(0.48, 1.0, edge);
    float centerMask = 1.0 - rimMask;
    float shellMask = smoothstep(0.64, 0.985, edge);
    float shellBand = smoothstep(0.70, 0.92, edge) * (1.0 - smoothstep(0.90, 0.995, edge));

    float swirlA = sin(time * 0.34 + centered.y * 3.2 + centered.x * 1.6);
    float swirlB = cos(time * 0.28 - centered.x * 2.8 + centered.y * 2.1);
    float2 innerFlow = float2(swirlA, swirlB) * wobble * (0.0004 + 0.0014 * centerMask);
    float2 portraitFlow = float2(
        sin(time * 0.34) * 0.010 + cos(time * 0.19 + 0.8) * 0.004,
        cos(time * 0.28 + 0.5) * 0.007 + sin(time * 0.16) * 0.003
    ) * driftAmount * 0.45;

    float radialScale = (0.485 / max(imageScale, 0.001)) - lens * (0.055 * centerMask + 0.010 * rimMask);
    float edgeRefraction = 0.35 + edgeDistort * 0.85;
    float2 centerBulge = centered * centerMask * (0.008 + lens * 0.045);
    float2 bulge = normal.xy * refraction * (0.010 + 0.012 * centerMask + 0.014 * rimMask + 0.016 * rimMask * rimMask * edgeRefraction);
    float2 edgeDir = radius > 0.0001 ? centered / radius : float2(0.0, -1.0);
    float2 edgePull = edgeDir * lens * shellMask * (0.012 + 0.020 * edgeDistort);
    float3 viewDir = float3(0.0, 0.0, -1.0);
    float3 refracted = refract(viewDir, normal, 1.0 / 1.12);
    float2 prismFlow = refracted.xy * (0.004 + shellBand * 0.010) * (0.65 + refraction * 0.35);
    float liquidRadialScale = (0.54 / max(imageScale, 0.001)) - lens * (0.090 * centerMask + 0.020 * rimMask);
    float2 liquidCenterBulge = centered * centerMask * (0.022 + lens * 0.082);
    float2 liquidBulge = normal.xy * refraction * (0.020 + 0.018 * centerMask + 0.028 * rimMask + 0.034 * rimMask * rimMask * edgeRefraction);
    float2 liquidEdgePull = edgeDir * shellMask * (0.015 + 0.018 * lens + 0.014 * edgeDistort);
    float2 liquidPrismFlow = refracted.xy * (0.008 + shellBand * 0.018) * (0.72 + refraction * 0.40);
    float2 liquidFlow = innerFlow * 0.08 + portraitFlow * 0.10;
    float2 bubbleBaseUV = 0.5 + centered * radialScale - centerBulge - bulge - edgePull - prismFlow + innerFlow + portraitFlow;
    float2 liquidBaseUV = 0.5 + centered * liquidRadialScale - liquidCenterBulge - liquidBulge - liquidEdgePull - liquidPrismFlow + liquidFlow;
    float2 baseUV = mix(bubbleBaseUV, liquidBaseUV, liquidGlass);
    baseUV = clamp(baseUV, float2(0.02), float2(0.98));

    float fresnel = pow(1.0 - max(normal.z, 0.0), 4.1);
    float dispersionMask = pow(rimMask, 2.1);
    float liquidDispersionMask = pow(rimMask, 3.8);
    float bubbleChromaAmount = chroma * (0.0012 + (0.0048 + 0.0058 * edgeDistort) * dispersionMask + shellBand * 0.004);
    float liquidChromaAmount = chroma * (0.0010 + 0.0062 * liquidDispersionMask + shellBand * 0.016 + edgeDistort * 0.0028);
    float2 chromaDirection = edgeDir + refracted.xy * 0.34;
    chromaDirection = normalize(chromaDirection + float2(0.0001, 0.0));
    float2 chromaOffset = chromaDirection * mix(bubbleChromaAmount, liquidChromaAmount, liquidGlass);
    float2 bubbleGreenOffset = refracted.xy * chroma * (0.0003 + shellBand * 0.0014);
    float2 liquidGreenOffset = refracted.xy * chroma * (0.00018 + shellBand * 0.0011);
    float2 greenOffset = mix(bubbleGreenOffset, liquidGreenOffset, liquidGlass);

    half4 redSample = portrait.sample(
        portraitSampler,
        clamp(baseUV + chromaOffset * 1.18, float2(0.02), float2(0.98))
    );
    half4 greenSample = portrait.sample(
        portraitSampler,
        clamp(baseUV + greenOffset, float2(0.02), float2(0.98))
    );
    half4 blueSample = portrait.sample(
        portraitSampler,
        clamp(baseUV - chromaOffset * 0.92, float2(0.02), float2(0.98))
    );
    float3 portraitBase = float3(portrait.sample(
        portraitSampler,
        clamp(baseUV, float2(0.02), float2(0.98))
    ).rgb);
    float glassBlurRadius = 0.004 + refractionBlur * 0.020;
    float2 glassBlurX = float2(glassBlurRadius, 0.0);
    float2 glassBlurY = float2(0.0, glassBlurRadius * 0.82);
    float3 portraitSoft =
        (
            portraitBase * 2.0
            + float3(portrait.sample(portraitSampler, clamp(baseUV + glassBlurX, float2(0.02), float2(0.98))).rgb)
            + float3(portrait.sample(portraitSampler, clamp(baseUV - glassBlurX, float2(0.02), float2(0.98))).rgb)
            + float3(portrait.sample(portraitSampler, clamp(baseUV + glassBlurY, float2(0.02), float2(0.98))).rgb)
            + float3(portrait.sample(portraitSampler, clamp(baseUV - glassBlurY, float2(0.02), float2(0.98))).rgb)
        ) / 6.0;

    float bloomRadius = (0.010 + glow * 0.015 + chroma * 0.004) * max(bloomRadiusScale, 0.001);
    float2 bloomOffsetX = float2(bloomRadius, 0.0);
    float2 bloomOffsetY = float2(0.0, bloomRadius * 0.82);
    float3 bloomSampleA = float3(portrait.sample(
        portraitSampler,
        clamp(baseUV + bloomOffsetX, float2(0.02), float2(0.98))
    ).rgb);
    float3 bloomSampleB = float3(portrait.sample(
        portraitSampler,
        clamp(baseUV - bloomOffsetX, float2(0.02), float2(0.98))
    ).rgb);
    float3 bloomSampleC = float3(portrait.sample(
        portraitSampler,
        clamp(baseUV + bloomOffsetY, float2(0.02), float2(0.98))
    ).rgb);
    float3 bloomSampleD = float3(portrait.sample(
        portraitSampler,
        clamp(baseUV - bloomOffsetY, float2(0.02), float2(0.98))
    ).rgb);

    float3 spectralColor = float3(redSample.r, greenSample.g, blueSample.b);
    float3 color = mix(float3(greenSample.rgb), spectralColor, 0.76);

    float3 portraitHighlights =
        bubbleBrightPass(portraitBase, 0.56) * 1.15
        + bubbleBrightPass(bloomSampleA, 0.60) * 0.55
        + bubbleBrightPass(bloomSampleB, 0.60) * 0.55
        + bubbleBrightPass(bloomSampleC, 0.62) * 0.42
        + bubbleBrightPass(bloomSampleD, 0.62) * 0.42;
    float portraitGlowEnergy = bubbleLuminance(portraitHighlights);
    float portraitGlowPresence = smoothstep(0.010, 0.120, portraitGlowEnergy);
    float3 imageGlowTint = clamp(portraitHighlights * 2.8, float3(0.0), float3(1.0));
    float3 shellGlowTint = mix(material.surfaceTint.rgb, imageGlowTint, portraitGlowPresence * 0.78);
    float3 flareGlowTint = mix(material.flareColor.rgb, imageGlowTint, portraitGlowPresence * 0.58);
    float3 hazeGlowTint = mix(material.artworkHaze.rgb, imageGlowTint, portraitGlowPresence * 0.52);

    float highlightShiftX = sin(time * 0.26 + 0.4) * 0.055 * highlightTravel;
    float highlightShiftY = cos(time * 0.21 + 0.9) * 0.040 * highlightTravel;
    float flareShiftX = cos(time * 0.18 + 1.1) * 0.065 * highlightTravel;
    float flareShiftY = sin(time * 0.23 + 0.2) * 0.048 * highlightTravel;

    float sunWash = ellipseGlow(centered, float2(-0.08 + highlightShiftX * 0.35, -0.24 + highlightShiftY * 0.25), float2(0.74, 0.46), -0.18, 2.1);
    float accentWash = ellipseGlow(centered, float2(0.22 - highlightShiftX * 0.22, 0.18 + highlightShiftY * 0.28), float2(0.48, 0.28), 0.24, 3.2);
    float hazeBand = ellipseGlow(centered, float2(0.08 + highlightShiftX * 0.18, 0.56 + highlightShiftY * 0.12), float2(0.76, 0.12), 0.05, 2.7);
    float bottomShadow = smoothstep(-0.04, 0.78, centered.y);

    float bubbleArtworkMix = 1.0 - liquidGlass;
    float bubbleTopLight = rimStrength * bubbleArtworkMix;
    color += material.artworkSun.rgb * (sunWash * 0.13 * bubbleTopLight);
    color += material.artworkAccent.rgb * (accentWash * 0.06 * bubbleTopLight);
    color += material.artworkHaze.rgb * (hazeBand * 0.08 * bubbleTopLight);
    color -= material.artworkShadow.rgb * (bottomShadow * 0.09 * imageShadowStrength * bubbleArtworkMix);

    float centerLift = centerMask * 0.05;
    float thickness = smoothstep(0.22, 0.98, edge);
    float keyLight = pow(max(dot(normal, normalize(float3(-0.52, 0.68, 0.52))), 0.0), 32.0);
    float fillLight = pow(max(dot(normal, normalize(float3(0.8, -0.08, 0.6))), 0.0), 20.0) * 0.16;
    float backSheen = pow(max(dot(normal, normalize(float3(0.0, -0.94, 0.32))), 0.0), 18.0) * 0.14;
    float3 reflectionVector = reflect(viewDir, normal);
    float3 envPrimary = sampleEnvironmentFiltered(environmentMap, portraitSampler, reflectionVector, envRotation, envPitch, envRoll, envScaleY, environmentBlur);
    float3 envSoft = sampleEnvironmentFiltered(environmentMap, portraitSampler, reflectionVector, envRotation, envPitch, envRoll, envScaleY, min(environmentBlur + 0.38, 1.0));
    float3 environmentRaw = mix(envPrimary, envSoft, clamp(environmentBlur * 0.42, 0.0, 0.42));
    float3 environmentBoosted = max(environmentRaw * max(envExposure, 0.0), float3(0.0));
    float rawEnvironmentLuma = bubbleLuminance(environmentBoosted);
    float environmentContrast = clamp(
        length(envPrimary - envSoft) * 2.8 + abs(bubbleLuminance(envPrimary) - bubbleLuminance(envSoft)) * 1.6,
        0.0,
        1.0
    );
    float whiteMapDamping = mix(0.32, 1.0, environmentContrast);
    float environmentHighlightMask = smoothstep(0.42, 1.55, rawEnvironmentLuma) * environmentContrast;
    float3 environmentTone = environmentBoosted / (1.0 + environmentBoosted);
    float environmentToneLuma = bubbleLuminance(environmentTone);
    float3 environmentSpecular = mix(environmentTone, float3(environmentToneLuma), 0.42);
    environmentSpecular = mix(environmentSpecular, float3(1.0), environmentHighlightMask * 0.44);
    float3 environmentField = mix(environmentTone * 0.72, float3(environmentToneLuma), 0.36);
    float envPostToneGain = max(envExposure - 3.5, 0.0);
    environmentSpecular *= whiteMapDamping * (1.0 + envPostToneGain * 0.35);
    environmentField *= whiteMapDamping * (1.0 + envPostToneGain * 0.20);

    float iridescenceTimeA = time * (0.02 * iridescenceSpeed);
    float iridescenceTimeB = time * (0.03 * iridescenceSpeed);
    float iridescenceTimeC = time * (0.05 * iridescenceSpeed);
    float3 film = iridescence(edge * 0.35 + iridescenceTimeA) * fresnel * (0.18 + glow * 0.03) * iridescenceAmount;
    float3 edgeFilm = iridescence(edge * 0.92 + iridescenceTimeB + 0.2) * shellBand * (0.12 + chroma * 0.05) * iridescenceAmount;
    float edgeCaustic = pow(rimMask, 3.0) * (0.08 + 0.12 * glow);
    float chromaFringe = pow(shellBand, 1.2) * (0.05 + glow * 0.04);
    float flareStreak = ellipseGlow(centered, float2(-0.12 + flareShiftX, -0.34 + flareShiftY * 0.35), float2(0.84, 0.08), -0.24, 2.4);
    float flareGhost = ellipseGlow(centered, float2(0.34 - flareShiftX * 0.42, 0.02 + flareShiftY * 0.22), float2(0.18, 0.07), -0.20, 4.0);
    float flareOrb = ellipseGlow(centered, float2(0.48 - flareShiftX * 0.30, 0.24 - flareShiftY * 0.20), float2(0.12, 0.12), 0.0, 5.8);

    float3 flareColorA = mix(float3(0.30, 0.27, 0.22), material.flareColor.rgb, 0.52);
    float3 flareColorB = mix(float3(0.16, 0.11, 0.24), material.surfaceTint.rgb, 0.42);
    float3 flareColorC = mix(float3(0.10, 0.16, 0.26), material.artworkAccent.rgb, 0.35);
    float flareAmount = flareStrength * (0.10 + glow * 0.08 + chroma * 0.03);

    float highlightA = ellipseGlow(centered, float2(-0.16 + highlightShiftX, -0.46 + highlightShiftY), float2(0.48, 0.14), -0.26, 4.7);
    float highlightB = ellipseGlow(centered, float2(0.28 - highlightShiftX * 0.58, 0.10 + highlightShiftY * 0.62), float2(0.12, 0.24), 0.22, 5.6);
    float lowerGlow = ellipseGlow(centered, float2(0.20 + highlightShiftX * 0.34, 0.34 + highlightShiftY * 0.30), float2(0.42, 0.10), 0.08, 3.1);
    float bubbleShadow = smoothstep(0.74, 1.0, edge) * (0.06 * rimShadowStrength);
    float upperHemisphere = 1.0 - smoothstep(-0.22, 0.72, centered.y);
    float frontHemisphere = smoothstep(0.08, 0.86, centerMask);
    float heroWindowArc = ellipseGlow(centered, float2(-0.16, -0.46), float2(0.92, 0.19), -0.32, 1.42);
    float heroReflectionMask = clamp(
        frontHemisphere * (0.045 + upperHemisphere * 0.18)
        + fresnel * 0.16
        + shellBand * 0.08,
        0.0,
        1.0
    );

    if (liquidGlass > 0.5) {
        float3 liquidTint = mix(float3(1.0), material.surfaceTint.rgb, 0.04);
        float liquidFresnel = pow(fresnel, 0.72);
        float liquidSpecular = pow(max(dot(normal, normalize(float3(-0.42, 0.78, 0.46))), 0.0), 58.0);
        float liquidBackSpec = pow(max(dot(normal, normalize(float3(0.36, -0.08, 0.93))), 0.0), 22.0) * 0.16;
        float rimRing = smoothstep(0.68, 0.95, edge) * (1.0 - smoothstep(0.962, 0.998, edge));
        float edgeGlowBand = smoothstep(0.56, 0.86, edge) * (1.0 - smoothstep(0.90, 0.995, edge));
        float upperArc = ellipseGlow(centered, float2(-0.16 + highlightShiftX * 0.18, -0.48 + highlightShiftY * 0.12), float2(0.96, 0.24), -0.34, 1.34);
        float midArc = ellipseGlow(centered, float2(-0.26 + highlightShiftX * 0.08, -0.04 + highlightShiftY * 0.06), float2(0.92, 0.10), -0.08, 2.10);
        float lowerArc = ellipseGlow(centered, float2(0.00, 0.60), float2(0.82, 0.15), 0.02, 1.84);
        float sideArc = ellipseGlow(centered, float2(-0.78, 0.02), float2(0.18, 0.92), 0.04, 2.80);
        float frontCloud = ellipseGlow(centered, float2(-0.08, 0.12), float2(0.86, 0.42), -0.10, 1.28) * centerMask;
        float undersideFog = ellipseGlow(centered, float2(0.06, 0.70), float2(0.70, 0.18), 0.02, 1.72);
        float studioArcMask = clamp(upperArc * 0.92 + midArc * 0.32 + lowerArc * 0.18 + sideArc * 0.16, 0.0, 1.0) * studioArcStrength;
        float veilMask = clamp(frontCloud * 0.60 + midArc * 0.18 + undersideFog * 0.38, 0.0, 1.0) * veilStrength;
        float frostMask = clamp(midArc * 0.54 + lowerArc * 0.48 + undersideFog * 0.46 + frontCloud * 0.24, 0.0, 1.0) * frostAmount;
        float edgeDepthMask = rimRing * 0.070 + edgeGlowBand * 0.026;
        float reflectionMask = clamp(
            liquidFresnel * 0.24
            + heroReflectionMask * 0.46
            + rimRing * (0.11 + rimLight * 0.20)
            + studioArcMask * 0.86,
            0.0,
            1.0
        );
        float portraitSharpness = clamp(0.78 - refractionBlur * 0.26 - frostAmount * 0.08, 0.36, 0.90);
        float centerSharpness = clamp(portraitSharpness + centerMask * 0.16, 0.0, 1.0);
        float3 liquidPortrait = mix(portraitSoft, portraitBase, centerSharpness);
        float3 spectralFringe = clamp(abs(spectralColor - portraitBase) * 5.4, float3(0.0), float3(1.0));
        float chromaArcMask = clamp(upperArc * 0.72 + rimRing * 0.52 + edgeGlowBand * 0.30, 0.0, 1.0) * smoothstep(0.03, 0.24, chroma);

        color = liquidPortrait;
        color = mix(color, portraitSoft, veilMask * (0.14 + veilStrength * 0.16));
        color *= 1.01 + centerMask * 0.06;
        color *= 1.0 - thickness * (0.004 + shellDimStrength * 0.010);
        color *= 1.0 - shellMask * (0.010 + shellDimStrength * 0.020);
        color *= 1.0 - edgeDepthMask * (0.40 + shellDimStrength * 0.24);
        color -= bubbleShadow * 0.16;
        color += environmentField * reflectionStrength * (heroReflectionMask * 0.34 + liquidFresnel * 0.18 + edgeGlowBand * (0.020 + rimStrength * 0.085));
        color += environmentSpecular * reflectionStrength * reflectionMask;
        color += environmentSpecular * reflectionStrength * studioArcMask * 0.32;
        color += portraitHighlights * 0.02;
        color += float3(1.0) * studioArcMask * (rimLight * 0.08);
        color += float3(1.0) * veilMask * (veilStrength * 0.06);
        color += float3(1.0) * frostMask * (frostAmount * 0.08);
        color += float3(1.0) * rimRing * (rimLight * 0.18);
        color += edgeGlowBand * liquidTint * (rimStrength * 0.05);
        color += spectralFringe * chromaArcMask * (0.04 + chroma * 0.26);
        color += liquidSpecular * float3(0.26, 0.27, 0.29) * highlightStrength;
        color += liquidBackSpec * float3(0.10, 0.11, 0.13);
        color += upperArc * float3(1.0) * (studioArcStrength * 0.08);
        color += heroWindowArc * environmentSpecular * reflectionStrength * (0.08 + studioArcStrength * 0.16);
        color += lowerArc * environmentField * (reflectionStrength * 0.06);
        color += sideArc * float3(1.0) * (studioArcStrength * 0.02);
    } else {
        float bubbleShell = smoothstep(0.38, 0.98, edge);
        // Snow-globe depth comes from the image itself as much as from highlights:
        // sample a vertically flipped, softened copy and bleed it through the shell.
        float2 flippedUV = clamp(
            float2(baseUV.x, 1.0 - baseUV.y) + edgeDir * shellMask * (0.010 + lens * 0.012),
            float2(0.02),
            float2(0.98)
        );
        float flippedBlurRadius = (0.016 + shellDimStrength * 0.012 + lens * 0.006) * max(bloomRadiusScale, 0.001);
        float2 flippedBlurX = float2(flippedBlurRadius, 0.0);
        float2 flippedBlurY = float2(0.0, flippedBlurRadius * 0.82);
        float3 flippedBleed =
            (
                float3(portrait.sample(portraitSampler, flippedUV).rgb) * 2.0
                + float3(portrait.sample(portraitSampler, clamp(flippedUV + flippedBlurX, float2(0.02), float2(0.98))).rgb)
                + float3(portrait.sample(portraitSampler, clamp(flippedUV - flippedBlurX, float2(0.02), float2(0.98))).rgb)
                + float3(portrait.sample(portraitSampler, clamp(flippedUV + flippedBlurY, float2(0.02), float2(0.98))).rgb)
                + float3(portrait.sample(portraitSampler, clamp(flippedUV - flippedBlurY, float2(0.02), float2(0.98))).rgb)
            ) / 6.0;
        float flippedBleedMask = clamp(pow(fresnel, 0.82) * 0.60 + shellBand * 0.50 + bubbleShell * 0.10, 0.0, 1.0);
        float milkyShell = clamp(
            pow(fresnel, 0.62) * 0.46
            + shellBand * 0.26
            + heroWindowArc * (0.18 + studioArcStrength * 0.18)
            + upperHemisphere * rimMask * 0.12,
            0.0,
            1.0
        );
        float edgeLip = smoothstep(0.68, 0.97, edge) * (1.0 - smoothstep(0.955, 0.998, edge));
        float outerBloom = smoothstep(0.80, 0.99, edge);
        float3 shellWhite = mix(float3(0.92, 0.98, 1.0), shellGlowTint, 0.16);

        color *= 0.98 + centerLift;
        color *= 1.0 - thickness * (0.022 * shellDimStrength);
        color *= 1.0 - shellMask * (0.19 * shellDimStrength);
        color = mix(color, portraitSoft, bubbleShell * (0.08 + shellDimStrength * 0.08));
        color = mix(color, flippedBleed, flippedBleedMask * (0.18 + shellDimStrength * 0.18 + rimStrength * 0.08));
        color = mix(color, shellWhite, milkyShell * (0.20 + shellDimStrength * 0.16));
        color += portraitHighlights * (0.14 + glow * 0.06) * (0.55 + centerMask * 0.45);
        color += bubbleBrightPass(flippedBleed, 0.46) * flippedBleedMask * (0.18 + glow * 0.06);
        color += film * mix(float3(1.0), shellGlowTint, 0.24);
        color += edgeFilm * mix(shellGlowTint, flareGlowTint, 0.26);
        color += iridescence(edge * 1.12 + iridescenceTimeC + 0.4) * edgeCaustic * mix(float3(1.0), shellGlowTint, 0.18) * iridescenceAmount;
        color += chromaFringe * mix(float3(0.16, 0.05, 0.20), flareGlowTint, 0.35);
        color += flareStreak * flareColorA * flareAmount;
        color += flareGhost * flareColorB * (flareAmount * 0.82);
        color += flareOrb * flareColorC * (flareAmount * 0.68);
        color += keyLight * float3(0.2, 0.2, 0.2) * highlightStrength;
        color += fillLight * float3(0.08, 0.12, 0.18);
        color += backSheen * float3(0.05, 0.07, 0.10);
        color += environmentField * reflectionStrength * (heroReflectionMask * 0.42 + fresnel * 0.10);
        color += environmentSpecular * reflectionStrength * (heroWindowArc * (0.16 + studioArcStrength * 0.18) + shellBand * 0.10);
        color += shellWhite * edgeLip * (0.22 + rimStrength * 0.26 + highlightStrength * 0.08);
        color += shellWhite * heroWindowArc * (0.08 + rimStrength * 0.10 + highlightStrength * 0.12);
        color += shellGlowTint * outerBloom * (0.04 + glow * 0.05 + iridescenceAmount * 0.04);
        color += highlightA * mix(float3(0.28, 0.31, 0.32), shellGlowTint, 0.25) * highlightStrength;
        color += highlightB * mix(float3(0.18, 0.22, 0.26), flareGlowTint, 0.22) * (0.84 + glow * 0.24) * highlightStrength;
        color += lowerGlow * mix(float3(0.12, 0.16, 0.22), hazeGlowTint, 0.24) * (0.72 + glow * 0.20) * highlightStrength;
        color += fresnel * glow * 0.05;
        color -= bubbleShadow;
    }

    color *= exposure;

    float bubbleAlpha = 1.0 - smoothstep(0.965, 1.0, edge);
    float liquidAlpha = 1.0 - smoothstep(0.993, 1.0, edge);
    float alpha = mix(bubbleAlpha, liquidAlpha, liquidGlass);
    return half4(half3(clamp(color, 0.0, 1.0)), half(alpha));
}
