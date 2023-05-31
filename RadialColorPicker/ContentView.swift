//
//  ContentView.swift
//  RadialColorPicker
//
//  Created by Reza on 5/29/23.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var renderer: Renderer
    
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0.0)
            .onChanged { value in
                renderer.samplePoint(value.location)
            }
    }
    
    var body: some View {
        ZStack {
            Image("T")
                .resizable()
                .background(.white)
            VStack {
                MTKViewContainer(renderer: renderer)
                    .frame(width: 300.0, height: 300.0)
                    .gesture(dragGesture)
                SaturationSlider()
                    .frame(width: 400.0, height: 50.0)
                BrightnessSlider()
                    .frame(width: 400.0, height: 50.0)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
