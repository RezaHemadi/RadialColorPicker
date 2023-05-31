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
import Combine

let kMaxBuffersInFlight: Int = 3
let kAlignedUniformsSize: Int = (MemoryLayout<Uniforms>.size & ~0xFF) + 0x100
let kAlignedRibbonUniformsSize: Int = (MemoryLayout<RibbonUniforms>.size & ~0xFF) + 0x100

class Renderer: NSObject, ObservableObject, MTKViewDelegate {
    // MARK: - Properties
    @Published var hue: Double = 0.0
    @Published var saturation: Double = 1.0
    @Published var brightness: Double = 0.5
    
    var streams: [AnyCancellable] = []
    
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
    var ribbonRenderState: MTLRenderPipelineState!
    
    // depth state
    var depthState: MTLDepthStencilState!
    
    // projections
    var projectionMatrix: matrix_float4x4 = matrix_identity_float4x4
    var ribbonProjectionMatrix: matrix_float4x4 = matrix_identity_float4x4
    
    // geometry transform
    var transform: Transform = .init(transform: .init(eulerAngles: [0.0, 1.1 * Float.pi, 0.0]))
    
    // camera
    var camera: Camera = .init(transform: .init(translationX: 0.040, translationY: 0.02, translationZ: -1.17))
    
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
    
    // ribbon polygon
    /// angle steps when constructing polygon and radial hsl colors
    let deltaTheta: Float = .pi / 30.0
    let r1: Float = 3.9
    let r2: Float = 5.0
    var ribbon: ColoredPolygon!
    
    // Buffers
    var dynamicBufferIndex: Int = 0
    var vertexCount: Int!
    var indexCount: Int!
    var ribbonIndexCount: Int!
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
    
    // ribbon buffers
    var ribbonVertexBuffer: MTLBuffer!
    var ribbonVertexBufferAddress: UnsafeMutableRawPointer!
    var ribbonVertexBufferOffset: Int = 0
    
    var ribbonIndexBuffer: MTLBuffer!
    
    var ribbonColorsBuffer: MTLBuffer!
    var ribbonColorsBufferAddress: UnsafeMutableRawPointer!
    var ribbonColorsBufferOffset:  Int = 0
    
    var ribbonUniformsBuffer: MTLBuffer!
    var ribbonUniformsBufferAddress: UnsafeMutableRawPointer!
    var ribbonUniformsBufferOffset: Int = 0
    
    // texture to sample drawable
    var sampleBuffer: MTLBuffer!
    var sampleBufferOffset: Int!
    var sampleBufferAddress: UnsafeMutableRawPointer!
    
    var samplePoint: CGPoint?
    
    // MARK: - Initialization
    override init() {
        super.init()
        
        let stream_s = $saturation.sink { value in
            self.ribbon?.updateColors(s: Float(value), l: Float(self.brightness))
        }
        stream_s.store(in: &streams)
        
        let stream_l = $brightness.sink { value in
            self.ribbon?.updateColors(s: Float(self.saturation), l: Float(value))
        }
        stream_l.store(in: &streams)
    }
    
    // MARK: - Methods
    func samplePoint(_ point: CGPoint) {
        let texSpacePoint = convertToTextureSpace(point)
        // make sure point is within the texture size
        guard point.x.isLessThanOrEqualTo(CGFloat(view.currentDrawable!.texture.width)) else { return }
        guard point.y.isLessThanOrEqualTo(CGFloat(view.currentDrawable!.texture.height)) else { return }
        
        let r1: CGFloat = CGFloat(self.r1) * 100.0
        let r2: CGFloat = CGFloat(self.r2) * 100.0
        
        let origin = CGPoint(x: 500.0, y: 500.0)
        let translatedPoint: CGPoint = .init(x: texSpacePoint.x - origin.x, y: texSpacePoint.y - origin.y)
        
        let d1sqr: CGFloat = (translatedPoint.x * translatedPoint.x + translatedPoint.y * translatedPoint.y)
        let r1sqr: CGFloat = r1 * r1
        guard !d1sqr.isLess(than: r1sqr) else { return }
        
        let r2sqr: CGFloat = r2 * r2
        guard d1sqr.isLessThanOrEqualTo(r2sqr) else { return }
        
        samplePoint = texSpacePoint
    }
    
