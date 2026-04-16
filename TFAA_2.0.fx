/*=============================================================================
    TFAA 2.0 - Universal Edition
    
    Copyright, Jakob Wapenhensch
    Modified by maksymilianlt (2026)
    
    License: CC BY-NC 4.0 (https://creativecommons.org/licenses/by-nc/4.0/)
=============================================================================*/

/*=============================================================================
    Resources
=============================================================================*/

#include "ReShadeUI.fxh"
#include "ReShade.fxh"

#ifndef RESHADE_DEPTH_LINEARIZATION_FAR_PLANE
    #define RESHADE_DEPTH_LINEARIZATION_FAR_PLANE 1000.0
#endif

/*=============================================================================
    Setup
=============================================================================*/

#ifndef TFAA_USE_OPENGL_COMPATIBILITY
    #define TFAA_USE_OPENGL_COMPATIBILITY 0
#endif

// Select high-precision accumulation format unless OpenGL restricted
#if TFAA_USE_OPENGL_COMPATIBILITY
    #define TFAA_FORMAT RGBA8
#else
    #define TFAA_FORMAT RGBA16F
#endif

/*=============================================================================
    Constants
=============================================================================*/

uniform float frametime < source = "frametime"; >;

// Calibration target for frametime-independent blending
static const float fpsConst = (1000.0 / 48.0);

// 3x3 pixel kernel offsets
static const float2 nOffsets[9] = { 
    float2(-1, -1), float2(0, -1), float2(1, -1), 
    float2(-1,  0), float2(0,  0), float2(1,  0), 
    float2(-1,  1), float2(0,  1), float2(1,  1) 
};

/*=============================================================================
    UI
=============================================================================*/

uniform int UI_MOTION_SOURCE <
    ui_type = "combo";
    ui_label = "Motion Vector Source";
    ui_items = "iMMERSE: Launchpad\0vort_MotionEffects\0LUMENITE: Kernel\0Zenteon: Motion\0";
    ui_category = "Temporal Filter";
    ui_tooltip = "Select the provider for motion vectors.";
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

// Primary input buffers
texture texDepthIn : DEPTH;
sampler smpDepthIn { 
    Texture = texDepthIn; 
};

texture texInCur : COLOR;
sampler smpInCur { 
    Texture   = texInCur; 
    AddressU  = Clamp; 
    AddressV  = Clamp; 
    MipFilter = Linear; 
    MinFilter = Linear; 
    MagFilter = Linear; 
};

// Intermediate and history accumulation buffers
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

// Point-sampled depth history for precise motion rejection
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
    Utilities
=============================================================================*/

float4 tex2Dlod(sampler s, float2 uv, float mip) { return tex2Dlod(s, float4(uv, 0, mip)); }

// Rec.601 YCbCr conversion for luma-based neighborhood clipping
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

float3 cvtRgb2whatever(float3 rgb) { return cvtRgb2YCbCr(rgb); }
float3 cvtWhatever2Rgb(float3 whatever) { return cvtYCbCr2Rgb(whatever); }

// 5-tap Catmull-Rom bicubic filter for high-fidelity history reconstruction
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

float4 sampleHistory(sampler2D historySampler, float2 texcoord)
{
    return bicubic_5(historySampler, texcoord);
}

// Linearizes non-linear depth buffer input
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
    Motion Bridge
=============================================================================*/

