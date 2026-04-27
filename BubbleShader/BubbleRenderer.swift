import MetalKit
import SwiftUI
import UIKit

final class BubbleRenderer: NSObject, MTKViewDelegate {
    // Three shared uniform buffers avoid CPU/GPU contention while frames overlap.
    private static let inFlightBufferCount = 3

    // MARK: - Metal Resources

    private let commandQueue: MTLCommandQueue
    private let bubblePipelineState: MTLRenderPipelineState
    private let glassPipelineState: MTLRenderPipelineState
    private let liquidGlassPipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private let quadVertexBuffer: MTLBuffer
    private let portraitTexture: MTLTexture
    private let environmentTexture: MTLTexture
    private let frameUniformBuffers: [MTLBuffer]
    private let bubbleMaterialUniformBuffers: [MTLBuffer]
    private let liquidGlassUniformBuffers: [MTLBuffer]
    private let startTime = CACurrentMediaTime()

    // MARK: - Render State

    private var uniformBufferIndex = 0
    private var drawableSize: CGSize = .zero
    private var preset: BubblePreset
    private var materialStyle: BubbleMaterialStyle
    private var controls: BubbleControls
    private var bubbleMaterialUniforms: BubbleMaterialUniforms
    private var liquidGlassUniforms: LiquidGlassMaterialUniforms

    // MARK: - Initialization

    init?(view: MTKView, preset: BubblePreset, materialStyle: BubbleMaterialStyle, controls: BubbleControls) {
        guard let device = view.device else {
            Self.logRendererIssue("No Metal device is attached to the MTKView.")
            return nil
        }

        guard
            let commandQueue = device.makeCommandQueue(),
            let library = Self.makeDefaultLibrary(device: device),
            let quadVertexBuffer = Self.makeQuadVertexBuffer(device: device),
            let samplerState = Self.makeSamplerState(device: device)
        else {
            Self.logRendererIssue("Failed to create required Metal resources.")
            return nil
        }

        guard
            let bubblePipelineState = Self.makePipelineState(
                device: device,
                library: library,
                vertexFunctionName: "showcaseBubbleVertex",
                fragmentFunctionName: "showcaseBubbleFragment",
                pixelFormat: view.colorPixelFormat,
                showcaseUseGlass: false
            ),
            let glassPipelineState = Self.makePipelineState(
                device: device,
                library: library,
                vertexFunctionName: "showcaseBubbleVertex",
                fragmentFunctionName: "showcaseBubbleFragment",
                pixelFormat: view.colorPixelFormat,
                showcaseUseGlass: true
            ),
            let liquidGlassPipelineState = Self.makePipelineState(
                device: device,
                library: library,
                vertexFunctionName: "showcaseLiquidGlassVertex",
                fragmentFunctionName: "showcaseLiquidGlassFragment",
                pixelFormat: view.colorPixelFormat
            )
        else {
            Self.logRendererIssue("Failed to create required render pipelines.")
            return nil
        }

        guard let fallbackTexture = Self.makeFallbackTexture(device: device) else {
            Self.logRendererIssue("Failed to create fallback textures.")
            return nil
        }
        // Shared portrait image for Bubble, Liquid, and Glass. Change this asset-catalog name to swap the demo image.
        let portraitTexture = Self.makePortraitTexture(device: device, imageName: "avatar") ?? fallbackTexture

        self.commandQueue = commandQueue
        self.bubblePipelineState = bubblePipelineState
        self.glassPipelineState = glassPipelineState
        self.liquidGlassPipelineState = liquidGlassPipelineState
        self.samplerState = samplerState
        self.quadVertexBuffer = quadVertexBuffer
        self.portraitTexture = portraitTexture
        self.environmentTexture = Self.makeEnvironmentTexture(device: device) ?? portraitTexture
        self.frameUniformBuffers = Self.makeUniformBuffers(
            device: device,
            length: MemoryLayout<BubbleFrameUniforms>.stride
        )
        self.bubbleMaterialUniformBuffers = Self.makeUniformBuffers(
            device: device,
            length: MemoryLayout<BubbleMaterialUniforms>.stride
        )
        self.liquidGlassUniformBuffers = Self.makeUniformBuffers(
            device: device,
            length: MemoryLayout<LiquidGlassMaterialUniforms>.stride
        )
        self.preset = preset
        self.materialStyle = materialStyle
        self.controls = controls
        self.bubbleMaterialUniforms = Self.makeBubbleMaterialUniforms(
            preset: preset,
            materialStyle: materialStyle,
            controls: controls
        )
        self.liquidGlassUniforms = Self.makeLiquidGlassUniforms(controls: controls)

        guard
            frameUniformBuffers.count == Self.inFlightBufferCount,
            bubbleMaterialUniformBuffers.count == Self.inFlightBufferCount,
            liquidGlassUniformBuffers.count == Self.inFlightBufferCount
        else {
            Self.logRendererIssue("Failed to allocate uniform buffers.")
            return nil
        }

        super.init()
        drawableSize = view.drawableSize
        writeMaterialUniformsToAllBuffers()
    }

