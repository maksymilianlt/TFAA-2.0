/*=============================================================================
    TFAA (2.0) - Universal Edition
    Temporal Filter Anti-Aliasing Shader
    
    First published 2025 - Copyright, Jakob Wapenhensch
    Modified & Optimized by maksymilianlt (2026)
    
    Key Updates: 
    - Implemented Universal Motion Bridge (Launchpad, VORT, Lumenite)
    - Resolved history buffer resource pooling conflicts
    - Refactored codebase for improved performance and reduced binary size
    
    License: CC BY-NC 4.0 (https://creativecommons.org/licenses/by-nc/4.0/)
=============================================================================*/

#include "ReShadeUI.fxh"
#include "ReShade.fxh"

#ifndef RESHADE_DEPTH_LINEARIZATION_FAR_PLANE
    #define RESHADE_DEPTH_LINEARIZATION_FAR_PLANE 1000.0
#endif

/*=============================================================================
    Preprocessor Settings
=============================================================================*/

// Compatibility mode for OpenGL. Set this to 1 in Preprocessor Definitions if playing OpenGL-based games or if the shader fails to display.
#ifndef TFAA_USE_OPENGL_COMPATIBILITY
    #define TFAA_USE_OPENGL_COMPATIBILITY 0
#endif

#if TFAA_USE_OPENGL_COMPATIBILITY
    #define TFAA_FORMAT RGBA8
#else
    #define TFAA_FORMAT RGBA16F
#endif

// Uniform variable to access the frame time.
uniform float frametime < source = "frametime"; >;

// Constant for temporal weights adjustment based on a 48 FPS baseline.
static const float fpsConst = (1000.0 / 48.0);

/*=============================================================================
    UI Uniforms
=============================================================================*/

uniform int UI_MOTION_SOURCE <
    ui_type = "combo";
    ui_label = "Motion Vector Source";
    ui_items = "iMMERSE: Launchpad\0vort_MotionEffects\0LUMENITE: Kernel\0";
    ui_category = "Temporal Filter";
    ui_tooltip = "Select the provider for motion vectors. Ensure the corresponding shader is active in your preset.";
> = 0;

uniform float UI_TEMPORAL_FILTER_STRENGTH <
    ui_type    = "slider";
    ui_min     = 0.0; 
    ui_max     = 1.0; 
    ui_step    = 0.01;
    ui_label   = "Temporal Filter Strength";
    ui_category= "Temporal Filter";
> = 0.5;

uniform float UI_POST_SHARPEN <
    ui_type    = "slider";
    ui_min     = 0.0; 
    ui_max     = 1.0; 
    ui_step    = 0.01;
    ui_label   = "Adaptive Sharpening";
    ui_category= "Temporal Filter";
> = 0.5;

/*=============================================================================
    Textures & Samplers
=============================================================================*/

// Texture and sampler for depth input.
texture texDepthIn : DEPTH;
sampler smpDepthIn { 
    Texture = texDepthIn; 
};

// Texture and sampler for the current frame's color.
texture texInCur : COLOR;
sampler smpInCur { 
    Texture   = texInCur; 
    AddressU  = Clamp; 
    AddressV  = Clamp; 
    MipFilter = Linear; 
    MinFilter = Linear; 
    MagFilter = Linear; 
};

// Backup texture for the current frame's color.
texture texInCurBackup { 
    Width  = BUFFER_WIDTH; 
    Height = BUFFER_HEIGHT; 
    Format = RGBA8; 
};

sampler smpInCurBackup { 
    Texture   = texInCurBackup; 
    AddressU  = Clamp; 
    AddressV  = Clamp; 
    MipFilter = Linear; 
    MinFilter = Linear; 
    MagFilter = Linear; 
};

// Texture for storing the exponential frame buffer.
texture texExpColor { 
    Width = BUFFER_WIDTH; 
    Height = BUFFER_HEIGHT; 
    Format = TFAA_FORMAT; 
};

sampler smpExpColor { 
    Texture   = texExpColor; 
    AddressU  = Clamp; 
    AddressV  = Clamp; 
    MipFilter = Linear; 
    MinFilter = Linear; 
    MagFilter = Linear; 
};

