//
//  Projections.swift
//  RadialColorPicker
//
//  Created by Reza on 5/29/23.
//

import Foundation

func matrix_perspective_left_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let a = (1 / tanf(fovy * 0.5)) / aspectRatio
    let b = 1.0 / (tanf(fovy * 0.5))
    let c = farZ / (farZ - nearZ)
    let e = -nearZ * farZ / (farZ - nearZ)
    
    return matrix_float4x4(columns: ([a, 0.0, 0.0, 0.0],
                                     [0.0, b, 0.0, 0.0],
                                     [0.0, 0.0, c, 1.0],
                                     [0.0, 0.0, e, 0.0]))
}
