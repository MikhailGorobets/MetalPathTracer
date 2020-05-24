//
//  GeometryProvider.swift
//  RayTracing
//
//  Created by Mikhail Gorobets on 20.05.2020.
//  Copyright © 2020 Mikhail Gorobets. All rights reserved.
//

import MetalKit
import MetalPerformanceShaders

import simd


struct Vertex {
    let positionX: Float
    let positionY: Float
    let positionZ: Float
    
    let normalX: Float
    let normalY: Float
    let normalZ: Float
    
    let texcoordU: Float
    let texcoordV: Float
    
    init() {
        positionX = 0
        positionY = 0
        positionZ = 0
        
        normalX = 0
        normalY = 0
        normalZ = 0
        
        texcoordU = 0
        texcoordV = 0
    }
    
    init(position: simd_float3, normal: simd_float3, texcoord: simd_float2) {
        positionX = position.x
        positionY = position.y
        positionZ = position.z
        
        normalX = normal.x
        normalY = normal.y
        normalZ = normal.z
        
        texcoordU = texcoord.x
        texcoordV = texcoord.y
    }
    
    var position: simd_float3 {
        get { simd_float3(positionX, positionY, positionZ) }
    }
    
    var normal: simd_float3 {
        get { simd_float3(normalX, normalY, normalZ )}
    }
    
    var texcoord: simd_float2 {
        get { simd_float2(texcoordU, texcoordV) }
    }
    
}


struct Material {
    let diffuseX:  Float
    let diffuseY:  Float
    let diffuseZ:  Float
    let type:      uint32
    
    let emissiveX: Float
    let emissiveY: Float
    let emissiveZ: Float
    
    init(diffuse: simd_float3, type: uint32, emissive: simd_float3) {
        self.diffuseX = diffuse.x
        self.diffuseY = diffuse.y
        self.diffuseZ = diffuse.z
        self.type = type
        self.emissiveX = emissive.x
        self.emissiveY = emissive.y
        self.emissiveZ = emissive.z
    }
    
    var diffuse: simd_float3 {
        get { simd_float3(diffuseX, diffuseY, diffuseZ) }
    }
    
    var emissive: simd_float3 {
        get { simd_float3(emissiveX, emissiveY, emissiveZ )}
    }
    
}

struct Triangle {
    let indexMaterial: uint32
}

struct EmitterTriangle {
    let area: Float
    var cdf: Float
    var pdf: Float
    let globalIndex: UInt32
    
    let v0: Vertex
    let v1: Vertex
    let v2: Vertex
    
    
    let emissiveX: Float
    let emissiveY: Float
    let emissiveZ: Float
 
    
    init(area: Float, cdf: Float, pdf: Float, globalIndex: UInt32, v0: Vertex, v1: Vertex, v2: Vertex, emission: simd_float3) {
        self.area = area
        self.cdf = cdf
        self.pdf = pdf
        self.globalIndex = globalIndex
        self.v0 = v0
        self.v1 = v1
        self.v2 = v2
        self.emissiveX = emission.x
        self.emissiveY = emission.y
        self.emissiveZ = emission.z
    }
    
};



extension MTLIndexType {
    func convertToMSPDataType() -> MPSDataType {
        switch self {
        case .uint16:
            return MPSDataType.uInt16
        case .uint32:
            return MPSDataType.uInt32
        @unknown default:
            fatalError()
        }
    }
}

class GeometryProvider {
    let accelerationStruct: MPSTriangleAccelerationStructure
    let materialBuffer: MTLBuffer
    let triangleBuffer: MTLBuffer
    let emitterTriangleBuffer: MTLBuffer
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    
    
