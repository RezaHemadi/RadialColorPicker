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

func matrix_orthographic_left_hand(left: Float, right: Float, top: Float, bottom: Float, near: Float, far: Float) -> matrix_float4x4 {
    return matrix_float4x4.init([2.0 / (right - left), 0.0, 0.0, 0.0],
                                [0.0, -2.0 / (bottom - top), 0.0, 0.0],
                                [0.0, 0.0, 1.0 / (far - near), 0.0],
                                [-(right + left) / (right - left), -(top + bottom) / (top - bottom), -near / (far - near), 1.0])
}
