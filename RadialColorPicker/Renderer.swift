//
//  Renderer.swift
//  RadialColorPicker
//
//  Created by Reza on 5/29/23.
//

import Foundation
import MetalKit
import Matrix
import Transform

let kMaxBuffersInFlight: Int = 3
let kAlignedUniformsSize: Int = (MemoryLayout<Uniforms>.size & ~0xFF) + 0x100

class Renderer: NSObject, ObservableObject, MTKViewDelegate {
    // MARK: - Properties
    let geometryURL: URL = Bundle.main.url(forResource: "Body", withExtension: "obj")!
    var view: MTKView! {
        didSet {
            guard view != nil else { return }
            
            do {
                try loadMetal()
            } catch {
                print("error loading metal: \(error.localizedDescription)")
            }
        }
    }
    var commandQueue: MTLCommandQueue!
    var _inFlightSemaphore = DispatchSemaphore(value: kMaxBuffersInFlight)
    
    // RenderState
    var renderState: MTLRenderPipelineState!
    
    // depth state
    var depthState: MTLDepthStencilState!
    
    // projections
    var projectionMatrix: matrix_float4x4 = matrix_identity_float4x4
    
    // geometry transform
    var transform: Transform = .init(transform: .init(eulerAngles: [0.0, 7.0 * Float.pi / 6.0, 0.0]))
    
    // camera
    var camera: Camera = .init(transform: .init(translationX: 0.0, translationY: 0.0, translationZ: -1.0))
    
    // light direction
    var lightDirection: simd_float3 = [-1.0, 1.0, -1.0]
    
    // light color
    var lightColor: simd_float3 = [0.4, 0.4, 0.4]
    
    // color
    var color: simd_float3 = [1.0, 0.0, 0.0]
    
    // geometry
    var V = Mat<Float>()
    var N = Mat<Float>()
    var F = Mat<UInt32>()
    
    // Buffers
    var dynamicBufferIndex: Int = 0
    var vertexCount: Int!
    var indexCount: Int!
    /// Position - Normal
    var vertexBuffer: MTLBuffer!
    var vertexBufferAddress: UnsafeMutableRawPointer!
    var vertexBufferOffset: Int = 0
    /// faces
    var indexBuffer: MTLBuffer!
    /// uniiforms
    var uniformsBuffer: MTLBuffer!
    var uniformsBufferAddress: UnsafeMutableRawPointer!
    var uniformsBufferOffset: Int = 0
    
    // MARK: - Helper Methods
    private func loadMetal() throws {
        // initialize library
        let device = GPUDevice.shared
        let library = device.makeDefaultLibrary()!
        
        let vertexShader = library.makeFunction(name: "vertexShader")
        let fragmentShader = library.makeFunction(name: "fragmentShader")
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[VertexAttribute.position.rawValue].format = .float3
        vertexDescriptor.attributes[VertexAttribute.position.rawValue].offset = 0
        vertexDescriptor.attributes[VertexAttribute.position.rawValue].bufferIndex = BufferIndex.meshPositions.rawValue
        
        vertexDescriptor.attributes[VertexAttribute.normal.rawValue].format = .float3
        vertexDescriptor.attributes[VertexAttribute.normal.rawValue].offset = 3 * MemoryLayout<Float>.size
        vertexDescriptor.attributes[VertexAttribute.normal.rawValue].bufferIndex = BufferIndex.meshPositions.rawValue
        
        vertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stride = 6 * MemoryLayout<Float>.size
        
        let renderStateDescriptor = MTLRenderPipelineDescriptor()
        renderStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        /*
        renderStateDescriptor.colorAttachments[0].isBlendingEnabled = true
        renderStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        renderStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        renderStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        renderStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusBlendAlpha
        renderStateDescriptor.colorAttachments[0].alphaBlendOperation = .add
        renderStateDescriptor.isAlphaToOneEnabled = false
        renderStateDescriptor.isAlphaToCoverageEnabled = true*/
        renderStateDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        renderStateDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat
        renderStateDescriptor.vertexDescriptor = vertexDescriptor
        renderStateDescriptor.vertexFunction = vertexShader
        renderStateDescriptor.fragmentFunction = fragmentShader
        
        renderState = try device.makeRenderPipelineState(descriptor: renderStateDescriptor)
        
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthDesc)
        
        commandQueue = device.makeCommandQueue()
        
        // Load geometry
        let allocator = MTKMeshBufferAllocator(device: device)
        GeometryLoader.LoadMesh(allocator: allocator, device: device, url: geometryURL, vertices: &V, normals: &N, faces: &F)
        vertexCount = V.rows
        indexCount = F.size.count
        
