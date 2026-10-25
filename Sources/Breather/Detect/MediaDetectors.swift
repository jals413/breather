import AppKit
import CoreAudio
import CoreMediaIO
import IOKit.pwr_mgt

/// Which apps are capturing from a microphone right now (macOS 14.2+ process objects).
/// Reading "is running input" needs no microphone permission.
enum MicrophoneDetector {
    /// System services that hold the mic for calls on behalf of an app (FaceTime, Phone).
    private static let callServices: Set<String> = ["avconferenced", "callservicesd"]

    /// Apps using the microphone. Background system processes (Siri / "Hey Siri" listening,
    /// dictation, voice control) are ignored: only real apps, or call services, count as a call.
    static func appsUsingInput() -> [AppIdentity] {
        var result: [AppIdentity] = []
        for process in processObjects() where isRunningInput(process) {
            guard let pid = pid(of: process), pid != getpid(), let app = AppIdentity.resolve(pid: pid) else { continue }
            let isRegularApp = NSRunningApplication(processIdentifier: app.pid)?.activationPolicy == .regular
            if isRegularApp || callServices.contains(app.name) { result.append(app) }
        }
        return result
    }

    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func isRunningInput(_ object: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private static func pid(of object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
}

/// Whether any camera is streaming. Needs no camera permission.
enum CameraDetector {
    static func isAnyCameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == noErr else { return false }

        for device in devices {
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var value: UInt32 = 0
            var valueSize: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &valueSize, &value) == noErr,
               value != 0 {
                return true
            }
        }
        return false
    }
}

/// Apps holding a "keep the display awake" power assertion — what browsers and players do
/// while a video plays.
enum DisplayAssertionDetector {
    private static let types: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]
    /// Keep-awake utilities hold these assertions all day; they say nothing about video.
    private static let ignoredBundleIDs: Set<String> = [
        "com.if.Amphetamine", "com.lightheadsw.caffeine", "com.intelliscapesolutions.caffeine",
        "com.sindresorhus.KeepingYouAwake", "com.jalthakor.breather",
    ]
    private static let ignoredProcessNames: Set<String> = ["caffeinate", "powerd", "WindowServer", "coreaudiod"]

    static func appsHoldingDisplayAwake() -> [AppIdentity] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let dict = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }

        var apps: [AppIdentity] = []
        for (pidNumber, assertions) in dict {
            for assertion in assertions {
                guard let type = assertion["AssertType"] as? String, types.contains(type) else { continue }
                // WebKit and some players assert on behalf of the app that asked.
                let pid = (assertion["AssertionOnBehalfOfPID"] as? NSNumber)?.int32Value ?? pidNumber.int32Value
                guard pid != getpid(), let app = AppIdentity.resolve(pid: pid) else { continue }
                if ignoredBundleIDs.contains(app.bundleID) || ignoredProcessNames.contains(app.name) { continue }
                apps.append(app)
                break
            }
        }
        return apps
    }
}
