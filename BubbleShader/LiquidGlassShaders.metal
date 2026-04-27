#include <metal_stdlib>

using namespace metal;

// MARK: - Shared Math Helpers

static inline float liquidGlassLuminance(float3 color) {
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

static inline float2 liquidGlassEquirectangularUV(float3 direction, float verticalScale) {
    float3 dir = normalize(direction);
    float u = atan2(dir.z, dir.x) * 0.15915494309 + 0.5;
    float v = acos(clamp(dir.y, -1.0, 1.0)) * 0.31830988618;
    float scaledV = (v - 0.5) * max(verticalScale, 0.001) + 0.5;
    return float2(fract(u), clamp(scaledV, 0.001, 0.999));
}

static inline float3 liquidGlassRotateY(float3 direction, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float3(
        direction.x * c - direction.z * s,
        direction.y,
        direction.x * s + direction.z * c
    );
}

static inline float3 liquidGlassRotateX(float3 direction, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float3(
        direction.x,
        direction.y * c - direction.z * s,
        direction.y * s + direction.z * c
    );
}

static inline float3 liquidGlassRotateZ(float3 direction, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float3(
        direction.x * c - direction.y * s,
        direction.x * s + direction.y * c,
        direction.z
    );
}

static inline float3 liquidGlassSampleEnvironmentFiltered(
    texture2d<half> environmentMap,
    sampler environmentSampler,
    float3 direction,
    float rotationY,
    float rotationX,
    float rotationZ,
    float verticalScale,
    float blur
) {
    float3 dir = normalize(
        liquidGlassRotateZ(
            liquidGlassRotateX(
                liquidGlassRotateY(direction, rotationY),
                rotationX
            ),
            rotationZ
        )
    );
    float maxMip = max(float(environmentMap.get_num_mip_levels()) - 1.0, 0.0);
    // A small mip floor keeps high-contrast window maps clean after sphere warping.
    float antiAliasMipFloor = min(maxMip, 1.5);
    float mipLevel = clamp(mix(antiAliasMipFloor, maxMip, clamp(blur, 0.0, 1.0)), 0.0, maxMip);
    return float3(environmentMap.sample(environmentSampler, liquidGlassEquirectangularUV(dir, verticalScale), level(mipLevel)).rgb);
}

static inline float liquidGlassEllipseGlow(float2 point, float2 center, float2 radius, float rotation, float softness) {
    float s = sin(rotation);
    float c = cos(rotation);
    float2 shifted = point - center;
    float2 rotated = float2(
        shifted.x * c - shifted.y * s,
        shifted.x * s + shifted.y * c
    );
    float2 normalized = rotated / max(radius, float2(0.0001));
    return exp(-dot(normalized, normalized) * softness);
}

// MARK: - Pipeline Data

struct ShowcaseLiquidGlassVertex {
    float2 position;
    float2 uv;
};

struct ShowcaseLiquidGlassFrameUniforms {
    float4 viewportAndTime;
};

struct ShowcaseLiquidGlassMaterialUniforms {
    float4 lensA;
    float4 envA;
    float4 surfaceA;
    float4 surfaceB;
    float4 grading;
};

struct ShowcaseLiquidGlassVertexOut {
    float4 position [[position]];
    float2 uv;
    float2 local;
};

// MARK: - Vertex Shader

vertex ShowcaseLiquidGlassVertexOut showcaseLiquidGlassVertex(
    const device ShowcaseLiquidGlassVertex *vertices [[buffer(0)]],
    uint vertexID [[vertex_id]]
) {
    ShowcaseLiquidGlassVertex quadVertex = vertices[vertexID];

    ShowcaseLiquidGlassVertexOut out;
    out.position = float4(quadVertex.position, 0.0, 1.0);
    out.uv = quadVertex.uv;
    out.local = quadVertex.position;
    return out;
}

// MARK: - Fragment Shader

fragment half4 showcaseLiquidGlassFragment(
    ShowcaseLiquidGlassVertexOut in [[stage_in]],
    constant ShowcaseLiquidGlassFrameUniforms &frame [[buffer(1)]],
    constant ShowcaseLiquidGlassMaterialUniforms &material [[buffer(2)]],
    texture2d<half> portrait [[texture(0)]],
    texture2d<half> environmentMap [[texture(1)]],
    sampler textureSampler [[sampler(0)]]
) {
    float2 centered = in.local;
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);
    float dist = length(centered);
    float radius = 1.0;

    float refraction = material.lensA.x;
    float lensAmount = material.lensA.y;
    float refractionBlur = material.lensA.z;
    float chroma = material.lensA.w;
    float envRotation = material.envA.x * 3.14159265;
    float envPitch = material.envA.y * 1.57079633;
    float envScaleY = material.envA.z;
    float envExposure = material.envA.w;
    float envRoll = material.grading.w * 3.14159265;
    float reflectionStrength = material.surfaceA.x;
    float environmentBlur = material.surfaceA.y;
    float rimLight = material.surfaceA.z;
    float studioArcStrength = material.surfaceA.w;
    float frostAmount = material.surfaceB.x;
    float veilStrength = material.surfaceB.y;
    float highlightStrength = material.surfaceB.z;
    float edgeShape = material.surfaceB.w;
    float exposure = material.grading.x;
    float imageShadowStrength = material.grading.y;
    float rimShadowStrength = material.grading.z;

    float shadowBlur = 0.12 + imageShadowStrength * 0.10;
    float2 shadowCenter = float2(0.05, 0.08);
    float shadowDist = length(centered - shadowCenter);

    if (dist > radius) {
        float shadowRadius = radius + shadowBlur;
        if (shadowDist < shadowRadius) {
            float shadowFalloff = (shadowDist - radius) / max(shadowBlur, 0.001);
            float shadowStrength = smoothstep(1.0, 0.0, shadowFalloff) * (0.035 + rimShadowStrength * 0.07);
            return half4(0.0, 0.0, 0.0, half(shadowStrength));
        }
        return half4(0.0);
    }

    float normalizedDist = clamp(dist / radius, 0.0, 1.0);
    float centerFalloff = 1.0 - normalizedDist * normalizedDist;
    float magnification = mix(centerFalloff, 1.0 - pow(normalizedDist, 6.0), clamp((lensAmount - 0.8) / 0.6, 0.0, 1.0));
    float2 refractedOffset = centered * magnification * (0.030 + refraction * 0.060) * (0.54 + lensAmount * 0.36);
    refractedOffset *= 1.0 - smoothstep(0.72, 1.0, normalizedDist) * 0.22;
    float chromaticStrength = pow(normalizedDist, 1.85) * chroma * 0.10;

    float2 redUV = clamp(uv - refractedOffset * (1.0 + chromaticStrength), float2(0.02), float2(0.98));
    float2 greenUV = clamp(uv - refractedOffset, float2(0.02), float2(0.98));
    float2 blueUV = clamp(uv - refractedOffset * (1.0 - chromaticStrength), float2(0.02), float2(0.98));

    half4 redSample = portrait.sample(textureSampler, redUV);
    half4 greenSample = portrait.sample(textureSampler, greenUV);
    half4 blueSample = portrait.sample(textureSampler, blueUV);

    float blurRadius = 0.003 + refractionBlur * 0.018 + frostAmount * 0.005;
    float2 blurX = float2(blurRadius, 0.0);
    float2 blurY = float2(0.0, blurRadius * 0.84);
    float3 greenBase = float3(greenSample.rgb);
    float3 refractedSoft =
        (
            greenBase * 2.0
            + float3(portrait.sample(textureSampler, clamp(greenUV + blurX, float2(0.02), float2(0.98))).rgb)
            + float3(portrait.sample(textureSampler, clamp(greenUV - blurX, float2(0.02), float2(0.98))).rgb)
            + float3(portrait.sample(textureSampler, clamp(greenUV + blurY, float2(0.02), float2(0.98))).rgb)
            + float3(portrait.sample(textureSampler, clamp(greenUV - blurY, float2(0.02), float2(0.98))).rgb)
        ) / 6.0;

    float3 refractedColor = float3(redSample.r, greenSample.g, blueSample.b);
    refractedColor = mix(refractedColor, greenBase, 0.26);
    refractedColor = mix(refractedColor, refractedSoft, 0.08 + refractionBlur * 0.14 + frostAmount * 0.05);

    float sphereZ = sqrt(max(0.0001, 1.0 - normalizedDist * normalizedDist));
    float3 normal = normalize(float3(centered, sphereZ));
    float fresnel = pow(1.0 - max(normal.z, 0.0), 3.1);
    float3 viewDir = float3(0.0, 0.0, -1.0);
    float3 reflectionVector = reflect(viewDir, normal);

    float3 envPrimary = liquidGlassSampleEnvironmentFiltered(environmentMap, textureSampler, reflectionVector, envRotation, envPitch, envRoll, envScaleY, environmentBlur);
    float3 envSoft = liquidGlassSampleEnvironmentFiltered(environmentMap, textureSampler, reflectionVector, envRotation, envPitch, envRoll, envScaleY, min(environmentBlur + 0.38, 1.0));
    float3 environmentRaw = max(mix(envPrimary, envSoft, clamp(environmentBlur * 0.42, 0.0, 0.42)) * max(envExposure, 0.0), float3(0.0));
    float environmentLuma = liquidGlassLuminance(environmentRaw);
    float environmentContrast = clamp(
        length(envPrimary - envSoft) * 2.8 + abs(liquidGlassLuminance(envPrimary) - liquidGlassLuminance(envSoft)) * 1.6,
        0.0,
        1.0
    );
    float whiteMapDamping = mix(0.32, 1.0, environmentContrast);
    float environmentHighlight = smoothstep(0.40, 1.35, environmentLuma) * environmentContrast;
    float3 environmentTone = environmentRaw / (1.0 + environmentRaw);
    float environmentToneLuma = liquidGlassLuminance(environmentTone);
    float3 environmentField = mix(environmentTone * 0.72, float3(environmentToneLuma), 0.36);
    float3 environmentSpecular = mix(environmentTone, float3(environmentToneLuma), 0.42);
    environmentSpecular = mix(environmentSpecular, float3(1.0), environmentHighlight * 0.46);
    float envPostToneGain = max(envExposure - 3.5, 0.0);
    environmentSpecular *= whiteMapDamping * (1.0 + envPostToneGain * 0.35);
    environmentField *= whiteMapDamping * (1.0 + envPostToneGain * 0.20);

    float edgeThickness = 0.050 - clamp(edgeShape * 0.010, 0.0, 0.020);
    float edgeDistance = abs(normalizedDist - 1.0);
    float rimFade = smoothstep(edgeThickness, 0.0, edgeDistance);
    float2 lightDir = normalize(float2(-0.52, -0.84));
    float rimBias = clamp(dot(normalize(centered + float2(0.0001, 0.0001)), lightDir), 0.0, 1.0);
    float directionalRim = rimFade * mix(0.12, 1.0, rimBias);

    float upperArc = liquidGlassEllipseGlow(centered, float2(-0.18, -0.44), float2(0.98, 0.22), -0.30, 1.40);
    float midArc = liquidGlassEllipseGlow(centered, float2(-0.20, -0.02), float2(0.92, 0.10), -0.08, 2.10);
    float lowerArc = liquidGlassEllipseGlow(centered, float2(0.02, 0.58), float2(0.82, 0.15), 0.02, 1.85);
    float frontVeil = liquidGlassEllipseGlow(centered, float2(-0.08, 0.12), float2(0.86, 0.42), -0.10, 1.32);
    float upperHemisphere = 1.0 - smoothstep(-0.22, 0.72, centered.y);
    float frontHemisphere = smoothstep(0.08, 0.86, centerFalloff);
    float heroWindowArc = liquidGlassEllipseGlow(centered, float2(-0.16, -0.46), float2(0.92, 0.19), -0.32, 1.42);
    float heroReflection = clamp(
        frontHemisphere * (0.050 + upperHemisphere * 0.20)
        + fresnel * 0.18
        + rimFade * 0.045,
        0.0,
        1.0
    );
    float studioArc = clamp(upperArc * 0.94 + midArc * 0.22 + lowerArc * 0.14, 0.0, 1.0) * studioArcStrength;
    float veil = clamp(frontVeil * (0.26 + veilStrength * 0.32) + lowerArc * (0.08 + frostAmount * 0.10), 0.0, 1.0);

    float3 spectralFringe = clamp(abs(float3(redSample.r, greenSample.g, blueSample.b) - greenBase) * 6.5, float3(0.0), float3(1.0));
    float chromaMask = clamp(upperArc * 0.56 + directionalRim * 0.68 + rimFade * 0.16, 0.0, 1.0) * smoothstep(0.03, 0.24, chroma);
    float interiorOcclusion = smoothstep(0.74, 0.98, normalizedDist) * (0.018 + rimShadowStrength * 0.03);

    float3 result = refractedColor;
    result *= 1.0 + centerFalloff * 0.05;
    result -= interiorOcclusion;
    result += environmentField * reflectionStrength * (heroReflection * 0.36 + fresnel * 0.16 + rimFade * 0.030);
    result += environmentSpecular * reflectionStrength * (heroReflection * 0.42 + studioArc * 0.76 + directionalRim * 0.14 + fresnel * 0.08);
    result += float3(1.0) * directionalRim * (0.08 + rimLight * 0.18);
    result += float3(1.0) * studioArc * (0.05 + studioArcStrength * 0.10);
    result += float3(1.0) * veil * (0.02 + veilStrength * 0.08 + frostAmount * 0.05);
    result += spectralFringe * chromaMask * (0.05 + chroma * 0.34);
    result += upperArc * float3(1.0) * (0.02 + highlightStrength * 0.05);
    result += heroWindowArc * environmentSpecular * reflectionStrength * (0.08 + studioArcStrength * 0.16);
    result += lowerArc * environmentField * (0.02 + reflectionStrength * 0.06);
    result *= exposure;

    float alpha = 1.0 - smoothstep(0.992, 1.0, normalizedDist);
    return half4(half3(clamp(result, 0.0, 1.0)), half(alpha));
}
