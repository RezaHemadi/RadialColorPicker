//
//  GPUDevice.swift
//  RadialColorPicker
//
//  Created by Reza on 5/29/23.
//

import Foundation
import MetalKit

class GPUDevice {
    static var shared: MTLDevice {
        return MTLCreateSystemDefaultDevice()!
    }
}
