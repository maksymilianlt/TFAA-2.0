# TFAA 2.0 - Universal Edition

A modified version of Temporal Filter Anti-Aliasing (TFAA) for ReShade, optimized for cross-provider compatibility, frametime-independent accumulation, and universal depth handling.

## Changes in 2.0
- **Integrated Depth Calibration:** Added internal UI controls for Depth Orientation (Normal/Reversed), Upside-Down flipping, and Linearization tuning.
- **Depth Debug:** Built-in debug overlay to verify depth-buffer alignment.
- **Mathematical Reference Calibration:** Synchronized accumulation and sharpening baselines to mathematically calibrated references.
- **Motion Stability & Gain Calibration:** Added a motion noise floor to stop sharpening flicker and calibrated the gain.
- **Rec.709 Integration:** Migrated from Rec.601 luma conversion to Rec.709 luma conversion to align with modern color-space standards.
- **Real-Time FPS Synchronization:** Dynamic frametime scaling ensures blending weights synchronize 1:1 with your current refresh rate.
- **Universal Motion Bridge:** Added native support for iMMERSE: Launchpad, vort_MotionEffects, LUMENITE: Kernel, and Zenteon: Motion.
- **Precision Sampling:** Implemented 5-tap Catmull-Rom bicubic history reconstruction to reduce sub-pixel blurring.
- **Stability Fixes:** Resolved history buffer resource pooling conflicts and implemented division-by-zero crash guards.

## Installation and Requirements
 - Install the latest version of ReShade.
 - Place `TFAA_2.0.fx` in your `reshade-shaders/Shaders` directory.
 - Requires a supported motion vector provider: **iMMERSE Launchpad**, **vort_MotionEffects**, **LUMENITE: Kernel**, or **Zenteon: Motion**.
 - Enable `Display Depth Debug` in the shader UI. Use the **Depth Orientation**, **Upside Down**, and **Depth Map Adjustment** settings until you see a clear grayscale representation of your game world.

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
