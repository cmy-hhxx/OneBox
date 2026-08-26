enum AsciiShaderSource {
    // Luminance quantization and character-atlas sampling are adapted from
    // ascii-simulation-art-console, Copyright (c) 2026 By Skent (@SkentSun), MIT License.
    static let source = #"""
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        struct Uniforms {
            float4 darkColor;
            float4 middleColor;
            float4 lightColor;
            float4 backgroundColor;
            float4 transform;
            float4 geometry;
            float4 settings;
            float4 animation;
        };

        vertex VertexOut asciiVertex(uint vertexID [[vertex_id]]) {
            float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
            VertexOut out;
            out.position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
            out.uv = uv;
            return out;
        }

        fragment float4 asciiFragment(
            VertexOut in [[stage_in]],
            texture2d<float> sourceTexture [[texture(0)]],
            texture2d<float> glyphTexture [[texture(1)]],
            sampler linearSampler [[sampler(0)]],
            constant Uniforms &uniforms [[buffer(0)]])
        {
            float2 gridSize = max(uniforms.geometry.xy, float2(1.0));
            float2 cell = floor(in.uv * gridSize);
            float2 cellUV = (cell + 0.5) / gridSize;
            float2 localUV = fract(in.uv * gridSize);

            float sourceAspect = uniforms.geometry.z;
            float canvasAspect = uniforms.geometry.w;
            float2 fitted = sourceAspect > canvasAspect
                ? float2(1.0, canvasAspect / sourceAspect)
                : float2(sourceAspect / canvasAspect, 1.0);
            float2 displayed = fitted * uniforms.transform.x;
            float2 center = float2(0.5) + uniforms.transform.yz;
            float2 sourceUV = (cellUV - center) / displayed + 0.5;

            float style = uniforms.settings.w;
            float time = uniforms.animation.x;
            float strength = uniforms.animation.y;
            if (style == 2.0) {
                sourceUV.x += sin(cellUV.y * 18.0 + time * 2.2) * strength * 0.045;
            }

            bool inside = all(sourceUV >= 0.0) && all(sourceUV <= 1.0);
            float4 source = inside ? sourceTexture.sample(linearSampler, sourceUV) : float4(0.0);
            float luminance = dot(source.rgb, float3(0.2126, 0.7152, 0.0722));
            luminance = clamp((luminance - 0.5) * uniforms.settings.y + 0.5, 0.0, 1.0);
            if (uniforms.settings.z > 0.5) {
                luminance = 1.0 - luminance;
            }

            if (style == 1.0) {
                float rain = sin(cell.x * 1.7 + cell.y * 0.31 - time * 6.0);
                luminance = clamp(luminance - max(rain, 0.0) * strength * 0.35, 0.0, 1.0);
            } else if (style == 3.0) {
                float scan = 1.0 - abs(fract(cellUV.y - time * 0.35) * 2.0 - 1.0);
                luminance = clamp(luminance - pow(scan, 12.0) * strength * 0.55, 0.0, 1.0);
            }

            float intensity = clamp(1.0 - luminance + (uniforms.settings.x - 0.5) * 0.8, 0.0, 1.0);
            float glyphCount = max(uniforms.animation.z, 1.0);
            float glyphIndex = floor(intensity * (glyphCount - 1.0) + 0.5);
            float2 atlasUV = float2((glyphIndex + localUV.x) / glyphCount, 1.0 - localUV.y);
            float glyphMask = glyphTexture.sample(linearSampler, atlasUV).a * source.a;

            float gradientPosition = clamp((cellUV.x + cellUV.y) * 0.5, 0.0, 1.0);
            float4 foreground = gradientPosition < 0.5
                ? mix(uniforms.darkColor, uniforms.middleColor, gradientPosition * 2.0)
                : mix(uniforms.middleColor, uniforms.lightColor, (gradientPosition - 0.5) * 2.0);

            if (uniforms.animation.w > 0.5) {
                return float4(foreground.rgb * glyphMask, glyphMask);
            }
            return float4(mix(uniforms.backgroundColor.rgb, foreground.rgb, glyphMask), 1.0);
        }
        """#
}
