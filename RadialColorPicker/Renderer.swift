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
import MetalPerformanceShaders
import CoreGraphics

let kMaxBuffersInFlight: Int = 3
let kAlignedUniformsSize: Int = (MemoryLayout<Uniforms>.size & ~0xFF) + 0x100
let kAlignedRibbonUniformsSize: Int = (MemoryLayout<RibbonUniforms>.size & ~0xFF) + 0x100
let kAlignedShadowUniformsSize: Int = (MemoryLayout<ShadowUniforms>.size & ~0xFF) + 0x100
let kAlignedShadowInstanceUniformsSize: Int = (MemoryLayout<ShadowInstanceUniforms>.size & ~0xFF) + 0x100

class Renderer: NSObject, ObservableObject, MTKViewDelegate {
    // MARK: - Properties
    @Published var hue: Double
    @Published var saturation: Double
    @Published var brightness: Double
    
    var streams: [AnyCancellable] = []
    
    var drawableWidth: Int!
    var drawableHeight: Int!
    
    let geometryURL: URL = Bundle.main.url(forResource: "Body", withExtension: "obj")!
    var view: MTKView!
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
    var lightDirection: simd_float3 = [0.5, 1.0, -1.0]
    
    // light color
    var lightColor: simd_float3 = [0.43, 0.43, 0.43]
    
    // color
    //var color: simd_float3 = [1.0, 0.0, 0.0]
    @Published var color: UIColor
    private var rgbColor: [Float]
    
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
    
    var samplePoint: CGPoint?
    
    // shadows
    var shadowRenderState: MTLRenderPipelineState!
    var shadowDepthState: MTLDepthStencilState!
    
    var r1Polygon: ColoredPolygon!
    var r1IndexCount: Int!
    var r1VertexBuffer: MTLBuffer!
    var r1IndexBuffer: MTLBuffer!
    var r1VertexBufferOffset: Int = 0
    var r1VertexBufferAddress: UnsafeMutableRawPointer!
    
    var r2Polygon: ColoredPolygon!
    var r2IndexCount: Int!
    var r2VertexBuffer: MTLBuffer!
    var r2IndexBuffer: MTLBuffer!
    var r2VertexBufferOffset: Int = 0
    var r2VertexBufferAddress: UnsafeMutableRawPointer!
    
    var shadowUniformsBuffer: MTLBuffer!
    var shadowUniformsBufferOffset: Int!
    var shadowUniformsBufferAddress: UnsafeMutableRawPointer!
    
    var shadowInstanceUniformsBuffer: MTLBuffer!
    var shadowInstanceUniformsBufferOffset: Int = 0
    var shadowInstanceUniformsAddress: UnsafeMutableRawPointer!
    
    var shadowTransform = Transform.init(translationX: 0.13, translationY: -0.13, translationZ: 0.9)
    
    var shadowTexture: MTLTexture!
    var shadowDepthTexture: MTLTexture!
    var shadowRenderPassDescriptor: MTLRenderPassDescriptor!
    
    var ribbonRenderTexture: MTLTexture!
    var ribbonRenderPassDescriptor: MTLRenderPassDescriptor!
    
    // blend kernel
    var blendKernelState: MTLComputePipelineState!
    
    private var shadowsInitialized: Bool = false
    private var ribbonTransform: matrix_float4x4 = Transform.init(translation: [0.0, 0.0, 0.2]).matrix
    
    // MARK: - Initialization
    init(color: UIColor) {
        self.color = color
        
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        guard color.getRed(&r, green: &g, blue: &b, alpha: nil) else { fatalError() }
        rgbColor = [Float(r), Float(g), Float(b)]
        
        var hue: CGFloat = 0.0
        var saturation: CGFloat = 0.0
        var brightness: CGFloat = 0.0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil) else { fatalError() }
        self.hue = Double(hue)
        self.saturation = Double(saturation)
        self.brightness = Double(brightness)
        
