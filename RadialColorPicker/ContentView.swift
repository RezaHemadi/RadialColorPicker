//
//  ContentView.swift
//  RadialColorPicker
//
//  Created by Reza on 5/29/23.
//

import SwiftUI

struct ContentView: View {
    @State var renderer = Renderer()
    
    var body: some View {
        ZStack {
            Circle()
                .fill(.gray)
                .frame(width: 1000.0, height: 1000.0)
            
            MTKViewContainer(renderer: renderer)
                .frame(width: 500.0, height: 500.0)
                .padding()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