// Backup texture for the exponential frame buffer.
texture texExpColorBackup { 
    Width = BUFFER_WIDTH; 
    Height = BUFFER_HEIGHT; 
    Format = TFAA_FORMAT; 
};

sampler smpExpColorBackup { 
    Texture   = texExpColorBackup; 
    AddressU  = Clamp; 
    AddressV  = Clamp; 
    MipFilter = Linear; 
    MinFilter = Linear; 
    MagFilter = Linear; 
};

// Backup texture for the last frame's depth.
texture texDepthBackup { 
    Width = BUFFER_WIDTH; 
    Height = BUFFER_HEIGHT; 
    Format = R16f; 
};

sampler smpDepthBackup { 
    Texture   = texDepthBackup; 
    AddressU  = Clamp; 
    AddressV  = Clamp; 
    MipFilter = Point; 
    MinFilter = Point; 
    MagFilter = Point; 
};

/*=============================================================================
    Functions
=============================================================================*/

float4 tex2Dlod(sampler s, float2 uv, float mip) { return tex2Dlod(s, float4(uv, 0, mip)); }

// Color Space Conversions (YCbCr)
float3 cvtRgb2YCbCr(float3 rgb)
{
    float y  = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b;
    float cb = (rgb.b - y) * 0.565;
    float cr = (rgb.r - y) * 0.713;
    return float3(y, cb, cr);
}

float3 cvtYCbCr2Rgb(float3 YCbCr)
{
    return float3(
        YCbCr.x + 1.403 * YCbCr.z,
        YCbCr.x - 0.344 * YCbCr.y - 0.714 * YCbCr.z,
        YCbCr.x + 1.770 * YCbCr.y
    );
}

// Internal wrapper for temporal logic
float3 cvtRgb2whatever(float3 rgb) { return cvtRgb2YCbCr(rgb); }
float3 cvtWhatever2Rgb(float3 whatever) { return cvtYCbCr2Rgb(whatever); }

// High-quality bicubic sampling (Inspired by Marty Robbins)
float4 bicubic_5(sampler source, float2 texcoord)
{
    float2 texsize = tex2Dsize(source);
    float2 UV = texcoord * texsize;
    float2 tc = floor(UV - 0.5) + 0.5;
    float2 f = UV - tc;

    float2 f2 = f * f;
    float2 f3 = f2 * f;

    float2 w0 = f2 - 0.5 * (f3 + f);
    float2 w1 = 1.5 * f3 - 2.5 * f2 + 1.0;
    float2 w3 = 0.5 * (f3 - f2);
    float2 w12 = 1.0 - w0 - w3;

    float4 ws[3];
    ws[0].xy = w0; ws[1].xy = w12; ws[2].xy = w3;
    ws[0].zw = (tc - 1.0) / texsize;
    ws[1].zw = (tc + 1.0 - w1 / w12) / texsize;
    ws[2].zw = (tc + 2.0) / texsize;

    float4 ret = tex2Dlod(source, float2(ws[1].z, ws[0].w), 0) * ws[1].x * ws[0].y;
    ret += tex2Dlod(source, float2(ws[0].z, ws[1].w), 0) * ws[0].x * ws[1].y;
    ret += tex2Dlod(source, float2(ws[1].z, ws[1].w), 0) * ws[1].x * ws[1].y;
    ret += tex2Dlod(source, float2(ws[2].z, ws[1].w), 0) * ws[2].x * ws[1].y;
    ret += tex2Dlod(source, float2(ws[1].z, ws[2].w), 0) * ws[1].x * ws[2].y;
    
    return max(0, ret * (1.0 / (1.0 - (f.x - f2.x) * (f.y - f2.y) * 0.25)));
}

// Helper to sample history with bicubic filtering
float4 sampleHistory(sampler2D historySampler, float2 texcoord)
{
    return bicubic_5(historySampler, texcoord);
}

// Linearizes depth and handles reversed depth buffers
float getDepth(float2 texcoord)
{
    float depth = tex2Dlod(smpDepthIn, texcoord, 0).x;

    #if RESHADE_DEPTH_INPUT_IS_REVERSED
        depth = 1.0 - depth;
    #endif

    const float N = 1.0;
    float factor = RESHADE_DEPTH_LINEARIZATION_FAR_PLANE * 0.1;
    depth /= factor - depth * (factor - N);

    return depth;
}

