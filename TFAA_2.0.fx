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

/*=============================================================================
    Constants
=============================================================================*/

// 3x3 pixel kernel offsets
static const float2 nOffsets[9] = { 
    float2(-BUFFER_RCP_WIDTH, -BUFFER_RCP_HEIGHT), float2(0, -BUFFER_RCP_HEIGHT), float2(BUFFER_RCP_WIDTH, -BUFFER_RCP_HEIGHT), 
    float2(-BUFFER_RCP_WIDTH,  0),                  float2(0,  0),                  float2(BUFFER_RCP_WIDTH,  0), 
    float2(-BUFFER_RCP_WIDTH,  BUFFER_RCP_HEIGHT),  float2(0,  BUFFER_RCP_HEIGHT),  float2(BUFFER_RCP_WIDTH,  BUFFER_RCP_HEIGHT) 
};

// Mathematically calibrated references
static const float stabilityRef = 0.275251;
static const float sharpenRef   = 0.082575;

// Rec.709 Luma coefficients
static const float3 LumaWeights = float3(0.2126, 0.7152, 0.0722);

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

uniform float UI_TEMPORAL_MULTIPLIER <
    ui_type    = "slider";
    ui_min      = 0.0; 
    ui_max      = 2.0;
    ui_step    = 0.01;
    ui_label   = "Temporal Accumulation Multiplier";
    ui_category= "Temporal Filter";
    ui_tooltip = "Scales the temporal accumulation strength.";
> = 1.0;

uniform float UI_SHARPEN_MULTIPLIER <
    ui_type     = "slider";
    ui_min      = 0.0; 
    ui_max      = 2.0;
    ui_step     = 0.01;
    ui_label    = "Adaptive Sharpening Multiplier";
    ui_category = "Temporal Filter";
    ui_tooltip  = "Scales the adaptive sharpening strength.";
> = 1.0;

uniform bool UI_DEPTH_DEBUG <
    ui_label = "Display Depth Debug";
    ui_category = "Depth Buffer Settings";
> = false;

uniform int UI_DEPTH_ORIENTATION <
    ui_type = "combo";
    ui_label = "Depth Orientation";
    ui_items = "Normal\0Reversed\0";
    ui_category = "Depth Buffer Settings";
> = 0;

uniform bool UI_DEPTH_UPSIDE_DOWN <
    ui_label = "Upside Down";
    ui_category = "Depth Buffer Settings";
> = false;

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
    Format = RGBA16F; 
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
    Format = RGBA16F; 
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
    Format = RGBA16F; 
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

// Rec.709 YCbCr conversion
float3 cvtRgb2YCbCr(float3 rgb)
{
    float y = dot(rgb, LumaWeights);
    return float3(y, (rgb.b - y) * 0.5389, (rgb.r - y) * 0.6350);
}

float3 cvtYCbCr2Rgb(float3 YCbCr)
{
    return float3(
        YCbCr.x + 1.5748 * YCbCr.z,
        YCbCr.x - 0.1873 * YCbCr.y - 0.4681 * YCbCr.z,
        YCbCr.x + 1.8556 * YCbCr.y
    );
}

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
    float2 rcpSize = rcp(texsize);
    ws[0].zw = (tc - 1.0) * rcpSize;
    ws[1].zw = (tc + 1.0 - w1 * rcp(w12)) * rcpSize;
    ws[2].zw = (tc + 2.0) * rcpSize;

    float4 ret = tex2Dlod(source, float2(ws[1].z, ws[0].w), 0) * ws[1].x * ws[0].y;
    ret += tex2Dlod(source, float2(ws[0].z, ws[1].w), 0) * ws[0].x * ws[1].y;
    ret += tex2Dlod(source, float2(ws[1].z, ws[1].w), 0) * ws[1].x * ws[1].y;
    ret += tex2Dlod(source, float2(ws[2].z, ws[1].w), 0) * ws[2].x * ws[1].y;
    ret += tex2Dlod(source, float2(ws[1].z, ws[2].w), 0) * ws[1].x * ws[2].y;
    
    float weightDenom = 1.0 - (f.x - f2.x) * (f.y - f2.y) * 0.25;
    return max(0, ret * rcp(weightDenom));
}

