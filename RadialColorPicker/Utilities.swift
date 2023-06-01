//
//  Utilities.swift
//  RadialColorPicker
//
//  Created by Reza on 5/30/23.
//

import Foundation
import Transform
import SwiftUI
import UIKit

func rgb(h: Float, s: Float, l: Float) -> [Float] {
    let h = h / 360.0
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

extension Color {
    func toHex() -> String? {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)

        if components.count >= 4 {
            a = Float(components[3])
        }

        if a != Float(1.0) {
            return String(format: "%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0

        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0

        } else {
            return nil
        }

        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

