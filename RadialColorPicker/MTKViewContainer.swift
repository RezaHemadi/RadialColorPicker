//
//  MTKViewContainer.swift
//  RadialColorPicker
//
//  Created by Reza on 5/29/23.
//

import Foundation
import SwiftUI
import MetalKit

struct MTKViewContainer: UIViewRepresentable {
    var renderer: Renderer
    
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.framebufferOnly = false
        view.isOpaque = false
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float_stencil8
        view.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0)
        view.device = GPUDevice.shared
        renderer.view = view
        view.delegate = renderer
        
        return view
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        
    }
    
    class Coordinator: NSObject {
        var parent: MTKViewContainer
        
        init(_ container: MTKViewContainer) {
            self.parent = container
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
}