        super.init()
        let stream_s = $saturation
            .receive(on: RunLoop.main)
            .sink { value in
            self.ribbon?.updateColors(s: Float(value), l: Float(self.brightness))
        }
        stream_s.store(in: &streams)
        
        let stream_l = $brightness
            .receive(on: RunLoop.main)
            .sink { value in
            self.ribbon?.updateColors(s: Float(self.saturation), l: Float(value))
        }
        stream_l.store(in: &streams)
        
        let stream_col = $color
            .receive(on: RunLoop.main)
            .sink { col in
            self.rgbColor = self.getRGB(col)
        }
        stream_col.store(in: &streams)
    }
    
    // MARK: - Methods
    func samplePoint(_ point: CGPoint) {
        let texSpacePoint = convertToTextureSpace(point)
        // make sure point is within the texture size
        guard point.x.isLessThanOrEqualTo(CGFloat(view.currentDrawable!.texture.width)) else { return }
        guard point.y.isLessThanOrEqualTo(CGFloat(view.currentDrawable!.texture.height)) else { return }
        
        
        let r1: CGFloat = CGFloat(self.r1) * CGFloat(drawableWidth) / 10.0
        let r2: CGFloat = CGFloat(self.r2) * CGFloat(drawableWidth) / 10.0
        
        let origin = CGPoint(x: CGFloat(drawableWidth!) / 2.0, y: CGFloat(drawableHeight) / 2.0)
        let translatedPoint: CGPoint = .init(x: texSpacePoint.x - origin.x, y: texSpacePoint.y - origin.y)
        
        let d1sqr: CGFloat = (translatedPoint.x * translatedPoint.x + translatedPoint.y * translatedPoint.y)
        let r1sqr: CGFloat = r1 * r1
        guard !d1sqr.isLess(than: r1sqr) else { return }
        
        let r2sqr: CGFloat = r2 * r2
        guard d1sqr.isLessThanOrEqualTo(r2sqr) else { return }
        
        samplePoint = texSpacePoint
    }
    
    // MARK: - Helper Methods
    private func readSample() {
        if samplePoint != nil {
            let pointer = self.sampleBuffer.contents()
            let b: UInt8 = pointer.assumingMemoryBound(to: UInt8.self).pointee
            let g: UInt8 = pointer.assumingMemoryBound(to: UInt8.self).advanced(by: 1).pointee
            let r: UInt8 = pointer.assumingMemoryBound(to: UInt8.self).advanced(by: 2).pointee
            let rgbcolor = [Double(r) / 255.0, Double(g) / 255.0, Double(b) / 255.0]
            let newColor = UIColor.init(red: rgbcolor[0], green: rgbcolor[1], blue: rgbcolor[2], alpha: 1.0)
            DispatchQueue.main.async {
                self.color = newColor
            }
            samplePoint = nil
        }
    }
    
    private func getRGB(_ color: UIColor) -> [Float] {
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 0.0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { fatalError() }
        return [Float(r), Float(g), Float(b)]
    }
    
    private func convertToTextureSpace(_ point: CGPoint) -> CGPoint {
        let scale = view.contentScaleFactor
        
        return .init(x: point.x * scale, y: point.y * scale)
    }
    
    func loadMetal() throws {
        // initialize library
        let device = GPUDevice.shared
        let library = device.makeDefaultLibrary()!
        
        let vertexShader = library.makeFunction(name: "vertexShader")
        let fragmentShader = library.makeFunction(name: "fragmentShader")
        let ribbonVertexShader = library.makeFunction(name: "ribbonVertexShader")
        let ribbonFragmentShader = library.makeFunction(name: "ribbonFragmentShader")
        let shadowVertexShader = library.makeFunction(name: "shadowVertexShader")
        let shadowFragmentShader = library.makeFunction(name: "shadowFragmentShader")
        
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
        ribbonRenderStateDescriptor.vertexFunction = ribbonVertexShader
        ribbonRenderStateDescriptor.fragmentFunction = ribbonFragmentShader
        ribbonRenderStateDescriptor.vertexDescriptor = ribbonVertexDescriptor
        ribbonRenderState = try device.makeRenderPipelineState(descriptor: ribbonRenderStateDescriptor)
        
        // initialize ribbon rendering buffers
        ribbon =  .CircularRibbon(lowerRadius: r1, upperRadius: r2, deltaTheta: deltaTheta)
        ribbon.updateColors(s: Float(self.saturation), l: Float(self.brightness))
        ribbonVertexBuffer = device.makeBuffer(length: ribbon.vertices.count * MemoryLayout<Float>.size * kMaxBuffersInFlight)
        ribbonColorsBuffer = device.makeBuffer(length: ribbon.colors.count * MemoryLayout<Float>.size * kMaxBuffersInFlight)
        ribbonUniformsBuffer = device.makeBuffer(length: kAlignedRibbonUniformsSize * kMaxBuffersInFlight)
        ribbonIndexBuffer = device.makeBuffer(bytes: ribbon.indices, length: ribbon.indices.count * MemoryLayout<UInt32>.size)
        ribbonIndexCount = ribbon.indices.count
        
        // initialize sample buffer
        sampleBuffer = device.makeBuffer(length: 4, options: .storageModeShared)
        
        let normalizedColor: [UInt8] = [UInt8(rgbColor[0] * 255.0), UInt8(rgbColor[1] * 255.0), UInt8(rgbColor[2] * 255.0), 255]
        for i in 0..<kMaxBuffersInFlight {
            let offset = 4 * i
            sampleBuffer.contents().advanced(by: offset).assumingMemoryBound(to: UInt8.self).initialize(from: normalizedColor, count: normalizedColor.count)
        }
        
        // initialize shadow render state
        let shadowVertexDescriptor = MTLVertexDescriptor()
        shadowVertexDescriptor.attributes[ShadowVertexAttribute.position.rawValue].format = .float3
        shadowVertexDescriptor.attributes[ShadowVertexAttribute.position.rawValue].offset = 0
        shadowVertexDescriptor.attributes[ShadowVertexAttribute.position.rawValue].bufferIndex = ShadowBufferIndex.positions.rawValue
        shadowVertexDescriptor.layouts[ShadowBufferIndex.positions.rawValue].stride = MemoryLayout<Float>.size * 3
        
        let shadowRenderStateDescriptor = MTLRenderPipelineDescriptor()
        shadowRenderStateDescriptor.vertexDescriptor = shadowVertexDescriptor
        shadowRenderStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        shadowRenderStateDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        shadowRenderStateDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat
        shadowRenderStateDescriptor.vertexFunction = shadowVertexShader
        shadowRenderStateDescriptor.fragmentFunction = shadowFragmentShader
        
        shadowRenderState = try device.makeRenderPipelineState(descriptor: shadowRenderStateDescriptor)
        shadowDepthState = device.makeDepthStencilState(descriptor: depthDesc)
        
        let ribbonRenderTextureDescriptor = MTLTextureDescriptor()
        ribbonRenderTextureDescriptor.usage = [.renderTarget, .shaderRead]
        ribbonRenderTextureDescriptor.pixelFormat = view.colorPixelFormat
        ribbonRenderTextureDescriptor.width = drawableWidth
        ribbonRenderTextureDescriptor.height = drawableHeight
        ribbonRenderTextureDescriptor.textureType = .type2D
        ribbonRenderTexture = device.makeTexture(descriptor: ribbonRenderTextureDescriptor)
        
        let ribbonRenPassDesc = MTLRenderPassDescriptor()
        ribbonRenPassDesc.colorAttachments[0].texture = ribbonRenderTexture
        ribbonRenPassDesc.colorAttachments[0].loadAction = .clear
        ribbonRenPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0)
        ribbonRenPassDesc.colorAttachments[0].storeAction = .store
        ribbonRenderPassDescriptor = ribbonRenPassDesc
        
        // initialize shadow rendering buffers
        r1Polygon = .Circle(radius: r1, deltaTheta: deltaTheta)
        r1IndexCount = r1Polygon.indices.count
        r1VertexBuffer = device.makeBuffer(length: r1Polygon.vertices.count * MemoryLayout<Float>.size * kMaxBuffersInFlight)
        r1IndexBuffer = device.makeBuffer(bytes: r1Polygon.indices, length: MemoryLayout<UInt32>.size * r1IndexCount)
        
        r2Polygon = .CircularRibbon(lowerRadius: r2, upperRadius: r2 + 2.5, deltaTheta: deltaTheta)
        r2IndexCount = r2Polygon.indices.count
        r2VertexBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * r2Polygon.vertices.count * kMaxBuffersInFlight)
        r2IndexBuffer = device.makeBuffer(bytes: r2Polygon.indices, length: MemoryLayout<UInt32>.size * r2IndexCount)
        shadowUniformsBuffer = device.makeBuffer(length: kAlignedShadowUniformsSize * kMaxBuffersInFlight)
        
        shadowInstanceUniformsBuffer = device.makeBuffer(length: kAlignedShadowInstanceUniformsSize * 2 * kMaxBuffersInFlight)
        
        // Initialize shadow texture
        let shadowTextureDescriptor = MTLTextureDescriptor()
        shadowTextureDescriptor.usage = [.shaderRead, .renderTarget, .shaderWrite]
        shadowTextureDescriptor.textureType = .type2D
        shadowTextureDescriptor.width = drawableWidth
        shadowTextureDescriptor.height = drawableHeight
        shadowTextureDescriptor.pixelFormat = .bgra8Unorm
        
        shadowTexture = device.makeTexture(descriptor: shadowTextureDescriptor)
        
        let shadowDepthTextureDescriptor = MTLTextureDescriptor()
        shadowDepthTextureDescriptor.usage = [.renderTarget]
        shadowDepthTextureDescriptor.textureType = .type2D
        shadowDepthTextureDescriptor.storageMode = .private
        shadowDepthTextureDescriptor.width = drawableWidth
        shadowDepthTextureDescriptor.height = drawableHeight
        shadowDepthTextureDescriptor.pixelFormat = .depth32Float_stencil8
        shadowDepthTexture = device.makeTexture(descriptor: shadowDepthTextureDescriptor)
        
        // initialize shadow render pass descriptor
        let shadowRenPassDesc = MTLRenderPassDescriptor()
        shadowRenPassDesc.colorAttachments[0].texture = shadowTexture
        shadowRenPassDesc.depthAttachment.texture = shadowDepthTexture
        shadowRenPassDesc.stencilAttachment.texture = shadowDepthTexture
        shadowRenPassDesc.depthAttachment.loadAction = .clear
        shadowRenPassDesc.depthAttachment.storeAction = .store
        shadowRenPassDesc.colorAttachments[0].loadAction = .clear
        shadowRenPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0)
        
        shadowRenderPassDescriptor = shadowRenPassDesc
        
        let blendFunction = library.makeFunction(name: "blendKernel")!
        blendKernelState = try device.makeComputePipelineState(function: blendFunction)
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
        
        if !shadowsInitialized {
            r1VertexBufferOffset = r1Polygon.vertices.count * MemoryLayout<Float>.size * dynamicBufferIndex
            r1VertexBufferAddress = r1VertexBuffer.contents().advanced(by: r1VertexBufferOffset)
            
            r2VertexBufferOffset = r2Polygon.vertices.count * MemoryLayout<Float>.size * dynamicBufferIndex
            r2VertexBufferAddress = r2VertexBuffer.contents().advanced(by: r2VertexBufferOffset)
            
            shadowUniformsBufferOffset = kAlignedShadowUniformsSize * dynamicBufferIndex
            shadowUniformsBufferAddress = shadowUniformsBuffer.contents().advanced(by: shadowUniformsBufferOffset)
            
            shadowInstanceUniformsBufferOffset = kAlignedShadowInstanceUniformsSize * 2 * dynamicBufferIndex
            shadowInstanceUniformsAddress = shadowInstanceUniformsBuffer.contents().advanced(by: shadowInstanceUniformsBufferOffset)
        }
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
        uniformsBufferAddress.assumingMemoryBound(to: Uniforms.self).pointee.color = simd_float3(x: rgbColor[0], y: rgbColor[1], z: rgbColor[2])
        uniformsBufferAddress.assumingMemoryBound(to: Uniforms.self).pointee.lightColor = lightColor
        
        // update ribbon vertex buffer
        ribbonVertexBufferAddress.assumingMemoryBound(to: Float.self).initialize(from: ribbon.vertices, count: ribbon.vertices.count)
        // update ribbon colors buffer
        ribbonColorsBufferAddress.assumingMemoryBound(to: Float.self).initialize(from: ribbon.colors, count: ribbon.colors.count)
        // update ribbon uniforms
        ribbonUniformsBufferAddress.assumingMemoryBound(to: RibbonUniforms.self).pointee.projection = ribbonProjectionMatrix
        ribbonUniformsBufferAddress.assumingMemoryBound(to: RibbonUniforms.self).pointee.transform = ribbonTransform
        
        if !shadowsInitialized {
            // update r1 vertex buffer
            r1VertexBufferAddress.assumingMemoryBound(to: Float.self).initialize(from: r1Polygon.vertices, count: r1Polygon.vertices.count)
            
            // update r2 vertex buffer
            r2VertexBufferAddress.assumingMemoryBound(to: Float.self).initialize(from: r2Polygon.vertices, count: r2Polygon.vertices.count)
            
            // update shadow uniforms
            shadowUniformsBufferAddress.assumingMemoryBound(to: ShadowUniforms.self).pointee.projection = ribbonProjectionMatrix
            
            // update shadow instance uniforms
            shadowInstanceUniformsAddress.assumingMemoryBound(to: ShadowInstanceUniforms.self).pointee.color = [0.0, 0.0, 0.0, 0.0]
            shadowInstanceUniformsAddress.assumingMemoryBound(to: ShadowInstanceUniforms.self).pointee.transform = Transform.init(translation: [0.0, 0.0, 0.8]).matrix
            shadowInstanceUniformsAddress.assumingMemoryBound(to: ShadowInstanceUniforms.self).advanced(by: 1).pointee.color = [0.1, 0.1, 0.1, 0.5]
            shadowInstanceUniformsAddress.assumingMemoryBound(to: ShadowInstanceUniforms.self).advanced(by: 1).pointee.transform = shadowTransform.matrix
        }
    }
    
    private func renderShadows(commandBuffer: MTLCommandBuffer) {
        shadowRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        if let shadowRenderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: shadowRenderPassDescriptor) {
            // render r1 shadow
            shadowRenderEncoder.setRenderPipelineState(shadowRenderState)
            shadowRenderEncoder.setDepthStencilState(shadowDepthState)
            shadowRenderEncoder.setFrontFacing(.counterClockwise)
            shadowRenderEncoder.setCullMode(.back)
            shadowRenderEncoder.setVertexBuffer(r1VertexBuffer, offset: r1VertexBufferOffset, index: ShadowBufferIndex.positions.rawValue)
            shadowRenderEncoder.setVertexBuffer(shadowUniformsBuffer, offset: shadowUniformsBufferOffset, index: ShadowBufferIndex.uniforms.rawValue)
            shadowRenderEncoder.setVertexBuffer(shadowInstanceUniformsBuffer, offset: shadowInstanceUniformsBufferOffset, index: ShadowBufferIndex.instanceUniforms.rawValue)
            shadowRenderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: r1IndexCount, indexType: .uint32, indexBuffer: r1IndexBuffer, indexBufferOffset: 0, instanceCount: 2)
            //shadowRenderEncoder.endEncoding()
            
            // render r2 shadow
            shadowRenderEncoder.setVertexBuffer(r2VertexBuffer, offset: r2VertexBufferOffset, index: ShadowBufferIndex.positions.rawValue)
            shadowRenderEncoder.setVertexBuffer(shadowUniformsBuffer, offset: shadowUniformsBufferOffset, index: ShadowBufferIndex.uniforms.rawValue)
            shadowRenderEncoder.setVertexBuffer(shadowInstanceUniformsBuffer, offset: shadowInstanceUniformsBufferOffset, index: ShadowBufferIndex.instanceUniforms.rawValue)
            shadowRenderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: r2IndexCount, indexType: .uint32, indexBuffer: r2IndexBuffer, indexBufferOffset: 0, instanceCount: 2)
            shadowRenderEncoder.endEncoding()
            
            let blur = MPSImageGaussianBlur(device: GPUDevice.shared, sigma: 12.0)
            let inPlaceTexture: UnsafeMutablePointer<MTLTexture> = .allocate(capacity: 1)
            inPlaceTexture.initialize(to: shadowTexture)
            blur.encode(commandBuffer: commandBuffer, inPlaceTexture: inPlaceTexture)
            
            shadowRenderPassDescriptor.colorAttachments[0].loadAction = .load
            if let shadowRenderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: shadowRenderPassDescriptor) {
                shadowRenderEncoder.setRenderPipelineState(shadowRenderState)
                shadowRenderEncoder.setDepthStencilState(shadowDepthState)
                shadowRenderEncoder.setFrontFacing(.counterClockwise)
                shadowRenderEncoder.setCullMode(.back)
                shadowRenderEncoder.setVertexBuffer(r1VertexBuffer, offset: r1VertexBufferOffset, index: ShadowBufferIndex.positions.rawValue)
                shadowRenderEncoder.setVertexBuffer(shadowUniformsBuffer, offset: shadowUniformsBufferOffset, index: ShadowBufferIndex.uniforms.rawValue)
                shadowRenderEncoder.setVertexBuffer(shadowInstanceUniformsBuffer, offset: shadowInstanceUniformsBufferOffset, index: ShadowBufferIndex.instanceUniforms.rawValue)
                shadowRenderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: r1IndexCount, indexType: .uint32, indexBuffer: r1IndexBuffer, indexBufferOffset: 0, instanceCount: 1)
                //shadowRenderEncoder.endEncoding()
                
                shadowRenderEncoder.setVertexBuffer(r2VertexBuffer, offset: r2VertexBufferOffset, index: ShadowBufferIndex.positions.rawValue)
                shadowRenderEncoder.setVertexBuffer(shadowUniformsBuffer, offset: shadowUniformsBufferOffset, index: ShadowBufferIndex.uniforms.rawValue)
                shadowRenderEncoder.setVertexBuffer(shadowInstanceUniformsBuffer, offset: shadowInstanceUniformsBufferOffset, index: ShadowBufferIndex.instanceUniforms.rawValue)
                shadowRenderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: r2IndexCount, indexType: .uint32, indexBuffer: r2IndexBuffer, indexBufferOffset: 0, instanceCount: 1)
                shadowRenderEncoder.endEncoding()
            }
        }
    }
    
    // MARK: - MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableWidth = Int(size.width)
        drawableHeight = Int(size.height)
        
        let aspectRatio = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_left_hand(fovyRadians: .pi / 4.0, aspectRatio: aspectRatio, nearZ: 0.1, farZ: 100.0)
        
        let height: Float = 10.0
        let width: Float = height * aspectRatio
        
        ribbonProjectionMatrix = matrix_orthographic_left_hand(left: -width / 2.0,
                                                               right: width / 2.0,
                                                               top: height / 2.0,
                                                               bottom: -height / 2.0,
                                                               near: 0.0, far: 10.0)
        do {
            try loadMetal()
        } catch {
            print("error loading metal: \(error.localizedDescription)")
        }
    }
    
    func draw(in view: MTKView) {
        let _ = _inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        var read: Bool = false
        
        if let commandBuffer = commandQueue?.makeCommandBuffer() {
            commandBuffer.label = "Render Command buffer"
            let semaphore = _inFlightSemaphore
            commandBuffer.addCompletedHandler { _ in
                if read { self.readSample() }
                semaphore.signal()
            }
            
            updateDynamicBuffer()
            updateAppState()
            
            if !shadowsInitialized {
                renderShadows(commandBuffer: commandBuffer)
                shadowsInitialized = true
            }
            
            // render ribbon
            if let ribbonRenderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: ribbonRenderPassDescriptor) {
                ribbonRenderEncoder.setRenderPipelineState(ribbonRenderState)
                ribbonRenderEncoder.setVertexBuffer(ribbonVertexBuffer, offset: ribbonVertexBufferOffset, index: RibbonBufferIndex.positions.rawValue)
                ribbonRenderEncoder.setVertexBuffer(ribbonColorsBuffer, offset: ribbonColorsBufferOffset, index: RibbonBufferIndex.colors.rawValue)
                ribbonRenderEncoder.setVertexBuffer(ribbonUniformsBuffer, offset: ribbonUniformsBufferOffset, index: RibbonBufferIndex.uniforms.rawValue)
                ribbonRenderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: ribbonIndexCount, indexType: .uint32, indexBuffer: ribbonIndexBuffer, indexBufferOffset: 0)
                ribbonRenderEncoder.endEncoding()
                
                // blend shadow with ribbon
                let computeKernel = commandBuffer.makeComputeCommandEncoder()!
                computeKernel.setComputePipelineState(blendKernelState)
                computeKernel.setTexture(shadowTexture, index: 0)
                computeKernel.setTexture(ribbonRenderTexture, index: 1)
                computeKernel.setTexture(view.currentDrawable!.texture, index: 2)
                let threadGroupSize = MTLSizeMake(16, 16, 1)
                let threadGroupCount = MTLSizeMake((shadowTexture.width + threadGroupSize.width - 1) / threadGroupSize.width,
                                                   (shadowTexture.height + threadGroupSize.height - 1) / threadGroupSize.height,
                                                   1)
                computeKernel.dispatchThreadgroups(threadGroupCount, threadsPerThreadgroup: threadGroupSize)
                computeKernel.endEncoding()
            }
            
            if let renderPassDescriptor = view.currentRenderPassDescriptor {
                renderPassDescriptor.colorAttachments[0].loadAction = .load
                renderPassDescriptor.depthAttachment.loadAction = .clear
                if let bodyRenderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                    // render body
                    bodyRenderEncoder.setRenderPipelineState(renderState)
                    bodyRenderEncoder.setCullMode(.back)
                    bodyRenderEncoder.setFrontFacing(.counterClockwise)
                    bodyRenderEncoder.setVertexBuffer(vertexBuffer, offset: vertexBufferOffset, index: BufferIndex.meshPositions.rawValue)
                    bodyRenderEncoder.setVertexBuffer(uniformsBuffer, offset: uniformsBufferOffset, index: BufferIndex.uniforms.rawValue)
                    bodyRenderEncoder.setFragmentBuffer(uniformsBuffer, offset: uniformsBufferOffset, index: BufferIndex.uniforms.rawValue)
                    bodyRenderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32, indexBuffer: indexBuffer, indexBufferOffset: 0)
                    
                    bodyRenderEncoder.popDebugGroup()
                    bodyRenderEncoder.endEncoding()
                }
                
                if let point = samplePoint {
                    read = true
                    let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
                    blitEncoder.copy(from: ribbonRenderTexture,
                                     sourceSlice: 0,
                                     sourceLevel: 0,
                                     sourceOrigin: MTLOrigin(x: Int(point.x), y: Int(point.y), z: 0),
                                     sourceSize: MTLSizeMake(1, 1, 1),
                                     to: sampleBuffer,
                                     destinationOffset: 0,
                                     destinationBytesPerRow: 4,
                                     destinationBytesPerImage: 4)
                    blitEncoder.endEncoding()
                }
            }
            if let drawable = view.currentDrawable {
                commandBuffer.present(drawable)
            }
            
            commandBuffer.commit()
        }
    }
}
