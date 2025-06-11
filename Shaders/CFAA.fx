/*
  CRAZY FAST ANTI ALIASING (CFAA) 
    
  Author u/Not4Fame
  Copyright = Copy it right ;) which means, as long as you give credits, have fun.
 
  Designed primarily to take care of artifacts and aliasing caused when turning TAA off in games, 
  where the game was designed around a forced TAA.
 
  Will also work generally well for any other application as a very lightweight but effective AA solution.
 
  Uses two separate masks (noise and edge) to detect artifacts/edges and combines them into one.
 
  A full 3x3 Gussian Kernel is used for blur.
  
  HDR/SDR selection for Luminance calculation based on Rec. 2020 or Rec. 709 weights.
 
  A luminance threshold will bypass pixels under a certain luminance to shave off major compute cost.
 
*/



#include "ReShade.fxh"

#define PX BUFFER_PIXEL_SIZE


uniform bool HDR <
    ui_type = "checkbox";
    ui_label = "HDR";
    ui_tooltip= "Use Rec. 2020 or Rec. 709 weights for luma calculation";
    ui_text = 
             "CRAZY FAST ANTI ALIASING by u/Not4Fame \n"
             "\n"
             "Select HDR if using on HDR content.\n"
             "First select \"Show Noise Mask\" and adjust \"Noise Threshold\"\n"
             "Next select \"Show Edge Mask\" and adjust \"Edge Threshold\"\n"
             "Next unselect \"Show Edge Mask\" and \"Show Noise Mask\"\n"
             "And adjust \"Blur Strength\" for masked pixels\n"
             "Now raise \"Luminance Threshold\" to save performance\n"
             "Remember raising \"Luminance Threshold\" bypasses darker pixels\n"
             "So watch carefully when raising \"Luminance Threshold\"\n"
             "Helps to turn mask views on when raising \"Luminance Threshold\"\n"
             "\n"
             "Enjoy\n"
             "\n";
> = false;


uniform bool ShowNoise <
    ui_type = "checkbox";
    ui_label = "Show Noise Mask";
    ui_tooltip= "Displays the noise mask";
> = false;

uniform float NoiseThreshold <
    ui_type = "drag";
    ui_min = 0.001; ui_max = 1;
    ui_step = 0.001;
    ui_label = "Noise Threshold";
    ui_tooltip= "Adjusts sensitivity of Noise detection";
> = 0.200;

uniform bool ShowEdges <
    ui_type = "checkbox";
    ui_label = "Show Edge Mask";
    ui_tooltip= "Displays the edge mask";
> = false;

uniform float EdgeThreshold <
    ui_type = "drag";
    ui_min = 0.001; ui_max = 1;
    ui_step = 0.001;
    ui_label = "Edge Threshold";
    ui_tooltip= "Adjusts sensitivity of Edge detection";
> = 0.050;

uniform float Strength <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 0.01;
    ui_label = "Blur Strength";
    ui_tooltip= "Strength of blur that will be applied on the combined noise+edge mask";
> = 0.50;

uniform float LuminanceThreshold <
    ui_type = "drag";
    ui_min = 0.001; ui_max = 1;
    ui_step = 0.001;
    ui_label = "Luminance Threshold";
    ui_tooltip= "Shader will ONLY work on pixels above this luminance (passing darker pixels untouched), as a result will MASSIVELY shave off compute and increase performance";
> = 0.00;


namespace CFAA
{
    texture2D BackBuffer : COLOR;
    sampler2D sBackBuffer { Texture = BackBuffer; };

    float ComputeLuma(float3 color)
    {
        if (HDR)
        {
            return dot(color, float3(0.2627, 0.6780, 0.0593));
        }
        else
        {
            return dot(color, float3(0.2126, 0.7152, 0.0722));
        }
    }

    float ComputeNoise(float center_luma, float top_luma, float left_luma, float bottom_luma, float right_luma)
    {
        float maxDiff = max(abs(center_luma - top_luma), max(abs(center_luma - left_luma), max(abs(center_luma - bottom_luma), abs(center_luma - right_luma))));
        return step(NoiseThreshold, maxDiff);
    }

    float Prewitt(float3 top, float3 topLeft, float3 topRight, float3 left, float3 center, float3 right, float3 bottomLeft, float3 bottom, float3 bottomRight)
    {
        float3 Gx = (topLeft + 2 * top + topRight - bottomLeft - 2 * bottom - bottomRight) * 0.1111;
        float3 Gy = (topLeft + 2 * left + bottomLeft - topRight - 2 * right - bottomRight) * 0.1111;
        float3 gradient = sqrt(Gx * Gx + Gy * Gy);
        float3 edgeMask = step(EdgeThreshold, gradient);
        return max(edgeMask.x, max(edgeMask.y, edgeMask.z));
    }

    float3 GaussianBlur(float3 center, float3 top, float3 left, float3 bottom, float3 right, float3 topLeft, float3 topRight, float3 bottomLeft, float3 bottomRight)
    {
        float3 blurred = (center * 4.0 + 
                          topLeft + 2 * top + topRight + 
                          2 * left + 2 * right + 
                          bottomLeft + 2 * bottom + bottomRight) * 0.0625;
        return lerp(center, blurred, Strength);
    }

    float4 PS_CFAA(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float3 center = tex2D(sBackBuffer, uv).rgb;
        float center_luma = ComputeLuma(center);
        float4 result = float4(center, 1.0);
        

        if (center_luma > LuminanceThreshold)
            {
                float3 top = tex2D(sBackBuffer, uv + float2(0, -PX.y)).rgb;
                float3 left = tex2D(sBackBuffer, uv + float2(-PX.x, 0)).rgb;
                float3 bottom = tex2D(sBackBuffer, uv + float2(0, PX.y)).rgb;
                float3 right = tex2D(sBackBuffer, uv + float2(PX.x, 0)).rgb;
                float3 topLeft = tex2D(sBackBuffer, uv + float2(-PX.x, -PX.y)).rgb;
                float3 topRight = tex2D(sBackBuffer, uv + float2(PX.x, -PX.y)).rgb;
                float3 bottomLeft = tex2D(sBackBuffer, uv + float2(-PX.x, PX.y)).rgb;
                float3 bottomRight = tex2D(sBackBuffer, uv + float2(PX.x, PX.y)).rgb;
                
                float top_luma = ComputeLuma(top);
                float left_luma = ComputeLuma(left);
                float bottom_luma = ComputeLuma(bottom);
                float right_luma = ComputeLuma(right);

                float noise = ComputeNoise(center_luma, top_luma, left_luma, bottom_luma, right_luma);
                float edge = Prewitt(top, topLeft, topRight, left, center, right, bottomLeft, bottom, bottomRight);

                float combinedMask = max(noise, edge);

                if (combinedMask == 1)
                        {
                            center = GaussianBlur(center, top, left, bottom, right, topLeft, topRight, bottomLeft, bottomRight);
                        }
               
                center = ShowNoise ? lerp(center, float3(noise, 0, 0), noise) : center;
                center = ShowEdges ? lerp(center, float3(0, 0, edge), edge) : center;

                result = float4(center, 1.0);
            }

        return result;
    }

    technique CFAA
    {
        pass
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_CFAA;
        }
    }
}