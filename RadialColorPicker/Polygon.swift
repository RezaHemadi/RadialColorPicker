//
//  Polygon.swift
//  RadialColorPicker
//
//  Created by Reza on 5/30/23.
//

import Foundation
import Transform

struct ColoredPolygon {
    let vertices: [Float]
    let indices: [UInt32]
    var colors: [Float]
    var deltaTheta: Float
    
    static func Circle(radius: Float, deltaTheta: Float) -> Self {
        var vertices: [Float] = []
        var indices: [UInt32] = []
        var colors: [Float] = []
        
        vertices.append(contentsOf: [0.0, 0.0, 0.0])
        colors.append(contentsOf: [1.0, 0.0, 0.0])
        
        for angle in stride(from: 0.0, through: 2.0 * Float.pi, by: deltaTheta) {
            let x = radius * cos(angle)
            let y = radius * sin(angle)
            
            vertices.append(contentsOf: [x, y, 0.0])
            colors.append(contentsOf: [1.0, 0.0, 0.0])
        }
        
        // process indices
        for i in 1..<(vertices.count - 1) {
            indices.append(contentsOf: [0, UInt32(i), UInt32(i + 1)])
        }
        
        return .init(vertices: vertices, indices: indices, colors: colors, deltaTheta: deltaTheta)
    }
    
    static func CircularRibbon(lowerRadius r1: Float, upperRadius r2: Float, deltaTheta: Float) -> Self {
        guard r1.isLess(than: r2) else { fatalError() }
        
        var vertices: [Float] = []
        var indices: [UInt32] = []
        var colors: [Float] = []
        
        // add two primary points
        vertices.append(contentsOf: [r1, 0.0, 0.0])
        let col = rgb(h: 0.0, s: 1.0, l: 0.5)
        colors.append(contentsOf: col)
        vertices.append(contentsOf: [r2, 0.0, 0.0])
        colors.append(contentsOf: col)
        
        for angle in stride(from: deltaTheta, through: 2 * Float.pi, by: deltaTheta) {
            // we add two points on each iteration(p2, p3)
            let p2x: Float = r1 * cos(angle)
            let p2y: Float = r1 * sin(angle)
            
            let p3x: Float = r2 * cos(angle)
            let p3y: Float = r2 * sin(angle)
            
            vertices.append(contentsOf: [p2x, p2y, 0.0])
            let col = rgb(h: Angle.init(radians: angle).degress, s: 1.0, l: 0.5)
            colors.append(contentsOf: col)
            vertices.append(contentsOf: [p3x, p3y, 0.0])
            colors.append(contentsOf: col)
            
            let p3idx: UInt32 = UInt32(vertices.count / 3) - 1
            let p2idx: UInt32 = p3idx - 1
            let p1idx: UInt32 = p2idx - 1
            let p0idx: UInt32 = p1idx - 1
            
            // add indices
            indices.append(contentsOf: [p0idx, p1idx, p2idx])
            indices.append(contentsOf: [p2idx, p1idx, p3idx])
        }
        
        return .init(vertices: vertices, indices: indices, colors: colors, deltaTheta: deltaTheta)
    }
    
    mutating func updateColors(s: Float, l: Float) {
        colors.removeAll(keepingCapacity: true)
        let col = rgb(h: 0.0, s: s, l: l)
        colors.append(contentsOf: col)
        colors.append(contentsOf: col)
        
        for angle in stride(from: deltaTheta, through: 2 * Float.pi, by: deltaTheta) {
            let col = rgb(h: Angle.init(radians: angle).degress, s: s, l: l)
            colors.append(contentsOf: col)
            colors.append(contentsOf: col)
        }
    }
}
