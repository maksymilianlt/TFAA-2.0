# TFAA 2.0 - Universal Edition

A modified version of Temporal Filter Anti-Aliasing (TFAA) for ReShade, optimized for broader compatibility and improved resource handling.

## Changes in 2.0
- **Universal Motion Bridge:** Adjusted motion vector logic for improved stability across various game engines and motion providers.
- **Precision Sampling:** Implemented a discrete 3x3 neighborhood grid to eliminate legacy sub-pixel blurring.
- **Optimization:** Refactored code to improve frame-time performance and reduced binary size.
- **Bug Fixes:** Resolved history buffer resource pooling conflicts and depth-buffer inversion issues.

## Installation and Requirements
- Install the latest ReShade build.
- Place `TFAA_2.0.fx` in your `reshade-shaders/Shaders` directory.
- Install a supported motion vector provider. It is compatible with: **iMMERSE Launchpad**, **vort_MotionEffects**, and **LUMENITE: Kernel**.
- Ensure the depth buffer is detected correctly using the `DisplayDepth.fx` shader. If it isn't, click "Edit global preprocessor definitions" and adjust the "Reversed", "Upside Down", or "Logarithmic" settings until the depth map displays correctly.
- Ensure you are using the correct load order as shown below:

## Load Order
1. Spatial Anti-Aliasing
2. Motion Vector Provider
3. Any GI/AO/SSR Shaders
4. **TFAA 2.0**
5. Color Correction
6. Everything Else

---

## Credits
**Original Author:** Jakob Wapenhensch (2025)  
**Modified & Optimized by:** maksymilianlt (2026)

Licensed under [CC BY-NC 4.0](LICENSE.md).
