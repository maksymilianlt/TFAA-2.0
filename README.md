# TFAA 2.0 - Universal Edition

A modified version of Temporal Filter Anti-Aliasing (TFAA) for ReShade, optimized for broader compatibility and improved resource handling.

## Changes in 2.0
 - **Universal Motion Bridge:** Adjusted motion vector logic for improved stability across various game engines and motion providers.
 - **Optimization:** Refactored code to improve frame-time performance.
 - **Architecture:** Condensed into a single .fx file for easier deployment.
 - **Bug Fixes:** Addressed resource allocation issues found in earlier revisions.

## Installation and Requirements
Place `TFAA_2.0.fx` in your `reshade-shaders/Shaders` directory.

**Dependencies:** This shader requires a motion vector provider to be active. It is compatible with:
 - iMMERSE: Launchpad
 - vort_MotionEffects
 - LUMENITE: Kernel

## Load Order
 1. Spatial Anti-Aliasing
 2. Motion Vector Provider (e.g., LAUNCHPAD)
 3. Any GI/AO/SSR Shaders
 4. **TFAA 2.0**
 5. Color Correction
 6. Everything Else

---

## Credits
**Original Author:** Jakob Wapenhensch (2022)  
**Modified by:** maksymilianlt (2026)

Licensed under [CC BY-NC 4.0](LICENSE.md).
