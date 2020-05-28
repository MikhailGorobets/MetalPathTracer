//
//  GeometryShader.metal
//  RayTracing
//
//  Created by Mikhail Gorobets on 19.05.2020.
//  Copyright © 2020 Mikhail Gorobets. All rights reserved.
//

#include <metal_stdlib>
#include <simd/simd.h>
#import "Common.h"

using namespace metal;


float3x3 GetTangentSpace(float3 normal) {
    const float3 helper = abs(normal.x) > (1 - DISTANCE_EPSILON) ? float3(0, 0, 1) : float3(1, 0, 0);
    const float3 tangent = normalize(cross(normal, helper));
    const float3 binormal = normalize(cross(normal, tangent));
    return float3x3(tangent, binormal, normal);
}


float3 GGX_SampleHemisphere(float3 normal, float alpha, thread CRNG& rng) {
    float2 e = float2(Rand(rng), Rand(rng));
    float phi = 2.0 * PI * e.x;
    float cosTheta = sqrt(max(0.0f, (1.0 - e.y) / (1.0 + alpha * alpha * e.y - e.y)));
    float sinTheta = sqrt(max(0.0f, 1.0 - cosTheta * cosTheta));
    return GetTangentSpace(normal) * float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
}

Ray CreateCameraRay(float4x4 invViewProj, uint2 id, float2 offset, float2 dimension) {
    
    float2 ncdXY = 2.0f * (float2(id.x, dimension.y - id.y) + offset) / dimension - 1.0f;
    
    float4 rayStart = invViewProj * float4(ncdXY, +0.0f, 1.0f);
    float4 rayEnd   = invViewProj * float4(ncdXY, +1.0f, 1.0f);
    
    rayStart.xyz /= rayStart.w;
    rayEnd.xyz   /= rayEnd.w;
    
    Ray ray;
    ray.base.direction = normalize(rayEnd.xyz - rayStart.xyz);
    ray.base.origin = rayStart.xyz;
    ray.base.minDistance = 0;
    ray.base.maxDistance = length(rayEnd.xyz - rayStart.xyz);
    ray.radiance = 0.0;
    ray.throughput = 1.0;
    ray.bounces = 0;
    
    return ray;
}


kernel void GenerateRaysKernel(constant ApplicationData & appData [[buffer(0)]],
                               device Ray* rays [[buffer(1)]],
                               uint2 coordinates [[thread_position_in_grid]],
                               uint2 size [[threads_per_grid]]) {
    uint rayIDx = coordinates.x + coordinates.y * size.x;
    rays[rayIDx] = CreateCameraRay(appData.invViewProjectMatrix, coordinates, appData.frameOffset, float2(size.x, size.y));
}


kernel void HandleIntersections(device const Intersection* intersections [[buffer(0)]],
                                device const Material* materials[[buffer(1)]],
                                device const Triangle* triangles [[buffer(2)]],
                                device const Vertex* vertices [[buffer(3)]],
                                device packed_uint3* indices [[buffer(4)]],
                                device Ray* rays [[buffer(5)]],
                                constant ApplicationData& appData [[buffer(6)]],
                                uint2 coordinates [[thread_position_in_grid]],
                                uint2 size [[threads_per_grid]]) {
    
    uint rayIndex = coordinates.x + coordinates.y * size.x;
    device Intersection const& intersect = intersections[rayIndex];
    device Ray& currentRay = rays[rayIndex];
    
    if (intersect.distance < DISTANCE_EPSILON) {
        currentRay.base.maxDistance = -1.0;
        return;
    }
  
    thread CRNG rng = InitCRND(coordinates, appData.frameIndex + currentRay.bounces);
    device const Triangle& triangle = triangles[intersect.primitiveIndex];
    device const Material& material = materials[triangle.materialIndex];
   

    device const packed_uint3& triangleIndices = indices[intersect.primitiveIndex];
    device const Vertex& v0 = vertices[triangleIndices.x];
    device const Vertex& v1 = vertices[triangleIndices.y];
    device const Vertex& v2 = vertices[triangleIndices.z];
    
    Vertex currentVertex = Interpolate(v0, v1, v2, intersect.coordinates);

    if (length(material.emissive) > 0.0) {
        currentRay.radiance += material.emissive * currentRay.throughput;
    }
    
    //pdf = cos(theta) / PI
    currentRay.base.origin = currentVertex.position + currentVertex.normal * DISTANCE_EPSILON;
    currentRay.base.direction = GGX_SampleHemisphere(currentVertex.normal, 1.0, rng);
    currentRay.throughput *= material.diffuse;
    currentRay.bounces++;

}


kernel void AccumulateImage(texture2d<float, access::read_write> image [[texture(0)]],
                            device Ray* rays [[buffer(0)]],
                            constant ApplicationData& appData [[buffer(1)]],
                            uint2 coordinates [[thread_position_in_grid]],
                            uint2 size [[threads_per_grid]]) {
    uint rayIndex = coordinates.x + coordinates.y * size.x;
    float4 outputColor = float4(rays[rayIndex].radiance, 1.0);

    if (appData.frameIndex > 0) {
        float4 storedColor = image.read(coordinates);
        outputColor = mix(outputColor, storedColor, float(appData.frameIndex) / float(appData.frameIndex + 1));
    }

    image.write(outputColor, coordinates);
}