// Resource declarations for external motion vector providers
texture2D texMotionVectors { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
texture2D tDOC              { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8;    };
sampler2D sZenteonMV  { Texture = texMotionVectors; };
sampler2D sZenteonDOC { Texture = tDOC; };

texture2D tLumaFlow { Width = BUFFER_WIDTH/8; Height = BUFFER_HEIGHT/8; Format = RG16F; };
sampler2D sLumaFlow { 
    Texture = tLumaFlow; 
    MagFilter = POINT; MinFilter = POINT; 
    AddressU = CLAMP; AddressV = CLAMP; 
};

texture2D MotVectTexVort { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
sampler2D sMotVectTexVort { 
    Texture = MotVectTexVort; 
    MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; 
    AddressU = CLAMP; AddressV = CLAMP; 
};

namespace Deferred 
{
    texture MotionVectorsTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
    sampler sMotionVectorsTex { Texture = MotionVectorsTex; };

    float2 get_motion(float2 uv)
    {
        return tex2Dlod(sMotionVectorsTex, uv, 0).xy;
    }
}

// Routes motion vector data from selected source to the temporal resolver
float2 get_universal_motion(float2 uv)
{
    if (UI_MOTION_SOURCE == 0)
    {
        return Deferred::get_motion(uv);
    }
    else if (UI_MOTION_SOURCE == 1)
    {
        return tex2Dlod(sMotVectTexVort, uv, 0).rg;
    }
    else if (UI_MOTION_SOURCE == 2)
    {
        return tex2Dlod(sLumaFlow, uv, 0).xy;
    }
    else
    {
        return tex2Dlod(sZenteonMV, uv, 0).xy;
    }
}

/*=============================================================================
    Shader Passes
=============================================================================*/

float4 SaveCur(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target0
{
    return float4(tex2Dlod(smpInCur, texcoord, 0).rgb, getDepth(texcoord));
}

float4 TemporalFilter(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 sampleCur = tex2Dlod(smpInCurBackup, texcoord, 0);
    float4 cvtColorCur = float4(cvtRgb2whatever(sampleCur.rgb), sampleCur.a);

    int closestDepthIndex = 4;
    float4 minimumCvt = 2;
    float4 maximumCvt = -1;

    // 3x3 neighborhood clipping search
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
    
    float zenteonOcclusion = 1.0;
    if (UI_MOTION_SOURCE == 3) {
        zenteonOcclusion = tex2Dlod(sZenteonDOC, texcoord, 0).x;
    }

    float lastDepth = tex2Dlod(smpDepthBackup, lastSamplePos, 0).r;
    float4 sampleExp = saturate(sampleHistory(smpExpColorBackup, lastSamplePos));

    float localContrast = saturate(pow(abs(maximumCvt.r - minimumCvt.r), 0.75));
    
    float motionMagnitude = length(motion) * 160.0; 
    float speedFactor = 1.0 - pow(saturate(motionMagnitude * 0.125), 0.5);

    float depthDelta = max(0, saturate(minimumCvt.a - lastDepth)) / max(sampleCur.a, 0.0001);
    float depthMask = saturate(1.0 - pow(depthDelta * 4, 4));

    // Normalize temporal accumulation for 48 FPS baseline
    float baseLeak = 1.0 - lerp(0.50, 0.98, UI_TEMPORAL_FILTER_STRENGTH);
    float adjustedLeak = pow(abs(baseLeak), frametime / fpsConst);

    float weight = saturate(1.0 - adjustedLeak);
    weight = lerp(weight, weight * (0.6 + localContrast * 2), 0.5);
    weight = clamp(weight * speedFactor * depthMask * zenteonOcclusion, 0.0, 0.95);

    float4 sampleExpClamped = float4(cvtWhatever2Rgb(clamp(cvtRgb2whatever(sampleExp.rgb), minimumCvt.rgb, maximumCvt.rgb)), sampleExp.a);

    // Color blending in non-linear power space
    const static float correctionFactor = 2;
    float3 blendedColor = saturate(pow(lerp(pow(sampleCur.rgb, correctionFactor), pow(sampleExpClamped.rgb, correctionFactor), weight), (1.0 / correctionFactor)));

    float motionKick = motionMagnitude > 0.0 ? 0.2 : 0.0;
    float reconstructionCurve = saturate(motionKick + pow(saturate(motionMagnitude), 0.35));
    
    float lumaError = saturate(abs(sampleCur.r - sampleExpClamped.r) * 25.0);

    float sharp = reconstructionCurve * lumaError * weight * (1.25 + localContrast) * UI_POST_SHARPEN;
    
    sharp = saturate(sharp * 3.15 * depthMask);

    return float4(blendedColor, sharp);
}

void SavePost(float4 position : SV_Position, float2 texcoord : TEXCOORD, out float4 lastExpOut : SV_Target0, out float depthOnly : SV_Target1)
{
    lastExpOut = tex2Dlod(smpExpColor, texcoord, 0);
    depthOnly = getDepth(texcoord);
}

float4 Out(float4 position : SV_Position, float2 texcoord : TEXCOORD ) : SV_Target
{
    float4 neighbors[9];
    for(int i = 0; i < 9; i++)
    {
        neighbors[i] = tex2Dlod(smpExpColor, texcoord + (nOffsets[i] * ReShade::PixelSize), 0);
    }

    float4 topLeft     = neighbors[0];
    float4 top         = neighbors[1];
    float4 topRight    = neighbors[2];
    float4 left        = neighbors[3];
    float4 center      = neighbors[4];
    float4 right       = neighbors[5];
    float4 bottomLeft  = neighbors[6];
    float4 bottom      = neighbors[7];
    float4 bottomRight = neighbors[8];

    float4 maxBox = max(max(top, max(bottom, max(left, max(right, center)))), max(topLeft, max(topRight, max(bottomLeft, bottomRight))));
    float4 minBox = min(min(top, min(bottom, min(left, min(right, center)))), min(topLeft, min(topRight, min(bottomLeft, bottomRight))));

    // Apply sharpening using CAS weighting logic
    float contrast    = 0.0;
    float sharpAmount = saturate(maxBox.a); 

    float4 crossWeight = -rcp(rsqrt(saturate(min(minBox, 1.0 - maxBox) * rcp(maxBox))) * (-3.0 * contrast + 8.0));
    float4 rcpWeight = rcp(4.0 * crossWeight + 1.0);
    
    return lerp(center, saturate(((top + bottom + left + right) * crossWeight + center) * rcpWeight), sharpAmount);
}

/*=============================================================================
    Technique
=============================================================================*/

technique TFAA
<
    ui_label = "TFAA 2.0";
    ui_tooltip = "Temporal Filter Anti-Aliasing";
>
{
    pass { VertexShader = PostProcessVS; PixelShader = SaveCur; RenderTarget = texInCurBackup; }
    pass { VertexShader = PostProcessVS; PixelShader = TemporalFilter; RenderTarget = texExpColor; }
    pass { VertexShader = PostProcessVS; PixelShader = SavePost; RenderTarget0 = texExpColorBackup; RenderTarget1 = texDepthBackup; }
    pass { VertexShader = PostProcessVS; PixelShader = Out; }
}
