//
//  ContentView.swift
//  RayTracing
//
//  Created by Mikhail Gorobets on 19.05.2020.
//  Copyright © 2020 Mikhail Gorobets. All rights reserved.
//

import SwiftUI
import MetalKit




struct RayTracingView: UIViewRepresentable {
    
    var view: MTKView
    
    init() {
        view = MTKView()
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.device = MTLCreateSystemDefaultDevice()!
    }
    
    func makeCoordinator() -> Render {
        Render(view: view)
    }
    
    func makeUIView(context: Context) -> MTKView {
        view.device = context.coordinator.device
        view.delegate = context.coordinator
        return view
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        
        
    }
    
}




struct ContentView: View {
    var body: some View {
        RayTracingView().edgesIgnoringSafeArea(.all)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