    // MARK: - Helper Methods
    private func convertToTextureSpace(_ point: CGPoint) -> CGPoint {
        let scale = view.contentScaleFactor
        
        return .init(x: point.x * scale, y: point.y * scale)
    }
    
    private func loadMetal() throws {
        // initialize library
        let device = GPUDevice.shared
        let library = device.makeDefaultLibrary()!
        
        let vertexShader = library.makeFunction(name: "vertexShader")
        let fragmentShader = library.makeFunction(name: "fragmentShader")
        let ribbonVertexShader = library.makeFunction(name: "ribbonVertexShader")
        let ribbonFragmentShader = library.makeFunction(name: "ribbonFragmentShader")
        
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
        
        // configure ribbon rendering vertex descriptor
        let ribbonVertexDescriptor = MTLVertexDescriptor()
        ribbonVertexDescriptor.attributes[RibbonVertexAttribute.position.rawValue].format = .float3
        ribbonVertexDescriptor.attributes[RibbonVertexAttribute.position.rawValue].offset = 0
        ribbonVertexDescriptor.attributes[RibbonVertexAttribute.position.rawValue].bufferIndex = RibbonBufferIndex.positions.rawValue
        ribbonVertexDescriptor.attributes[RibbonVertexAttribute.color.rawValue].format = .float3
        ribbonVertexDescriptor.attributes[RibbonVertexAttribute.color.rawValue].offset = 0
        ribbonVertexDescriptor.attributes[RibbonVertexAttribute.color.rawValue].bufferIndex = RibbonBufferIndex.colors.rawValue
        
        ribbonVertexDescriptor.layouts[RibbonBufferIndex.positions.rawValue].stride = MemoryLayout<Float>.size * 3
        ribbonVertexDescriptor.layouts[RibbonBufferIndex.colors.rawValue].stride = MemoryLayout<Float>.size * 3
        
        // initialize ribbon rendering state
        let ribbonRenderStateDescriptor = MTLRenderPipelineDescriptor()
        ribbonRenderStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        ribbonRenderStateDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        ribbonRenderStateDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat
        ribbonRenderStateDescriptor.vertexFunction = ribbonVertexShader
        ribbonRenderStateDescriptor.fragmentFunction = ribbonFragmentShader
        ribbonRenderStateDescriptor.vertexDescriptor = ribbonVertexDescriptor
        ribbonRenderState = try device.makeRenderPipelineState(descriptor: ribbonRenderStateDescriptor)
        
        // initialize ribbon rendering buffers
        ribbon =  .CircularRibbon(lowerRadius: r1, upperRadius: r2, deltaTheta: deltaTheta)
        ribbonVertexBuffer = device.makeBuffer(length: ribbon.vertices.count * MemoryLayout<Float>.size * kMaxBuffersInFlight)
        ribbonColorsBuffer = device.makeBuffer(length: ribbon.colors.count * MemoryLayout<Float>.size * kMaxBuffersInFlight)
        ribbonUniformsBuffer = device.makeBuffer(length: kAlignedRibbonUniformsSize * kMaxBuffersInFlight)
        ribbonIndexBuffer = device.makeBuffer(bytes: ribbon.indices, length: ribbon.indices.count * MemoryLayout<UInt32>.size)
        ribbonIndexCount = ribbon.indices.count
        
        // initialize sample buffer
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * 1
        let bytesPerImage = bytesPerRow * 1
        sampleBuffer = device.makeBuffer(length: bytesPerImage * kMaxBuffersInFlight, options: .storageModeShared)
    }
    
