//
//  Shaders.metal
//  RadialColorPicker
//
//  Created by Reza on 5/29/23.
//

#include <metal_stdlib>
#import "ShaderTypes.h"
#include <simd/simd.h>
using namespace metal;

typedef struct {
    float3 position [[attribute(VertexAttributePosition)]];
    float3 normal [[attribute(VertexAttributeNormal)]];
} Vertex;

typedef struct {
    float4 position [[position]];
    float3 normal;
    float3 fragWorldPos;
} PassThroughVertex;

PassThroughVertex vertex vertexShader(Vertex in [[stage_in]],
                                      constant Uniforms& uniforms [[ buffer(BufferIndexUniforms) ]])
{
    PassThroughVertex out;
    
    float4 position = float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.transform * position;
    
    float4 localNormal = float4(in.normal, 0.0);
    out.normal = normalize(uniforms.transform * localNormal).xyz;
    out.fragWorldPos = (uniforms.transform * float4(in.position, 1.0)).xyz;
    
    return out;
}

float4 fragment fragmentShader(PassThroughVertex in [[stage_in]],
                               constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]])
{
    //return float4(1.0, 0.0, 0.0, 1.0);
    
    /// Calculating The Specular Component
    float3 cameraPos = vector_float3(uniforms.cameraTransform.columns[3].x, uniforms.cameraTransform.columns[3].y, uniforms.cameraTransform.columns[3].z);
    float3 lightDirection = uniforms.lightDirection; // For Other Types of Light must be normalize(lightPos - FragPos)
    float3 viewDirectioin = normalize(cameraPos - in.fragWorldPos);
    float3 halfwayDir = normalize(/*lightDirection +*/ viewDirectioin);
    
    // Diffuse Term
    //float diffuseAmt = max(0.0, dot(uniforms.lightDirection, in.normal));
    float diffuseAmt = 0.7;
    float4 meshCol = float4(uniforms.color, 1.0);
    float3 diffuseColor = meshCol.xyz * uniforms.lightColor * diffuseAmt;
    
    // Ambient
    float3 ambCol = uniforms.lightColor;
    float3 ambient = ambCol * meshCol.xyz;
    
    // Specular Term
    float spec = pow(max(dot(in.normal, halfwayDir), 0.0), 0.1 * 50);
    float3 specularV = uniforms.lightColor * 0.5 * spec;
    
    return float4(diffuseColor + ambient + specularV, 1.0);
}