    // MARK: - Updates

    func update(preset: BubblePreset, materialStyle: BubbleMaterialStyle, controls: BubbleControls, size: CGSize) {
        let needsUniformRefresh =
            self.preset != preset
            || self.materialStyle != materialStyle
            || self.controls != controls

        drawableSize = size
        guard needsUniformRefresh else {
            return
        }

        self.preset = preset
        self.materialStyle = materialStyle
        self.controls = controls
        bubbleMaterialUniforms = Self.makeBubbleMaterialUniforms(
            preset: preset,
            materialStyle: materialStyle,
            controls: controls
        )
        liquidGlassUniforms = Self.makeLiquidGlassUniforms(controls: controls)
        writeMaterialUniformsToAllBuffers()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = size
    }

    func draw(in view: MTKView) {
        guard
            let drawable = view.currentDrawable,
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            return
        }

        if drawableSize == .zero {
            drawableSize = view.drawableSize
        }

        uniformBufferIndex = (uniformBufferIndex + 1) % Self.inFlightBufferCount
        writeFrameUniforms()

        let activePipelineState: MTLRenderPipelineState
        switch materialStyle {
        case .bubble:
            activePipelineState = bubblePipelineState
        case .glass:
            activePipelineState = glassPipelineState
        case .liquidGlass:
            activePipelineState = liquidGlassPipelineState
        }
        encoder.setRenderPipelineState(activePipelineState)
        encoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(portraitTexture, index: 0)
        encoder.setFragmentTexture(environmentTexture, index: 1)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.setFragmentBuffer(frameUniformBuffers[uniformBufferIndex], offset: 0, index: 1)

        if materialStyle == .liquidGlass {
            encoder.setFragmentBuffer(liquidGlassUniformBuffers[uniformBufferIndex], offset: 0, index: 2)
        } else {
            encoder.setFragmentBuffer(bubbleMaterialUniformBuffers[uniformBufferIndex], offset: 0, index: 2)
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Uniform Writes

    private func writeFrameUniforms() {
        let elapsed = Float(CACurrentMediaTime() - startTime)
        let animationTime = elapsed * Float(max(controls.motionSpeed, 0.0))
        let frameUniforms = BubbleFrameUniforms(
            viewportAndTime: SIMD4(
                Float(max(drawableSize.width, 1)),
                Float(max(drawableSize.height, 1)),
                animationTime,
                Float(max(drawableSize.width / max(drawableSize.height, 1), 0.0001))
            )
        )
        Self.copy(frameUniforms, to: frameUniformBuffers[uniformBufferIndex])
    }

    private func writeMaterialUniformsToAllBuffers() {
        for index in 0..<Self.inFlightBufferCount {
            Self.copy(bubbleMaterialUniforms, to: bubbleMaterialUniformBuffers[index])
            Self.copy(liquidGlassUniforms, to: liquidGlassUniformBuffers[index])
        }
    }
}

// MARK: - Metal Data Layout

private struct BubbleQuadVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
}

private struct BubbleFrameUniforms {
    var viewportAndTime: SIMD4<Float>
}