    func updateDynamicBuffer() {
        dynamicBufferIndex = (dynamicBufferIndex + 1) % 3
        
        vertexBufferOffset = (MemoryLayout<Float>.size * 6 * vertexCount * dynamicBufferIndex)
        vertexBufferAddress = vertexBuffer.contents().advanced(by: vertexBufferOffset)
        
        uniformsBufferOffset = kAlignedUniformsSize * dynamicBufferIndex
        uniformsBufferAddress = uniformsBuffer.contents().advanced(by: uniformsBufferOffset)
        
        ribbonVertexBufferOffset = MemoryLayout<Float>.size * ribbon.vertices.count * dynamicBufferIndex
        ribbonVertexBufferAddress = ribbonVertexBuffer.contents().advanced(by: ribbonVertexBufferOffset)
        
        ribbonColorsBufferOffset = MemoryLayout<Float>.size * ribbon.colors.count * dynamicBufferIndex
        ribbonColorsBufferAddress = ribbonColorsBuffer.contents().advanced(by: ribbonColorsBufferOffset)
        
        ribbonUniformsBufferOffset = kAlignedRibbonUniformsSize * dynamicBufferIndex
        ribbonUniformsBufferAddress = ribbonUniformsBuffer.contents().advanced(by: ribbonUniformsBufferOffset)
        
        sampleBufferOffset = 4 * dynamicBufferIndex
        sampleBufferAddress = sampleBuffer.contents().advanced(by: sampleBufferOffset)
    }
    
    func updateAppState() {
        if samplePoint != nil {
            let pointer = self.sampleBufferAddress!
            let b: UInt8 = pointer.assumingMemoryBound(to: UInt8.self).pointee
            let g: UInt8 = pointer.assumingMemoryBound(to: UInt8.self).advanced(by: 1).pointee
            let r: UInt8 = pointer.assumingMemoryBound(to: UInt8.self).advanced(by: 2).pointee
            color = [Float(r) / 255.0, Float(g) / 255.0, Float(b) / 255.0]
            
            // update hue
            let hsl = hsl(r: color[0] * 255, g: color[1] * 255, b: color[2] * 255)
            if !hsl[0].isNaN { hue = Double(hsl[0]) }
        }
        
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
        
        // update ribbon vertex buffer
        ribbonVertexBufferAddress.assumingMemoryBound(to: Float.self).initialize(from: ribbon.vertices, count: ribbon.vertices.count)
        // update ribbon colors buffer
        ribbonColorsBufferAddress.assumingMemoryBound(to: Float.self).initialize(from: ribbon.colors, count: ribbon.colors.count)
        // update ribbon uniforms
        ribbonUniformsBufferAddress.assumingMemoryBound(to: RibbonUniforms.self).pointee.projection = ribbonProjectionMatrix
    }
    
    // MARK: - MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspectRatio = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_left_hand(fovyRadians: .pi / 4.0, aspectRatio: aspectRatio, nearZ: 0.1, farZ: 100.0)
        
        let height: Float = 10.0
        let width: Float = height * aspectRatio
        
        ribbonProjectionMatrix = matrix_orthographic_left_hand(left: -width / 2.0,
                                                               right: width / 2.0,
                                                               top: height / 2.0,
                                                               bottom: -height / 2.0,
                                                               near: 0.0, far: 10.0)
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
                
                
                // render ribbon
                renderEncoder.setRenderPipelineState(ribbonRenderState)
                renderEncoder.setVertexBuffer(ribbonVertexBuffer, offset: ribbonVertexBufferOffset, index: RibbonBufferIndex.positions.rawValue)
                renderEncoder.setVertexBuffer(ribbonColorsBuffer, offset: ribbonColorsBufferOffset, index: RibbonBufferIndex.colors.rawValue)
                renderEncoder.setVertexBuffer(ribbonUniformsBuffer, offset: ribbonUniformsBufferOffset, index: RibbonBufferIndex.uniforms.rawValue)
                renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: ribbonIndexCount, indexType: .uint32, indexBuffer: ribbonIndexBuffer, indexBufferOffset: 0)
                
                // render body
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
                
                if let point = samplePoint {
                    let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
                    blitEncoder.copy(from: view.currentDrawable!.texture,
                                     sourceSlice: 0,
                                     sourceLevel: 0,
                                     sourceOrigin: MTLOrigin(x: Int(point.x), y: Int(point.y), z: 0),
                                     sourceSize: MTLSizeMake(1, 1, 1),
                                     to: sampleBuffer,
                                     destinationOffset: sampleBufferOffset,
                                     destinationBytesPerRow: 4,
                                     destinationBytesPerImage: 4)
                    blitEncoder.endEncoding()
                }
                
                if let drawable = view.currentDrawable {
                    commandBuffer.present(drawable)
                }
                
                commandBuffer.commit()
            }
        }
    }
}