// Linearizes non-linear depth buffer input
float getDepth(float2 texcoord)
{
    if (UI_DEPTH_UPSIDE_DOWN == 1) texcoord.y = 1.0 - texcoord.y;

    float zBuffer = tex2Dlod(smpDepthIn, texcoord, 0).x;

    if (UI_DEPTH_ORIENTATION == 1) zBuffer = 1.0 - zBuffer;

    float expDepth = pow(abs(zBuffer), 250.0);

    return saturate(expDepth);
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
    const float screenScale = BUFFER_HEIGHT / 1080.0;

    float4 sampleCur = tex2Dlod(smpInCurBackup, texcoord, 0);
    float3 centerCvt = cvtRgb2YCbCr(sampleCur.rgb);

    int closestDepthIndex = 4;
    float4 minimumCvt = float4(centerCvt, sampleCur.a);
    float4 maximumCvt = float4(centerCvt, sampleCur.a);

    [unroll]
    for (int i = 0; i < 9; i++)
    {
        if (i == 4) continue;

        float4 neighborhoodSample = tex2Dlod(smpInCurBackup, texcoord + nOffsets[i], 0);
        float4 cvt = float4(cvtRgb2YCbCr(neighborhoodSample.rgb), neighborhoodSample.a);

        if (neighborhoodSample.a < minimumCvt.a) closestDepthIndex = i;

        minimumCvt = min(minimumCvt, cvt);
        maximumCvt = max(maximumCvt, cvt);
    }

    float2 motion = get_universal_motion(texcoord + nOffsets[closestDepthIndex]);
    float2 lastSamplePos = texcoord + motion;
    
    float zenteonOcclusion = 1.0;
    if (UI_MOTION_SOURCE == 3) {
        zenteonOcclusion = tex2Dlod(sZenteonDOC, texcoord, 0).x;
    }

    float lastDepth = tex2Dlod(smpDepthBackup, lastSamplePos, 0).r;
    float4 sampleExp = saturate(bicubic_5(smpExpColorBackup, lastSamplePos));

    float diff = saturate(maximumCvt.r - minimumCvt.r);
    float localContrast = diff;

    float motionMagnitude = (length(motion) * 20.0) / screenScale; 
    float speedFactor = 1.0 - saturate(motionMagnitude * 1.0);

    float depthDelta = saturate(minimumCvt.a - lastDepth) * rcp(max(sampleCur.a, 0.0001));
    float dD4 = saturate(depthDelta * 4.0);
    float dD4Sq = dD4 * dD4;
    float depthMask = saturate(1.0 - (dD4Sq * dD4Sq));

    float strength = saturate(stabilityRef * UI_TEMPORAL_MULTIPLIER);
    float weight = lerp(0.50, 0.98, strength);

    weight = weight * (0.8 + localContrast);
    weight = clamp(weight * speedFactor * depthMask * zenteonOcclusion, 0.0, 0.95);

    float4 sampleExpClamped = float4(cvtYCbCr2Rgb(clamp(cvtRgb2YCbCr(sampleExp.rgb), minimumCvt.rgb, maximumCvt.rgb)), sampleExp.a);

    // Color blending in non-linear power space
    const static float correctionFactor = 2;
    float3 sampleCurSq = sampleCur.rgb * sampleCur.rgb;
    float3 sampleExpSq = sampleExpClamped.rgb * sampleExpClamped.rgb;
    float3 blendedColor = sqrt(saturate(lerp(sampleCurSq, sampleExpSq, weight)));

    float weightBalance = saturate(weight * 1.0526); 

    float motionThreshold = saturate(motionMagnitude * 5.0 - 0.25);
    float reconstructionCurve = motionThreshold * motionThreshold * (3.0 - 2.0 * motionThreshold);

    float lumaError = saturate(abs(centerCvt.x - minimumCvt.x) * (33.333333 * screenScale));
    float sharpAmount = sharpenRef * UI_SHARPEN_MULTIPLIER;

    float sharp = reconstructionCurve * weightBalance * lumaError * (localContrast + (1.0 - weight)) * sharpAmount;

    sharp = min(saturate(sharp * 3.333333 * depthMask), 0.333 * screenScale);

    return float4(blendedColor, sharp);

}

void SavePost(float4 position : SV_Position, float2 texcoord : TEXCOORD, out float4 lastExpOut : SV_Target0, out float depthOnly : SV_Target1)
{
    lastExpOut = tex2Dlod(smpExpColor, texcoord, 0);
    depthOnly = getDepth(texcoord);
}

float4 Out(float4 position : SV_Position, float2 texcoord : TEXCOORD ) : SV_Target
{
    if (UI_DEPTH_DEBUG) return float4(getDepth(texcoord).xxx, 1.0);

    const float2 offset = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

    float4 center = tex2D(smpExpColor, texcoord);

    float3 t = tex2D(smpExpColor, texcoord + float2(0, -offset.y)).rgb;
    float3 b = tex2D(smpExpColor, texcoord + float2(0,  offset.y)).rgb;
    float3 l = tex2D(smpExpColor, texcoord + float2(-offset.x, 0)).rgb;
    float3 r = tex2D(smpExpColor, texcoord + float2( offset.x, 0)).rgb;

    float activeSharp = center.a; 

    float3 edgeDetail = (center.rgb * 4.0) - (t + b + l + r);

    return float4(saturate(center.rgb + (edgeDetail * activeSharp)), 1.0);
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
