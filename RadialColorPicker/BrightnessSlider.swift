//
//  BrightnessSlider.swift
//  RadialColorPicker
//
//  Created by Reza on 5/31/23.
//

import SwiftUI

struct BrightnessSlider: View {
    @ObservedObject var renderer: Renderer
    
    @State var needleX: CGFloat = 0.0
    @State var sliderWidth: CGFloat?
    
    var hue: Double {
        let uiColor = UIColor(renderer.color)
        var h: CGFloat = 0.0
        uiColor.getHue(&h, saturation: nil, brightness: nil, alpha: nil)
        return Double(h)
    }
    
    var saturation: Double {
        let uiColor = UIColor(renderer.color)
        var s: CGFloat = 0.0
        uiColor.getHue(nil, saturation: &s, brightness: nil, alpha: nil)
        return Double(s)
    }
    
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0.0)
            .onChanged { value in
                withAnimation {
                    guard value.location.x.isLess(than: sliderWidth!) else { return }
                    guard !value.location.x.isLess(than: 0.0) else { return }
                    
                    needleX = value.location.x
                    if sliderWidth != nil {
                        renderer.brightness = getBrightness(value.location.x)
                    }
                }
            }
            .onEnded { value in
                withAnimation {
                    guard value.location.x.isLess(than: sliderWidth!) else { return }
                    guard !value.location.x.isLess(than: 0.0) else { return }
                    
                    needleX = value.location.x
                    
                }
            }
    }
    
    private func getBrightness(_ needleX: CGFloat) -> Double {
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
            .stroke(LinearGradient(colors: [Color.init(hue: hue, saturation: saturation, brightness: 0.0),
                                            Color.init(hue: hue, saturation: saturation, brightness: 1.0)], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 5.0, lineCap: .round, lineJoin: .round))
            .onAppear() {
                sliderWidth = geometry.size.width
                needleX = geometry.size.width * renderer.brightness
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

struct BrightnessSlider_Previews: PreviewProvider {
    static var previews: some View {
        BrightnessSlider(renderer: Renderer(color: .init(hue: 0.0, saturation: 1.0, brightness: 0.5)))
    }
}
