//
//  ShaderTypes.h
//  RadialColorPicker
//
//  Created by Reza on 5/29/23.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name: _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

typedef NS_ENUM(NSInteger, VertexAttribute)
{
    VertexAttributePosition = 0,
    VertexAttributeNormal   = 1
};

typedef NS_ENUM(NSInteger, RibbonVertexAttribute)
{
    RibbonVertexAttributePosition = 0,
    RibbonVertexAttributeColor    = 1
};

typedef NS_ENUM(NSInteger, RibbonBufferIndex)
{
    RibbonBufferIndexPositions = 0,
    RibbonBufferIndexColors    = 1,
    RibbonBufferIndexUniforms  = 2
};

typedef NS_ENUM(NSInteger, BufferIndex)
{
    BufferIndexMeshPositions = 0,
    BufferIndexUniforms      = 1
};

typedef NS_ENUM(NSInteger, ShadowVertexAttribute)
{
    ShadowVertexAttributePosition = 0
};

typedef NS_ENUM(NSInteger, ShadowBufferIndex)
{
    ShadowBufferIndexPositions        = 0,
    ShadowBufferIndexInstanceUniforms = 1,
    ShadowBufferIndexUniforms         = 2
};

typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 transform;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 cameraTransform;
    simd_float3 lightDirection;
    simd_float3 lightColor;
    simd_float3     color;
} Uniforms;

typedef struct
{
    matrix_float4x4 projection;
    matrix_float4x4 transform;
} RibbonUniforms;

typedef struct
{
    matrix_float4x4 projection;
} ShadowUniforms;

typedef struct
{
    matrix_float4x4 transform;
    simd_float4     color;
} ShadowInstanceUniforms;

#endif /* ShaderTypes_h */