    init(name: String, device: MTLDevice) {
        let modelURL = Bundle.main.url(forResource: name, withExtension: "obj")!
        
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: MemoryLayout<Float>.size * 3, bufferIndex: 0)
        vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: MemoryLayout<Float>.size * 6, bufferIndex: 0)
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 8)
        
        let bufferAllocator = MTKMeshBufferAllocator(device: device);
        let asset = MDLAsset(url: modelURL, vertexDescriptor: vertexDescriptor, bufferAllocator: bufferAllocator)
        
        
        let (sourceMeshes, meshes) = try! MTKMesh.newMeshes(asset: asset, device: device)
        
        let extractVertex: (UnsafeMutableRawPointer, Int) -> Vertex = { pointer, index in
            pointer.load(fromByteOffset: MemoryLayout<Vertex>.size * index, as: Vertex.self)
        }
        
        let extractIndex: (UnsafeMutableRawPointer, Int) -> Int = { pointer, index in
            Int(pointer.load(fromByteOffset: MemoryLayout<UInt32>.size * index, as: UInt32.self))
        }

        
        var materials: [Material] = []
        var triangles: [Triangle] = []
        var emitterTriangles: [EmitterTriangle] = []
        
        var totalLightArea: Float = 0.0
        
        for mesh in sourceMeshes {
            
            let ptrVertexBuffer = mesh.vertexBuffers.first!.map().bytes
            let vertices = (0..<mesh.vertexCount).map { extractVertex(ptrVertexBuffer, $0) }
            
            var globalIndex: uint32 = 0
           
            
            for submesh in mesh.submeshes as! [MDLSubmesh] {
                let ptrIndexBuffer = submesh.indexBuffer.map().bytes
                let indices  = (0..<submesh.indexCount).map { extractIndex(ptrIndexBuffer, $0) }
                
                let diffuse  = (submesh.material?.properties(with: .baseColor).first?.float3Value)!
                var emissive = (submesh.material?.properties(with: .emission).first?.float3Value)!
                
                if submesh.material?.name == "light" {
                    emissive = simd_float3(5, 4, 3)
                }
                
                
                let material = Material(diffuse: diffuse, type: 0, emissive: emissive)

                
                for id in 0 ..< submesh.indexCount / 3 {
           
                    let v0 = vertices[indices[3 * id + 0]]
                    let v1 = vertices[indices[3 * id + 1]]
                    let v2 = vertices[indices[3 * id + 2]]
                    
                    triangles.append(Triangle(indexMaterial: uint32(materials.count)))
           
                    if simd_length(material.emissive) > 0.0 {
                        let area = 0.5 * simd_length(simd_cross(v2.position - v0.position, v1.position - v0.position))
                        emitterTriangles.append(EmitterTriangle(area: area, cdf: 0, pdf: 0, globalIndex: globalIndex, v0: v0, v1: v1, v2: v2, emission: material.emissive ))
                        totalLightArea += area
                    }
                    globalIndex += 1
                }
            
                materials.append(material)
            }
        }
        
        emitterTriangles.sort(by: { x, y in x.area < y.area})
        
        var cdf: Float = 0.0
        for index in 0 ..< emitterTriangles.count {
            emitterTriangles[index].cdf = cdf
            emitterTriangles[index].pdf = emitterTriangles[index].area / totalLightArea
            cdf += emitterTriangles[index].pdf
        }
        emitterTriangles.append(EmitterTriangle(area: 0, cdf: 1.0, pdf: 0, globalIndex: 0, v0: Vertex(), v1: Vertex(), v2: Vertex(), emission: .zero))
        
        self.materialBuffer = device.makeBuffer(bytes: materials, length: MemoryLayout<Material>.size * materials.count)!
        self.triangleBuffer = device.makeBuffer(bytes: triangles, length: MemoryLayout<Triangle>.size * triangles.count)!
        self.emitterTriangleBuffer = device.makeBuffer(bytes: emitterTriangles, length: MemoryLayout<EmitterTriangle>.size * triangles.count)!
        
        
        self.vertexBuffer = meshes.first!.vertexBuffers.first!.buffer
        self.indexBuffer = meshes.first!.submeshes.first!.indexBuffer.buffer
        
        self.accelerationStruct = MPSTriangleAccelerationStructure(device: device)
        self.accelerationStruct.vertexBuffer = self.vertexBuffer
        self.accelerationStruct.vertexStride = MemoryLayout<Vertex>.size
        self.accelerationStruct.indexBuffer = self.indexBuffer
        self.accelerationStruct.triangleCount = triangles.count
        self.accelerationStruct.indexType = meshes.first!.submeshes.first!.indexType.convertToMSPDataType()
        self.accelerationStruct.rebuild()
        
        
    }
}
