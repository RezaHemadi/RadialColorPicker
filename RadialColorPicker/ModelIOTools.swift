//
//  ModelIOTools.swift
//  RadialColorPicker
//
//  Created by Reza on 5/29/23.
//

import Foundation
import ModelIO

/// Travese scene graph rooted at object and run a closure on each element,
///  passing on each element's flattened node index as well as it's parent index
func walkSceneGraph(rootAt object: MDLObject, perNodeBody: (MDLObject, Int, Int?) -> Void) {
    var currentIndex = 0
    
    func walkGraph(object: MDLObject, currentIndex: inout Int, parentIndex: Int?, perNodeBody: (MDLObject, Int, Int?) -> Void) {
        perNodeBody(object, currentIndex, parentIndex)
        
        let ourIndex = currentIndex
        currentIndex += 1
        var pointer: ObjCBool = false
        var count: Int = 0
        object.enumerateChildObjects(of: MDLObject.self, root: object, using: { _, _ in count += 1 }, stopPointer: &pointer)
        guard count != 0 else { return }
        
        for childIndex in 0..<object.children.count {
            walkGraph(
                object: object.children[childIndex],
                currentIndex: &currentIndex,
                parentIndex: ourIndex,
                perNodeBody: perNodeBody
            )
        }
    }
    
    walkGraph(object: object, currentIndex: &currentIndex, parentIndex: nil, perNodeBody: perNodeBody)
}
