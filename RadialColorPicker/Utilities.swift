//
//  Utilities.swift
//  RadialColorPicker
//
//  Created by Reza on 5/30/23.
//

import Foundation
import Transform
import SwiftUI

func rgb(h: Float, s: Float, l: Float) -> [Float] {
    let h = h / 360.0
    print(h)
    let color = Color(hue: Double(h), saturation: Double(s), brightness: Double(l))
    var r: CGFloat = 0.0
    var g: CGFloat = 0.0
    var b: CGFloat = 0.0
    
    let uiColor = UIColor(color)
    uiColor.getRed(&r, green: &g, blue: &b, alpha: nil)
    
    return [Float(r), Float(g), Float(b)]
}

/// h angle is in degrees, returns [0, 1] range
/*
func rgb(h: Float, s: Float, l: Float) -> [Float] {
    assert(!h.isLess(than: 0.0))
    
    var R: Float = 0.0
    var G: Float = 0.0
    var B: Float = 0.0
    
    let d = s * (1 - abs(2 * l - 1))
    let m = (l - 0.5 * d)
    
    let x = d * (1.0 - abs((h / 60.0).remainder(dividingBy: 2.0) - 1.0 ))
    
    if h.isLess(than: 60.0) {
        R = d + m
        G = x + m
        B = m
    } else if h.isLess(than: 120.0) {
        R = x + m
        G = d + m
        B = m
    } else if h.isLess(than: 180.0) {
        R = m
        G = d + m
        B = x + m
    } else if h.isLess(than: 240.0) {
        R = m
        G = x + m
        B = d + m
    } else if h.isLess(than: 300.0) {
        R = x + m
        G = m
        B = d + m
    } else if h.isLess(than: 360.0) {
        R = d + m
        G = m
        B = x + m
    }
    
    return [R, G, B]
} */

// r g b values should be in [0, 255] range
func hsl(r: Float, g: Float, b: Float) -> [Float] {
    let M: Float = max(r, g, b)
    let m: Float = min(r, g, b)
    let d: Float = (M - m) / 255.0
    
    let L: Float = (0.5 * (M + m)) / 255.0
    let S: Float
    
    if L == 0.0 {
        S = 0.0
    } else {
        S = d / (1.0 - abs(2 * L - 1))
    }
    
    let H: Float
    if b.isLessThanOrEqualTo(g) {
        let radians = acos(((r - g * 0.5 - b * 0.5) / sqrt(r * r + g * g + b * b - r * g - r * b - g * b)))
        H = Angle(radians: radians).degress
    } else {
        let radians = acos(((r - g * 0.5 - b * 0.5) / sqrt(r * r + g * g + b * b - r * g - r * b - g * b)))
        H = 360.0 - Angle(radians: radians).degress
    }
    
    return [H, S, L]
}
