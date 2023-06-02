//
//  RadialColorPickerView.swift
//  RadialColorPicker
//
//  Created by Reza on 6/1/23.
//

import SwiftUI

struct RadialColorPickerView: View {
    @ObservedObject private var renderer: Renderer = Renderer(color: .init(hue: 0.0, saturation: 1.0, brightness: 1.0, alpha: 1.0))
    @Binding var color: Color
    private let pastboard = UIPasteboard.general
    @State private var hex: String = ""
    
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0.0)
            .onChanged { value in
                renderer.samplePoint(value.location)
            }
    }
    
    private func setColorFromClipboard() {
        if let pasteString = pastboard.string {
            withAnimation{
                hex = pasteString
            }
        }
    }
    
    var body: some View {
        VStack {
            MTKViewContainer(renderer: renderer)
                .frame(width: 300.0, height: 300.0)
                .gesture(dragGesture)
                .onAppear() {
                    renderer.color = UIColor(color)
                    hex = "#" + (color.toHex() ?? "")
                }
                .onChange(of: renderer.color) { newValue in
                    color = Color(uiColor: newValue)
                    hex = "#" + (color.toHex() ?? "")
                }
                .onChange(of: color) { newValue in
                    renderer.color = UIColor(newValue)
                    hex = "#" + (color.toHex() ?? "")
                }
            
            ZStack {
                RoundedRectangle(cornerRadius: 10.0)
                    .fill(Color.init(white: 239/255))
                    .frame(width: 150.0, height: 30.0)
                
                RoundedRectangle(cornerRadius: 10.0)
                    .stroke(Color.white)
                    .frame(width: 150.0, height: 30.0)
                HStack {
                    TextField("", text: $hex)
                        .minimumScaleFactor(0.5)
                        .frame(width: 92.0, height: 23.0)
                        .foregroundColor(Color.init(white: 0.2))
                        .onChange(of: hex) { newValue in
                            if let newColor = Color.init(hex: hex) {
                                withAnimation {
                                    renderer.color = UIColor(newColor)
                                }
                            }
                        }
                    Button(action: setColorFromClipboard) {
                        Image("bxs_paste")
                            .resizable()
                            .frame(width: 15.0, height: 15.0)
                    }
                }
                
            }
            HStack(spacing: 30.0) {
                Text("S")
                SaturationSlider(renderer: renderer)
                    .frame(width: 250.0, height: 30.0)
            }
            
            HStack(spacing: 30.0) {
                Text("L")
                BrightnessSlider(renderer: renderer)
                    .frame(width: 250.0, height: 30.0)
            }
        }
    }
}

struct RadialColorPickerView_Previews: PreviewProvider {
    static var previews: some View {
        RadialColorPickerView(color: .constant(.init(hue: 0.0, saturation: 1.0, brightness: 0.5)))
    }
}