        // configure geometry transform
        
        // Flip Z axis to convert geometry from right handed to left handed
        var coordinateSpaceTransform = matrix_identity_float4x4
        coordinateSpaceTransform.columns.2.z = -1.0
        let transform = transform.matrix * coordinateSpaceTransform
        self.transform = .init(transform: transform)
        
        // Initialize Buffers
        vertexBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * 6 * vertexCount * kMaxBuffersInFlight)
        indexBuffer = device.makeBuffer(bytes: F.valuesPtr.pointer, length: MemoryLayout<UInt32>.size * indexCount)
        uniformsBuffer = device.makeBuffer(length: kAlignedUniformsSize * kMaxBuffersInFlight)
    }
    
    func updateDynamicBuffer() {
        dynamicBufferIndex = (dynamicBufferIndex + 1) % 3
        
        vertexBufferOffset = (MemoryLayout<Float>.size * 6 * vertexCount * dynamicBufferIndex)
        vertexBufferAddress = vertexBuffer.contents().advanced(by: vertexBufferOffset)
        
        uniformsBufferOffset = kAlignedUniformsSize * dynamicBufferIndex
        uniformsBufferAddress = uniformsBuffer.contents().advanced(by: uniformsBufferOffset)
    }
    
    func updateAppState() {
        // update vertex buffer
        for i in 0..<vertexCount {
            let xOffset = MemoryLayout<Float>.size * (6 * i)
            let normalXOffset = MemoryLayout<Float>.size * (6 * i + 3)
            
            vertexBufferAddress.advanced(by: xOffset).assumingMemoryBound(to: Float.self).initialize(from: V.ptrRef(i, 0), count: 3)
            vertexBufferAddress.advanced(by: normalXOffset).assumingMemoryBound(to: Float.self).initialize(from: N.ptrRef(i, 0), count: 3)
        }
        
        // update uniforms
        uniformsBufferAddress.assumingMemoryBound(to: Uniforms.self).pointee.projectionMatrix = projectionMatrix
        uniformsBufferAddress.assumingMemoryBound(to: Uniforms.self).pointee.transform = transform.matrix
        uniformsBufferAddress.assumingMemoryBound(to: Uniforms.self).pointee.viewMatrix = camera.viewMatrix
        uniformsBufferAddress.assumingMemoryBound(to: Uniforms.self).pointee.cameraTransform = camera.transform.matrix
        uniformsBufferAddress.assumingMemoryBound(to: Uniforms.self).pointee.lightDirection = lightDirection
        uniformsBufferAddress.assumingMemoryBound(to: Uniforms.self).pointee.color = color
        uniformsBufferAddress.assumingMemoryBound(to: Uniforms.self).pointee.lightColor = lightColor
    }
    
    // MARK: - MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspectRatio = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_left_hand(fovyRadians: .pi / 4.0, aspectRatio: aspectRatio, nearZ: 0.1, farZ: 100.0)
    }
    
    func draw(in view: MTKView) {
        let _ = _inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue?.makeCommandBuffer() {
            commandBuffer.label = "Render Command buffer"
            let semaphore = _inFlightSemaphore
            commandBuffer.addCompletedHandler { _ in
                semaphore.signal()
            }
            
            updateDynamicBuffer()
            updateAppState()
            
            if let renderPassDescriptor = view.currentRenderPassDescriptor, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderEncoder.label = "Geometry Rendering"
                renderEncoder.setRenderPipelineState(renderState)
                renderEncoder.setCullMode(.back)
                renderEncoder.setFrontFacing(.counterClockwise)
                renderEncoder.setDepthStencilState(depthState)
                
                renderEncoder.setVertexBuffer(vertexBuffer, offset: vertexBufferOffset, index: BufferIndex.meshPositions.rawValue)
                renderEncoder.setVertexBuffer(uniformsBuffer, offset: uniformsBufferOffset, index: BufferIndex.uniforms.rawValue)
                renderEncoder.setFragmentBuffer(uniformsBuffer, offset: uniformsBufferOffset, index: BufferIndex.uniforms.rawValue)
                renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32, indexBuffer: indexBuffer, indexBufferOffset: 0)
                
                renderEncoder.popDebugGroup()
                renderEncoder.endEncoding()
                
                if let drawable = view.currentDrawable {
                    commandBuffer.present(drawable)
                }
                
                commandBuffer.commit()
            }
        }
    }
}
