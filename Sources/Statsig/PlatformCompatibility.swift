import Foundation

#if TEST

struct DeviceInfo {
    let systemVersion = "test.system.version"
    let systemName = "test_system"
    let model = "test_model"
    let os = "testOS"
}

class PlatformCompatibility {
    static let willResignActiveNotification = NSNotification.Name(
        rawValue: "test.willResignActiveNotification")
    static let willTerminateNotification = NSNotification.Name(
        rawValue: "test.willTerminateNotification")
    static let didBecomeActiveNotification = NSNotification.Name(
        rawValue: "test.didBecomeActiveNotification")

    static let deviceInfo = DeviceInfo()

    static func getRootViewControllerClassName(_ callback: @escaping (_ name: String?) -> Void) {
        callback(nil)
    }
}

#elseif os(watchOS)

import WatchKit
import UIKit

struct DeviceInfo {
    let systemVersion = WKInterfaceDevice.current().systemVersion
    let systemName = WKInterfaceDevice.current().systemName
    let model = WKInterfaceDevice.current().model
    let os = "watchOS"
}

class PlatformCompatibility {
    static let willResignActiveNotification = WKExtension.applicationWillResignActiveNotification
    static let willTerminateNotification = NSNotification.Name(
        rawValue: "willTerminateNotification")
    static let didBecomeActiveNotification = WKExtension.applicationDidBecomeActiveNotification

    static let deviceInfo = DeviceInfo()

    static func getRootViewControllerClassName(_ callback: @escaping (_ name: String?) -> Void) {
        ensureMainThread { [callback] in
            callback(nil)
        }
    }
}

#elseif os(iOS) || os(tvOS)

import UIKit

struct DeviceInfo {
    let systemVersion = UIDevice.current.systemVersion
    let systemName = UIDevice.current.systemName
    let model = UIDevice.current.model
    let os = UIDevice.current.userInterfaceIdiom == .tv ? "tvOS" : "iOS"
}

class PlatformCompatibility {
    static let willResignActiveNotification = UIApplication.willResignActiveNotification

    static let willTerminateNotification = UIApplication.willTerminateNotification
    static let didBecomeActiveNotification = UIApplication.didBecomeActiveNotification

    static let deviceInfo = DeviceInfo()

    static func getRootViewControllerClassName(_ callback: @escaping (_ name: String?) -> Void) {
        #if STATSIG_WIDGET_BUILD
        callback(nil)
        #else
        ensureMainThread { [callback] in
            if let klass = UIApplication.shared.keyWindow?.rootViewController?.classForCoder {
                callback("\(klass)")
            } else {
                callback(nil)
            }
        }
        #endif
    }
}

#elseif os(visionOS)

import UIKit

struct DeviceInfo {
    let systemVersion = UIDevice.current.systemVersion
    let systemName = UIDevice.current.systemName
    let model = UIDevice.current.model
    let os = "visionOS"
}

class PlatformCompatibility {
    static let willResignActiveNotification = UIApplication.willResignActiveNotification
    static let willTerminateNotification = UIApplication.willTerminateNotification
    static let didBecomeActiveNotification = UIApplication.didBecomeActiveNotification

    static let deviceInfo = DeviceInfo()

    static func getRootViewControllerClassName(_ callback: @escaping (_ name: String?) -> Void) {
        ensureMainThread { [callback] in
            let scene = UIApplication.shared.connectedScenes.first(where: { scene in
                return scene.activationState == UIScene.ActivationState.foregroundActive
            })

            if let root = (scene?.delegate as? UIWindowSceneDelegate)?.window??.rootViewController {
                callback("\(root)")
            } else {
                callback(nil)
            }
        }
    }
}

#elseif os(macOS)

import AppKit
import IOKit

struct DeviceInfo {
    let systemVersion: String
    let systemName = "macOS"
    let model: String
    let os = "macOS"

    init() {
        let service = IOServiceGetMatchingService(
            kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if let data = IORegistryEntryCreateCFProperty(
            service, "model" as CFString, kCFAllocatorDefault, 0
        ).takeRetainedValue() as? Data {
            model = data.text?.trimmingCharacters(in: .controlCharacters) ?? "Unknown"
        } else {
            model = "Unknown"
        }

        IOObjectRelease(service)

        let version = ProcessInfo.processInfo.operatingSystemVersion
        systemVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

class PlatformCompatibility {
    static let willResignActiveNotification = NSApplication.willResignActiveNotification
    static let willTerminateNotification = NSApplication.willTerminateNotification
    static let didBecomeActiveNotification = NSApplication.didBecomeActiveNotification

    static let deviceInfo = DeviceInfo()

    static func getRootViewControllerClassName(_ callback: @escaping (_ name: String?) -> Void) {
        ensureMainThread { [callback] in
            if let klass = NSApplication.shared.keyWindow?.contentViewController?.classForCoder {
                callback("\(klass)")
            } else {
                callback(nil)
            }
        }
    }
}

#else

// No PlatformCompatibility (Won't Compile)

#endif