// Keep this layout in sync with ShowcaseBubbleMaterialUniforms in BubbleShaders.metal.
private struct BubbleMaterialUniforms {
    var opticsA: SIMD4<Float>
    var opticsB: SIMD4<Float>
    var opticsC: SIMD4<Float>
    var grading: SIMD4<Float>
    var animation: SIMD4<Float>
    var surfaceModel: SIMD4<Float>
    var glassA: SIMD4<Float>
    var glassB: SIMD4<Float>
    var flareColor: SIMD4<Float>
    var surfaceTint: SIMD4<Float>
    var artworkShadow: SIMD4<Float>
    var artworkAccent: SIMD4<Float>
    var artworkHaze: SIMD4<Float>
    var artworkSun: SIMD4<Float>
}

// Keep this layout in sync with ShowcaseLiquidGlassMaterialUniforms in LiquidGlassShaders.metal.
private struct LiquidGlassMaterialUniforms {
    var lensA: SIMD4<Float>
    var envA: SIMD4<Float>
    var surfaceA: SIMD4<Float>
    var surfaceB: SIMD4<Float>
    var grading: SIMD4<Float>
}

// MARK: - Resource Creation

private extension BubbleRenderer {
    static func logRendererIssue(_ message: String) {
        #if DEBUG
        print("BubbleRenderer: \(message)")
        #endif
    }

    static func makeDefaultLibrary(device: MTLDevice) -> MTLLibrary? {
        if let library = try? device.makeDefaultLibrary(bundle: Bundle(for: BubbleRenderer.self)) {
            return library
        }

        return device.makeDefaultLibrary()
    }

    static func makeUniformBuffers(device: MTLDevice, length: Int) -> [MTLBuffer] {
        (0..<inFlightBufferCount).compactMap { _ in
            device.makeBuffer(length: length, options: .storageModeShared)
        }
    }

