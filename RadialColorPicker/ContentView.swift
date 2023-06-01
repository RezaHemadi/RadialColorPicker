//
//  ContentView.swift
//  RadialColorPicker
//
//  Created by Reza on 5/29/23.
//

import SwiftUI

struct ContentView: View {
    @State var color: Color = Color.init(hue: 0.0, saturation: 1.0, brightness: 1.0)
    var body: some View {
        RadialColorPickerView(color: $color)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
