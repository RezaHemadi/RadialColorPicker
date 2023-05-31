//
//  RadialColorPickerApp.swift
//  RadialColorPicker
//
//  Created by Reza on 5/29/23.
//

import SwiftUI

@main
struct RadialColorPickerApp: App {
    var renderer = Renderer()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(renderer)
        }
    }
}
