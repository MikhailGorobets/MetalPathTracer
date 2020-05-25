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
    
        
        var materials: [Material] = []
        var triangles: [Triangle] = []
        
        
        for mesh in sourceMeshes {
            for submesh in mesh.submeshes as! [MDLSubmesh] {
 
                
                let diffuse  = (submesh.material?.properties(with: .baseColor).first?.float3Value)!
                var emissive = (submesh.material?.properties(with: .emission).first?.float3Value)!
                
                //Don't work emissive loading
                if submesh.material?.name == "light" {
                    emissive = simd_float3(5, 4, 3)
                }

                let material = Material(diffuse: diffuse, type: 0, emissive: emissive)

                for _ in 0 ..< submesh.indexCount / 3 {
                    triangles.append(Triangle(indexMaterial: uint32(materials.count)))
                }
            
                materials.append(material)
            }
        }
        
     
        
        self.materialBuffer = device.makeBuffer(bytes: materials, length: MemoryLayout<Material>.size * materials.count)!
        self.triangleBuffer = device.makeBuffer(bytes: triangles, length: MemoryLayout<Triangle>.size * triangles.count)!

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