    static func makeQuadVertexBuffer(device: MTLDevice) -> MTLBuffer? {
        let vertices: [BubbleQuadVertex] = [
            .init(position: SIMD2(-1, -1), uv: SIMD2(0, 1)),
            .init(position: SIMD2(1, -1), uv: SIMD2(1, 1)),
            .init(position: SIMD2(-1, 1), uv: SIMD2(0, 0)),
            .init(position: SIMD2(1, -1), uv: SIMD2(1, 1)),
            .init(position: SIMD2(1, 1), uv: SIMD2(1, 0)),
            .init(position: SIMD2(-1, 1), uv: SIMD2(0, 0))
        ]

        return device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<BubbleQuadVertex>.stride * vertices.count
        )
    }

    static func makeSamplerState(device: MTLDevice) -> MTLSamplerState? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.sAddressMode = .repeat
        descriptor.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: descriptor)
    }

    static func makePipelineState(
        device: MTLDevice,
        library: MTLLibrary,
        vertexFunctionName: String,
        fragmentFunctionName: String,
        pixelFormat: MTLPixelFormat,
        showcaseUseGlass: Bool? = nil
    ) -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: vertexFunctionName) else {
            logRendererIssue("Missing Metal vertex function: \(vertexFunctionName).")
            return nil
        }

        let fragmentFunction: MTLFunction
        do {
            if let showcaseUseGlass {
                var useGlass = showcaseUseGlass
                let constants = MTLFunctionConstantValues()
                constants.setConstantValue(&useGlass, type: .bool, index: 0)
                fragmentFunction = try library.makeFunction(name: fragmentFunctionName, constantValues: constants)
            } else if let function = library.makeFunction(name: fragmentFunctionName) {
                fragmentFunction = function
            } else {
                logRendererIssue("Missing Metal fragment function: \(fragmentFunctionName).")
                return nil
            }
        } catch {
            logRendererIssue("Failed to specialize Metal fragment function \(fragmentFunctionName): \(error)")
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            logRendererIssue("Failed to create render pipeline: \(error)")
            return nil
        }
    }

    static func makePortraitTexture(device: MTLDevice, imageName: String) -> MTLTexture? {
        let edge = 1024
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .rgba8Unorm_srgb
        descriptor.width = edge
        descriptor.height = edge
        descriptor.mipmapLevelCount = 1
        descriptor.usage = [.shaderRead]

        guard let image = makeImage(named: imageName) else {
            logRendererIssue("Missing portrait image asset: \(imageName).")
            return nil
        }

        guard
            let texture = device.makeTexture(descriptor: descriptor),
            let cgImage = image.cgImage,
            let bytes = makeTextureBytes(for: cgImage, edge: edge)
        else {
            logRendererIssue("Failed to create portrait texture: \(imageName).")
            return nil
        }
        defer { free(bytes) }

        texture.replace(
            region: MTLRegionMake2D(0, 0, edge, edge),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: edge * 4
        )

        return texture
    }

    static func makeEnvironmentTexture(device: MTLDevice) -> MTLTexture? {
        let rendererBundle = Bundle(for: BubbleRenderer.self)
        guard
            let url = rendererBundle.url(forResource: "map", withExtension: "jpg")
                ?? Bundle.main.url(forResource: "map", withExtension: "jpg")
        else {
            logRendererIssue("Missing bundled environment map: map.jpg.")
            return nil
        }

        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: true,
            // The shader samples explicit mip levels to keep sharp window maps from aliasing.
            .generateMipmaps: NSNumber(booleanLiteral: true),
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
        ]

        do {
            return try loader.newTexture(URL: url, options: options)
        } catch {
            logRendererIssue("Failed to load environment map: \(error)")
            return nil
        }
    }

    static func makeFallbackTexture(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb,
            width: 2,
            height: 2,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        var pixels: [UInt8] = [
            70, 70, 74, 255,
            118, 118, 124, 255,
            108, 108, 116, 255,
            56, 56, 62, 255
        ]
        texture.replace(
            region: MTLRegionMake2D(0, 0, 2, 2),
            mipmapLevel: 0,
            withBytes: &pixels,
            bytesPerRow: 2 * 4
        )

        return texture
    }

    static func makeImage(named imageName: String) -> UIImage? {
        let preferredBundles = [
            Bundle.main,
            Bundle(for: BubbleRenderer.self)
        ]
        let fallbackBundles = Bundle.allBundles + Bundle.allFrameworks
        var searchedBundleURLs = Set<URL>()

        for bundle in preferredBundles + fallbackBundles where searchedBundleURLs.insert(bundle.bundleURL).inserted {
            if let image = UIImage(named: imageName, in: bundle, compatibleWith: nil) {
                return image
            }
        }

        return UIImage(named: imageName) ?? makeSourceImage(named: imageName)
    }

    static func makeSourceImage(named imageName: String) -> UIImage? {
        #if DEBUG
        let sourceDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let imageSetDirectory = sourceDirectory
            .appendingPathComponent("Assets.xcassets")
            .appendingPathComponent("\(imageName).imageset")

        for fileExtension in ["png", "jpg", "jpeg", "webp"] {
            let url = imageSetDirectory.appendingPathComponent("\(imageName).\(fileExtension)")
            if let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }
        #endif

        return nil
    }

    static func makeTextureBytes(for cgImage: CGImage, edge: Int) -> UnsafeMutableRawPointer? {
        let bytesPerRow = edge * 4
        let totalByteCount = bytesPerRow * edge
        guard let data = malloc(totalByteCount) else {
            return nil
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: data,
            width: edge,
            height: edge,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            free(data)
            return nil
        }

        context.interpolationQuality = .high
        context.setFillColor(UIColor.clear.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: edge, height: edge))

        let imageRect = CGRect(origin: .zero, size: CGSize(width: edge, height: edge))
        let imageAspect = CGFloat(cgImage.width) / CGFloat(max(cgImage.height, 1))
        let targetAspect = CGFloat(edge) / CGFloat(edge)

        // Fill the square texture by center-cropping, matching the visual framing used by the shader.
        let drawRect: CGRect
        if imageAspect > targetAspect {
            let drawWidth = CGFloat(edge) * imageAspect
            drawRect = CGRect(
                x: (CGFloat(edge) - drawWidth) * 0.5,
                y: 0,
                width: drawWidth,
                height: CGFloat(edge)
            )
        } else {
            let drawHeight = CGFloat(edge) / max(imageAspect, 0.001)
            drawRect = CGRect(
                x: 0,
                y: (CGFloat(edge) - drawHeight) * 0.5,
                width: CGFloat(edge),
                height: drawHeight
            )
        }

        context.translateBy(x: 0, y: imageRect.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: drawRect)
        return data
    }
}

