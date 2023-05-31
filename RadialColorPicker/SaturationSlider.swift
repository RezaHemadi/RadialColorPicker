//
//  SaturationSlider.swift
//  RadialColorPicker
//
//  Created by Reza on 5/31/23.
//

import SwiftUI

struct SaturationSlider: View {
    @EnvironmentObject var renderer: Renderer
    
    @State var needleX: CGFloat = 0.0
    @State var sliderWidth: CGFloat?
    
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0.0)
            .onChanged { value in
                withAnimation {
                    guard value.location.x.isLess(than: sliderWidth!) else { return }
                    guard !value.location.x.isLess(than: 0.0) else { return }
                    
                    needleX = value.location.x
                    if sliderWidth != nil {
                        renderer.saturation = getSaturation(value.location.x)
                    }
                }
            }
            .onEnded { value in
                withAnimation {
                    guard value.location.x.isLess(than: sliderWidth!) else { return }
                    guard !value.location.x.isLess(than: 0.0) else { return }
                    
                    needleX = value.location.x
                    if sliderWidth != nil {
                        renderer.saturation = getSaturation(value.location.x)
                    }
                }
            }
    }
    
    private func getSaturation(_ needleX: CGFloat) -> Double {
        (needleX) / sliderWidth!
    }
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let midY = geometry.size.height / 2.0
                let width = geometry.size.width
                path.move(to: .init(x: 0.0, y: midY))
                path.addLine(to: .init(x: width, y: midY))
            }
            .stroke(LinearGradient(colors: [Color.init(hue: renderer.hue, saturation: 0.0, brightness: renderer.brightness),
                                            Color.init(hue: renderer.hue, saturation: 1.0, brightness: renderer.brightness)],
                                   startPoint: .leading,
                                   endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 5.0, lineCap: .round, lineJoin: .round))
            .onAppear() {
                sliderWidth = geometry.size.width
                needleX = geometry.size.width * renderer.saturation
            }
            Image("SliderNeedle")
                .resizable()
                .scaledToFit()
                .frame(width: 30.0, height: 30.0)
                .position(.init(x: needleX, y: geometry.size.height / 2.0))
                .gesture(dragGesture)
        }
    }
}

struct SaturationSlider_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.blue
            
            SaturationSlider()
                .frame(width: 500.0, height: 200.0)
        }
    }
}
