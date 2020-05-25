//
//  Render.swift
//  RayTracing
//
//  Created by Mikhail Gorobets on 22.05.2020.
//  Copyright © 2020 Mikhail Gorobets. All rights reserved.
//


import MetalKit
import ModelIO
import MetalPerformanceShaders


struct ApplicationData {
    var viewProjectMatrix: float4x4
    var invViewProjectMatrix: float4x4
    var frameIndex: uint32
    var frameOffset: packed_float2
}

struct Ray {
    var base: MPSRayOriginMinDistanceDirectionMaxDistance
    var radianceX: Float
    var radianceY: Float
    var radianceZ: Float
    var bounces: uint32
    var throughputX: Float
    var throughputY: Float
    var throughputZ: Float
}


class Render: NSObject, MTKViewDelegate {
    
    let view: MTKView
    let device: MTLDevice
    let cmdQueue: MTLCommandQueue
    let shaderLibrary: MTLLibrary
    
    let rayIntersector: MPSRayIntersector
    let geometry: GeometryProvider
    
    
    let rayGeneratorCPS: MTLComputePipelineState
    let handleIntersectionsCPS: MTLComputePipelineState
    let accumulateImageCPS: MTLComputePipelineState
    
    
    let conversionMPS: MPSImageConversion
    
    var uniformBuffer: MTLBuffer!
    var rayBuffer: MTLBuffer!
    var intersectionBuffer: MTLBuffer!
    
    var geometryRT: MTLTexture!
    
    let maxFramesInFlight = 3
    var frameIndex:uint32 = 0
    var semaphore: DispatchSemaphore!
    
    
    init(view: MTKView) {
        
        self.view = view
        self.device = view.device!
        self.cmdQueue = device.makeCommandQueue()!
        self.shaderLibrary = device.makeDefaultLibrary()!
        self.semaphore = DispatchSemaphore.init(value: maxFramesInFlight)
        
        do {
            let desc = MTLComputePipelineDescriptor()
            desc.label = "Geometry Ray Generator"
            desc.computeFunction = self.shaderLibrary.makeFunction(name: "GenerateRaysKernel")
            self.rayGeneratorCPS = try! self.device.makeComputePipelineState(descriptor: desc, options: [], reflection: nil)
        }
        
        do {
            let desc = MTLComputePipelineDescriptor()
            desc.label = "Geometry Intersection Handle"
            desc.computeFunction = self.shaderLibrary.makeFunction(name: "HandleIntersections")
            self.handleIntersectionsCPS = try! self.device.makeComputePipelineState(descriptor: desc, options: [], reflection: nil)
        }
        
        do {
            let desc = MTLComputePipelineDescriptor()
            desc.label = "Accumulate Image"
            desc.computeFunction = self.shaderLibrary.makeFunction(name: "AccumulateImage")
            self.accumulateImageCPS = try! self.device.makeComputePipelineState(descriptor: desc, options: [], reflection: nil)
        }
        
        let conversionInfo = CGColorConversionInfo(src: CGColorSpace(name: CGColorSpace.genericRGBLinear)!, dst: CGColorSpace(name: CGColorSpace.sRGB)!)!
        
        
        self.conversionMPS = MPSImageConversion(device: device, srcAlpha: .alphaIsOne, destAlpha: .alphaIsOne, backgroundColor: nil, conversionInfo: conversionInfo)
        
        
        self.rayIntersector = MPSRayIntersector(device: device)
        self.rayIntersector.rayDataType = .originMinDistanceDirectionMaxDistance
        self.rayIntersector.rayStride = MemoryLayout<Ray>.size
        self.rayIntersector.intersectionDataType = .distancePrimitiveIndexCoordinates
        self.rayIntersector.intersectionStride = MemoryLayout<MPSIntersectionDistancePrimitiveIndexCoordinates>.size
        
        self.uniformBuffer = device.makeBuffer(length: MemoryLayout<ApplicationData>.size, options: [])
        self.uniformBuffer.label = "Uniform Buffer"
        
        
        self.geometry = GeometryProvider(name: "cornellbox", device: device)
        
        super.init()
    }
    
