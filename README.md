# TFAA 2.0 - Universal Edition

A modified version of Temporal Filter Anti-Aliasing (TFAA) for ReShade, optimized for cross-provider compatibility and frametime-independent accumulation.

## Changes in 2.0
- **Mathematical Reference Calibration:** Synchronized accumulation and sharpening baselines to mathematically calibrated references.
- **Motion Stability & Gain Calibration:** Added a motion noise floor to stop sharpening flicker and calibrated the gain.
- **Rec.709 Integration:** Migrated from Rec.601 luma conversion to Rec.709 luma conversion to align with modern color-space standards.
- **Real-Time FPS Synchronization:** Replaced the static 48 FPS baseline with dynamic frametime scaling. Blending weights now synchronize 1:1 with your current refresh rate for maximum clarity and zero accumulation lag.
- **Universal Motion Bridge:** Added native support for iMMERSE: Launchpad, vort_MotionEffects, LUMENITE: Kernel, and Zenteon: Motion.
- **Precision Sampling:** Implemented 5-tap Catmull-Rom bicubic history reconstruction to reduce sub-pixel blurring.
- **Stability Fixes:** Resolved depth-buffer inversion logic and history buffer resource pooling conflicts, including division-by-zero crash guards for zero-frametime scenarios.

## Installation and Requirements
- Install the latest version of ReShade.
- Place `TFAA_2.0.fx` in your `reshade-shaders/Shaders` directory.
- Requires a supported motion vector provider: **iMMERSE Launchpad**, **vort_MotionEffects**, **LUMENITE: Kernel**, or **Zenteon: Motion**.
- Use `DisplayDepth.fx` to verify your depth buffer settings (Reversed, Logarithmic, etc.) before enabling the shader.

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
