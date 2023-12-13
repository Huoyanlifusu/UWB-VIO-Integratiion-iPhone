//
//  AppDelegate.swift
//  ScanKit
//
//  Created by Kenneth Schröder on 10.08.21.
//

import UIKit
import FirebaseCore

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow? 

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
//        if !ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
//            // Ensure that the device supports scene depth and present
//            //  an error-message view controller, if not.
//            let storyboard = UIStoryboard(name: "Main", bundle: nil)
//            window?.rootViewController = storyboard.instantiateViewController(withIdentifier: "unsupportedDeviceMessage")
//        }
        FirebaseApp.configure()
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state.
        // This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message)
        // or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks.
        // Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers,
        // and store enough application state information to restore your application to its current state in case it is terminated later.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state;
        // here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive.
        // If the application was previously in the background, optionally refresh the user interface.
    }
    func applicationWillTerminate(_ application: UIApplication) {
        if ScanConfig.isRecording {
            let fileManager = FileManager.default
            let currentPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
            do {
                let directoryContents = try fileManager.contentsOfDirectory(atPath: currentPath)
                for path in directoryContents {
                    if ScanConfig.url != nil && ScanConfig.url!.lastPathComponent == path {
                        let combinedPath = currentPath + "/" + path
                        try fileManager.removeItem(atPath: combinedPath)
                    }
                }
            } catch let error {
                print("Error: \(error.localizedDescription)")
            }
            Logger.shared.debugPrint("Forced exit.")
        }
    }
}
