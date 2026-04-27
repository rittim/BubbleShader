# BubbleShader

BubbleShader is an iOS SwiftUI and Metal shader experiment for rendering refractive bubble, liquid glass, and glass materials around an image.

The project is intentionally small: the UI exposes the shader controls directly, while the rendering path stays in Metal for predictable visual output and performance.

## Features

- Metal-rendered bubble, liquid glass, and glass material styles
- SwiftUI control panel for tuning refraction, reflection, blur, rim light, and motion
- Equirectangular environment-map reflections
- Mip-filtered environment sampling to reduce aliasing on high-contrast maps
- Shared demo image across all material styles

## Preview

<p align="center">
  <a href="https://github.com/user-attachments/assets/fb5c763e-5ce9-46ff-8d67-9d3f0605ead0">
    <img src="Media/bubble-demo-1.jpg" alt="Bubble material preview" width="48%">
  </a>
  <a href="https://github.com/user-attachments/assets/685a283d-780f-4f24-8a19-3988bad9b929">
    <img src="Media/bubble-demo-2.jpg" alt="Liquid material preview" width="48%">
  </a>
</p>

<p align="center">
  <a href="https://github.com/user-attachments/assets/d32a180d-54b0-4b05-9865-de08c1f666df">
    <img src="Media/bubble-demo-3.jpg" alt="Glass material preview" width="48%">
  </a>
  <a href="https://github.com/user-attachments/assets/81999a59-8dd3-4852-9f8d-c18b2fe5853f">
    <img src="Media/screen-recording.jpg" alt="Full screen recording" width="48%">
  </a>
</p>

## Requirements

- Xcode 17 or newer
- iOS 26 SDK
- iPhone or iPad simulator

## Running

Open `BubbleShader.xcodeproj` in Xcode, select the `BubbleShader` scheme, and run on an iOS simulator.

The project uses the placeholder bundle identifier `com.example.bubbleshader` and does not include a development team. To run on a physical device, set your own bundle identifier and signing team in Xcode.

From the command line:

```sh
xcodebuild -project BubbleShader.xcodeproj -scheme BubbleShader -destination 'generic/platform=iOS Simulator' build
```

## Assets

The renderer expects these bundled assets:

- `Assets.xcassets/avatar.imageset/avatar.png` for the material image
- `BubbleShader/map.jpg` for the environment reflection map

Bubble, Liquid, and Glass all use the same material image. To change it, add or replace an image set in `Assets.xcassets`, then update the `imageName` passed to `makePortraitTexture` in `BubbleRenderer.swift`.

For best reflection results, `map.jpg` should be a 2:1 equirectangular image. Very high-contrast maps can alias when sampled through strong curvature, so the shader applies a small mip-level floor even when environment blur is set to zero.

Asset provenance:

- The material image and environment reflection map were generated with ChatGPT.

## Credits

This project was inspired by the excellent bubble/glass visual work shared by [@theopanag7](https://x.com/theopanag7/status/1907883756838642127). This is not a perfect recreation; it is an iOS/Metal experiment exploring a similar refractive, reflective material feel.

## Project Structure

- `BubbleShowcaseView.swift` builds the main SwiftUI demo screen.
- `BubbleControlPanel.swift` defines the segmented controls and sliders.
- `BubbleRenderer.swift` owns the Metal device resources, textures, buffers, and render pipeline.
- `BubbleShaders.metal` renders the bubble and shared showcase material path.
- `LiquidGlassShaders.metal` renders the liquid/glass material path.
- `BubbleModels.swift` stores material styles and default control values.

## License

This project is released under the MIT License. See [LICENSE](LICENSE).

The MIT License covers the source code. Bundled demo image assets were generated with ChatGPT and are included for demonstration.