// MARK: - Uniform Packing

private extension BubbleRenderer {
    static func makeBubbleMaterialUniforms(
        preset: BubblePreset,
        materialStyle: BubbleMaterialStyle,
        controls: BubbleControls
    ) -> BubbleMaterialUniforms {
        BubbleMaterialUniforms(
            opticsA: SIMD4(
                Float(controls.refraction),
                Float(controls.chromaticSpread),
                Float(controls.lensAmount),
                Float(controls.wobble)
            ),
            opticsB: SIMD4(
                Float(controls.glowStrength),
                Float(controls.flareStrength),
                Float(controls.edgeDistortion),
                Float(controls.shapeMorph)
            ),
            opticsC: SIMD4(
                Float(controls.rimStrength),
                Float(controls.highlightStrength),
                Float(controls.driftAmount),
                1.085
            ),
            grading: SIMD4(
                Float(controls.exposure),
                Float(controls.imageShadowStrength),
                Float(controls.shellDimStrength),
                Float(controls.rimShadowStrength)
            ),
            animation: SIMD4(
                Float(controls.iridescenceAmount),
                Float(controls.iridescenceSpeed),
                Float(controls.highlightTravel),
                Float(controls.bloomRadius)
            ),
            surfaceModel: SIMD4(
                Float(controls.environmentRoll),
                Float(controls.environmentRotation),
                Float(controls.reflectionStrength),
                Float(controls.environmentBlur)
            ),
            glassA: SIMD4(
                Float(controls.frostAmount),
                Float(controls.rimLight),
                Float(controls.refractionBlur),
                Float(controls.environmentExposure)
            ),
            glassB: SIMD4(
                Float(controls.veilStrength),
                Float(controls.studioArcStrength),
                Float(controls.environmentPitch),
                Float(controls.environmentScaleY)
            ),
            flareColor: colorVector(for: preset.flareColor),
            surfaceTint: colorVector(for: preset.surfaceTint),
            artworkShadow: colorVector(for: preset.artworkShadow),
            artworkAccent: colorVector(for: preset.artworkAccent),
            artworkHaze: colorVector(for: preset.artworkHaze),
            artworkSun: colorVector(for: preset.artworkSun)
        )
    }

    static func makeLiquidGlassUniforms(controls: BubbleControls) -> LiquidGlassMaterialUniforms {
        LiquidGlassMaterialUniforms(
            lensA: SIMD4(
                Float(controls.refraction),
                Float(controls.lensAmount),
                Float(controls.refractionBlur),
                Float(controls.chromaticSpread)
            ),
            envA: SIMD4(
                Float(controls.environmentRotation),
                Float(controls.environmentPitch),
                Float(controls.environmentScaleY),
                Float(controls.environmentExposure)
            ),
            surfaceA: SIMD4(
                Float(controls.reflectionStrength),
                Float(controls.environmentBlur),
                Float(controls.rimLight),
                Float(controls.studioArcStrength)
            ),
            surfaceB: SIMD4(
                Float(controls.frostAmount),
                Float(controls.veilStrength),
                Float(controls.highlightStrength),
                Float(controls.edgeDistortion)
            ),
            grading: SIMD4(
                Float(controls.exposure),
                Float(controls.imageShadowStrength),
                Float(controls.rimShadowStrength),
                Float(controls.environmentRoll)
            )
        )
    }

    static func colorVector(for color: Color) -> SIMD4<Float> {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return SIMD4(Float(red), Float(green), Float(blue), Float(alpha))
    }

    static func copy<T>(_ value: T, to buffer: MTLBuffer) {
        var mutableValue = value
        withUnsafeBytes(of: &mutableValue) { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            memcpy(buffer.contents(), baseAddress, bytes.count)
        }
    }
}
