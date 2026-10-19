//
//  HEARTS_APP.swift
//
//  Created by Abner Garza on 9/15/26.
//

import SwiftUI
import UserNotifications

@main
struct HEARTSApp: App {
    @UIApplicationDelegateAdaptor(HEARTSAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ExposomeDashboardView()
        }
    }
}

/// Lets HEARTS air and heat alerts show as banners even while the app is open.
final class HEARTSAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
