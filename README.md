TFAA 2.0 - Universal Edition
A modified version of Temporal Filter Anti-Aliasing (TFAA) for ReShade, optimized for broader compatibility and improved resource handling.

Changes in 2.0
 - Universal Motion Bridge: Adjusted motion vector logic for improved stability across various game engines and motion providers.
 - Optimization: Refactored code to improve frame-time performance.
 - Architecture: Condensed into a single .fx file for easier deployment.
 - Bug Fixes: Addressed resource allocation issues found in earlier revisions.

Installation and Requirements: Place TFAA_2.0.fx in your reshade-shaders/Shaders directory.

Dependencies: This shader requires a motion vector provider to be active. It is compatible with:
 - iMMERSE: Launchpad
 - vort_MotionEffects
 - LUMENITE: Kernel

Load Order:
 - Spatial Anti-Aliasing
 - Motion Vector Provider (e.g., LAUNCHPAD)
 - Any GI/AO/SSR Shaders
 - TFAA 2.0
 - Color Correction
 - Everything Else

Credits and Licensing

Original Author: Jakob Wapenhensch (2022)

Modified by: maksymilianlt (2026)

This project is a derivative work licensed under Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0).
 - [License Summary](https://creativecommons.org/licenses/by-nc/4.0/)
 - [Legal Code](https://creativecommons.org/licenses/by-nc/4.0/legalcode)
