//
//  SceneDelegate.swift
//  RayTracing
//
//  Created by Mikhail Gorobets on 19.05.2020.
//  Copyright © 2020 Mikhail Gorobets. All rights reserved.
//

import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
       
        let context = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
        let contentView = ContentView().environment(\.managedObjectContext, context)
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = UIHostingController(rootView: contentView)
            self.window = window
            window.makeKeyAndVisible()
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
       
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
       
    }

    func sceneWillResignActive(_ scene: UIScene) {
     
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
       
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        (UIApplication.shared.delegate as? AppDelegate)?.saveContext()
    }


}

