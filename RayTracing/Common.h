//
//  ShaderTypes.h
//  RayTracing
//
//  Created by Mikhail Gorobets on 19.05.2020.
//  Copyright © 2020 Mikhail Gorobets. All rights reserved.
//

#pragma one

#include <MetalPerformanceShaders/MetalPerformanceShaders.h>


#define PI                  3.1415926536
#define DISTANCE_EPSILON    0.001
#define MATERIAL_DIFFUSE    1
#define MATERIAL_LIGHT      100
#define NOISE_BLOCK_SIZE    16


struct Ray {
    MPSRayOriginMinDistanceDirectionMaxDistance base;
    packed_float3 radiance;
    uint32_t      bounces;
    packed_float3 throughput;
};


struct CRNG {
    uint2 Seed;
};


struct Vertex {
    packed_float3 position;
    packed_float3 normal;
    packed_float2 texcoord;
};

struct Material {
    packed_float3 diffuse;
    uint32_t      type = MATERIAL_DIFFUSE;
    packed_float3 emissive;
};

struct Triangle {
    uint32_t materialIndex;
};


using Intersection = MPSIntersectionDistancePrimitiveIndexCoordinates;

struct ApplicationData {
    float4x4 viewProjectMatrix;
    float4x4 invViewProjectMatrix;
    uint32_t frameIndex;
    uint32_t emitterTriaglesCount;
    float2   frameOffset;
};



Vertex Interpolate(device const Vertex& v0, device const Vertex& v1, device const Vertex& v2, float3 barycentric) {
    float u = barycentric.x;
    float v = barycentric.y;
    float w = barycentric.z;

    Vertex result;
    result.position = v0.position * u + v1.position * v + v2.position * w;
    result.normal   = v0.normal   * u + v1.normal   * v + v2.normal   * w;
    result.texcoord = v0.texcoord * u + v1.texcoord * v + v2.texcoord * w;
    return result;
}

Vertex Interpolate(device const Vertex& v0, device const Vertex& v1, device const Vertex& v2, float2 barycentric) {
    float u = barycentric.x;
    float v = barycentric.y;
    float w = 1.0f - u - v;

    Vertex result;
    result.position = v0.position * u + v1.position * v + v2.position * w;
    result.normal   = v0.normal   * u + v1.normal   * v + v2.normal   * w;
    result.texcoord = v0.texcoord * u + v1.texcoord * v + v2.texcoord * w;
    return result;
}

uint Hash(uint seed) {
    seed = (seed ^ 61) ^ (seed >> 16);
    seed *= 9;
    seed = seed ^ (seed >> 4);
    seed *= 0x27d4eb2d;
    seed = seed ^ (seed >> 15);
    return seed;
}

uint RngNext(thread CRNG& rng) {
    uint result = rng.Seed.x * 0x9e3779bb;

    rng.Seed.y ^= rng.Seed.x;
    rng.Seed.x = ((rng.Seed.x << 26) | (rng.Seed.x >> (32 - 26))) ^ rng.Seed.y ^ (rng.Seed.y << 9);
    rng.Seed.y = (rng.Seed.x << 13) | (rng.Seed.x >> (32 - 13));

    return result;
}

float Rand(thread CRNG& rng) {
    uint u = 0x3f800000 | (RngNext(rng) >> 9);
    return as_type<float>(u) - 1.0;
}

CRNG InitCRND(uint2 id, uint frameIndex) {
    uint s0 = (id.x << 16) | id.y;
    uint s1 = frameIndex;

    CRNG rng;
    rng.Seed.x = Hash(s0);
    rng.Seed.y = Hash(s1);
    RngNext(rng);
    return rng;
}