/*=============================================================================
    Motion Vector Imports (Universal Bridge)
=============================================================================*/

// --- Lumenite Kernel Hook ---
texture2D tLumaFlow { Width = BUFFER_WIDTH/8; Height = BUFFER_HEIGHT/8; Format = RG16F; };
sampler2D sLumaFlow { Texture = tLumaFlow; MagFilter = POINT; MinFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };

// --- VORT Motion Hook ---
texture2D MotVectTexVort { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
sampler2D sMotVectTexVort { 
    Texture = MotVectTexVort; 
    MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; 
    AddressU = CLAMP; AddressV = CLAMP; 
};

// --- iMMERSE Launchpad Hook (The Namespace Secret) ---
namespace Deferred 
{
    texture MotionVectorsTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
    sampler sMotionVectorsTex { Texture = MotionVectorsTex; };

    float2 get_motion(float2 uv)
    {
        return tex2Dlod(sMotionVectorsTex, uv, 0).xy;
    }
}

float2 get_universal_motion(float2 uv)
{
    if (UI_MOTION_SOURCE == 0) // iMMERSE: Launchpad
    {
        return Deferred::get_motion(uv);
    }
    else if (UI_MOTION_SOURCE == 1) // vort_MotionEffects
    {
        return tex2Dlod(sMotVectTexVort, uv, 0).rg;
    }
    else // LUMENITE: Kernel (Index 2)
    {
        return tex2Dlod(sLumaFlow, uv, 0).xy;
    }
}

/*=============================================================================
    Shader Pass Functions
=============================================================================*/

// Capture current frame and depth for the temporal neighborhood
float4 SaveCur(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target0
{
    return float4(tex2Dlod(smpInCur, texcoord, 0).rgb, getDepth(texcoord));
}

// Main Temporal logic: Blends history using motion, contrast, and depth masks
float4 TemporalFilter(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 sampleCur = tex2Dlod(smpInCurBackup, texcoord, 0);
    float4 cvtColorCur = float4(cvtRgb2whatever(sampleCur.rgb), sampleCur.a);

    static const float2 nOffsets[9] = { 
        float2(-1, -1), float2(0, -1), float2(1, -1), 
        float2(-1,  0), float2(0,  0), float2(1,  0), 
        float2(-1,  1), float2(0,  1), float2(1,  1) 
    };

    int closestDepthIndex = 4;
    float4 minimumCvt = 2;
    float4 maximumCvt = -1;

    for (int i = 0; i < 9; i++)
    {
        float4 neighborhoodSample = tex2Dlod(smpInCurBackup, texcoord + (nOffsets[i] * ReShade::PixelSize), 0);
        float4 cvt = float4(cvtRgb2whatever(neighborhoodSample.rgb), neighborhoodSample.a);

        if (neighborhoodSample.a < minimumCvt.a) closestDepthIndex = i;

        minimumCvt = min(minimumCvt, cvt);
        maximumCvt = max(maximumCvt, cvt);
    }

    float2 motion = get_universal_motion(texcoord + (nOffsets[closestDepthIndex] * ReShade::PixelSize));
    float2 lastSamplePos = texcoord + motion;

    float lastDepth = tex2Dlod(smpDepthBackup, lastSamplePos, 0).r;
    float4 sampleExp = saturate(sampleHistory(smpExpColorBackup, lastSamplePos));

    float fpsFix       = frametime / fpsConst;
    float localContrast= saturate(pow(abs(maximumCvt.r - minimumCvt.r), 0.75));
    float speed        = length(motion);
    float speedFactor  = 1.0 - pow(saturate(speed * 20.0), 0.5);

    float depthDelta = max(0, saturate(minimumCvt.a - lastDepth)) / sampleCur.a;
    float depthMask  = saturate(1.0 - pow(depthDelta * 4, 4));

    float baseLeak = 1.0 - lerp(0.50, 0.98, UI_TEMPORAL_FILTER_STRENGTH);
    float adjustedLeak = pow(abs(baseLeak), frametime / fpsConst);

    float weight = saturate(1.0 - adjustedLeak);
    weight = lerp(weight, weight * (0.6 + localContrast * 2), 0.5);
    weight = clamp(weight * speedFactor * depthMask, 0.0, 0.95);

    float4 sampleExpClamped = float4(cvtWhatever2Rgb(clamp(cvtRgb2whatever(sampleExp.rgb), minimumCvt.rgb, maximumCvt.rgb)), sampleExp.a);

    const static float correctionFactor = 2;
    float3 blendedColor = saturate(pow(lerp(pow(sampleCur.rgb, correctionFactor), pow(sampleExpClamped.rgb, correctionFactor), weight), (1.0 / correctionFactor)));

    float sharp = (0.01 + localContrast) * (pow(speed, 0.3)) * 32;
    sharp = saturate(((sharp + sampleExpClamped.a) * 0.5) * depthMask * UI_POST_SHARPEN * UI_TEMPORAL_FILTER_STRENGTH);

    return float4(blendedColor, sharp);
}

// Commit results to history buffers
void SavePost(float4 position : SV_Position, float2 texcoord : TEXCOORD, out float4 lastExpOut : SV_Target0, out float depthOnly : SV_Target1)
{
    lastExpOut = tex2Dlod(smpExpColor, texcoord, 0);
    depthOnly = getDepth(texcoord);
}

// Final output pass with adaptive sharpening (CAS-style)
float4 Out(float4 position : SV_Position, float2 texcoord : TEXCOORD ) : SV_Target
{
    float4 center     = tex2Dlod(smpExpColor, texcoord, 0);
    float4 top        = tex2Dlod(smpExpColor, texcoord + (float2(0, -1) * ReShade::PixelSize), 0);
    float4 bottom     = tex2Dlod(smpExpColor, texcoord + (float2(0,  1) * ReShade::PixelSize), 0);
    float4 left       = tex2Dlod(smpExpColor, texcoord + (float2(-1, 0) * ReShade::PixelSize), 0);
    float4 right      = tex2Dlod(smpExpColor, texcoord + (float2(1,  0) * ReShade::PixelSize), 0);
    float4 topLeft    = tex2Dlod(smpExpColor, texcoord + (float2(-0.7, -0.7) * ReShade::PixelSize), 0);
    float4 topRight   = tex2Dlod(smpExpColor, texcoord + (float2(0.7,  -0.7) * ReShade::PixelSize), 0);
    float4 bottomLeft = tex2Dlod(smpExpColor, texcoord + (float2(-0.7,  0.7) * ReShade::PixelSize), 0);
    float4 bottomRight= tex2Dlod(smpExpColor, texcoord + (float2(0.7,   0.7) * ReShade::PixelSize), 0);

    float4 maxBox = max(max(top, max(bottom, max(left, max(right, center)))), max(topLeft, max(topRight, max(bottomLeft, bottomRight))));
    float4 minBox = min(min(top, min(bottom, min(left, min(right, center)))), min(topLeft, min(topRight, min(bottomLeft, bottomRight))));

    float contrast    = 0.6;
    float sharpAmount = saturate(maxBox.a); 

    float4 crossWeight = -rcp(rsqrt(saturate(min(minBox, 1.0 - maxBox) * rcp(maxBox))) * (-3.0 * contrast + 8.0));
    float4 rcpWeight = rcp(4.0 * crossWeight + 1.0);
    
    return lerp(center, saturate(((top + bottom + left + right) * crossWeight + center) * rcpWeight), sharpAmount);
}

/*=============================================================================
    Shader Technique: TFAA
=============================================================================*/

technique TFAA
<
    ui_label = "TFAA (2.0)";
    ui_tooltip = "Temporal Filter Anti-Aliasing | Universal Edition\n\nSupports Launchpad, VORT, and Lumenite motion vectors.";
>
{
    pass { VertexShader = PostProcessVS; PixelShader = SaveCur; RenderTarget = texInCurBackup; }
    pass { VertexShader = PostProcessVS; PixelShader = TemporalFilter; RenderTarget = texExpColor; }
    pass { VertexShader = PostProcessVS; PixelShader = SavePost; RenderTarget0 = texExpColorBackup; RenderTarget1 = texDepthBackup; }
    pass { VertexShader = PostProcessVS; PixelShader = Out; }
}