    func updateUniforms() {
        
        let projection = float4x4(perspectiveProjectionFov: Float.pi / 3, aspectRatio: Float(view.drawableSize.width) / Float(view.drawableSize.height), nearZ: 0.1, farZ: 100)
        let view = float4x4(translationBy: simd_float3(0.0, -1.0, -3))
        
        let ptr = uniformBuffer.contents().bindMemory(to: ApplicationData.self, capacity: 1)
        ptr.pointee.viewProjectMatrix = projection * view
        ptr.pointee.invViewProjectMatrix = simd_inverse(projection * view)
        ptr.pointee.frameIndex = self.frameIndex
        ptr.pointee.frameOffset = packed_float2(repeating: 0)
        
        self.frameIndex += 1
    }
    
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
        do {
            let desc = MTLTextureDescriptor()
            desc.textureType = .type2D
            desc.pixelFormat = .rgba32Float
            desc.width = Int(size.width)
            desc.height = Int(size.height)
            desc.mipmapLevelCount = 1
            desc.usage = [.shaderRead, .shaderWrite]
            desc.storageMode = .private
            self.geometryRT = device.makeTexture(descriptor: desc)
        }
        
        let rayCount = Int(size.width) * Int(size.height);
        
        self.rayBuffer = device.makeBuffer(length: MemoryLayout<Ray>.size * rayCount, options: .storageModePrivate)
        self.intersectionBuffer = device.makeBuffer(length: MemoryLayout<MPSIntersectionDistancePrimitiveIndexCoordinates>.size * rayCount, options:.storageModePrivate)
        
        
    }
    
    func draw(in view: MTKView) {
        semaphore.wait()
        updateUniforms()
        
        
        let cmdBuffer = cmdQueue.makeCommandBuffer()!
        cmdBuffer.addCompletedHandler { _ in self.semaphore.signal() }
        
        
        let threadsPerGroup = MTLSizeMake(8, 8, 1)
        let threadgroups = MTLSizeMake(geometryRT.width, geometryRT.height, 1)
        
        if let drawable = view.currentDrawable {
            
            
            
            do {
                let cmdEncoder = cmdBuffer.makeComputeCommandEncoder()!
                
                cmdEncoder.setComputePipelineState(rayGeneratorCPS)
                cmdEncoder.setBuffer(self.uniformBuffer, offset: 0, index: 0)
                cmdEncoder.setBuffer(self.rayBuffer, offset: 0, index: 1)
                cmdEncoder.dispatchThreads(threadgroups, threadsPerThreadgroup: threadsPerGroup)
                cmdEncoder.endEncoding()
            }
            
            
            for _ in 0 ..< 4 {
                
                
                
                rayIntersector.encodeIntersection(commandBuffer: cmdBuffer,
                                                  intersectionType: .nearest,
                                                  rayBuffer: rayBuffer,
                                                  rayBufferOffset: 0,
                                                  intersectionBuffer: intersectionBuffer,
                                                  intersectionBufferOffset: 0,
                                                  rayCount: geometryRT.width * geometryRT.height,
                                                  accelerationStructure: geometry.accelerationStruct)
                
                let cmdEncoder = cmdBuffer.makeComputeCommandEncoder()!
                cmdEncoder.setComputePipelineState(handleIntersectionsCPS)
                cmdEncoder.setTexture(self.geometryRT, index: 0)
                cmdEncoder.setBuffer(self.intersectionBuffer, offset: 0, index: 0)
                cmdEncoder.setBuffer(self.geometry.materialBuffer, offset: 0, index: 1)
                cmdEncoder.setBuffer(self.geometry.triangleBuffer, offset: 0, index: 2)
                cmdEncoder.setBuffer(self.geometry.vertexBuffer, offset: 0, index: 3)
                cmdEncoder.setBuffer(self.geometry.indexBuffer, offset: 0, index: 4)
                cmdEncoder.setBuffer(self.rayBuffer, offset: 0, index: 5)
                cmdEncoder.setBuffer(self.uniformBuffer, offset: 0, index: 6)
                cmdEncoder.dispatchThreads(threadgroups, threadsPerThreadgroup: threadsPerGroup)
                cmdEncoder.endEncoding()
        
            }
            
            
            do {
                let cmdEncoder = cmdBuffer.makeComputeCommandEncoder()!
                cmdEncoder.setComputePipelineState(accumulateImageCPS)
                cmdEncoder.setTexture(self.geometryRT, index: 0)
                cmdEncoder.setBuffer(self.rayBuffer, offset: 0, index: 0)
                cmdEncoder.setBuffer(self.uniformBuffer, offset: 0, index: 1)
                cmdEncoder.dispatchThreads(threadgroups, threadsPerThreadgroup: threadsPerGroup)
                cmdEncoder.endEncoding()
            }
            
            conversionMPS.encode(commandBuffer: cmdBuffer, sourceTexture: self.geometryRT, destinationTexture: view.currentDrawable!.texture)
            cmdBuffer.present(drawable)
            cmdBuffer.commit()
        }
        
    }
    
}
