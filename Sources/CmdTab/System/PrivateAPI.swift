import ApplicationServices
import CoreGraphics
import Darwin

/// Private WindowServer (SkyLight) and HIServices APIs that window switchers and managers rely on.
/// Public APIs cannot tell which Space a window is on,
/// map an accessibility element to its window ID, or focus one specific window of an app.
///
/// Symbols are resolved lazily with `dlsym`, so if a future macOS removes one of them the
/// related feature degrades gracefully instead of the app failing to launch.
enum PrivateAPI {
    typealias SpaceID = UInt64

    /// Identifiers of the system "symbolic hot keys" that drive the native app switcher.
    enum SymbolicHotKey: Int32, CaseIterable {
        case commandTab = 1
        case commandShiftTab = 2
    }

    // MARK: - Spaces

    /// The Space currently shown on each display (one per display, unless displays share Spaces).
    static func currentSpaceIDs() -> Set<SpaceID> {
        guard let copy = symbols.copyManagedDisplaySpaces,
              let displays = copy(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return [] }

        let ids = displays.compactMap { display -> SpaceID? in
            guard let space = display["Current Space"] as? [String: Any] else { return nil }
            let number = (space["id64"] ?? space["ManagedSpaceID"]) as? NSNumber
            return number?.uint64Value
        }
        return Set(ids)
    }

    /// Each display's current Space and full-screen app Spaces, from Mission Control's layout.
    static func displaySpaces() -> [DisplaySpaces] {
        guard let copy = symbols.copyManagedDisplaySpaces,
              let displays = copy(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return [] }

        func id(_ space: [String: Any]) -> SpaceID? {
            ((space["id64"] ?? space["ManagedSpaceID"]) as? NSNumber)?.uint64Value
        }
        func isFullScreen(_ space: [String: Any]) -> Bool { (space["type"] as? Int ?? 0) != 0 }

        return displays.compactMap { display in
            guard let current = display["Current Space"] as? [String: Any], let currentID = id(current) else { return nil }
            let spaces = display["Spaces"] as? [[String: Any]] ?? []
            return DisplaySpaces(
                displayID: display["Display Identifier"] as? String ?? "",
                current: currentID,
                currentIsFullScreen: isFullScreen(current),
                fullScreen: spaces.filter(isFullScreen).compactMap(id)
            )
        }
    }

    /// The number macOS shows for each desktop in Mission Control ("Desktop 2"), per display.
    /// Full-screen app Spaces are skipped.
    static func desktopNumbers() -> [SpaceID: Int] {
        guard let copy = symbols.copyManagedDisplaySpaces,
              let displays = copy(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return [:] }

        let spacesPerDisplay = displays.map { display in
            (display["Spaces"] as? [[String: Any]] ?? []).compactMap { space -> DesktopNumbering.Space? in
                guard let id = ((space["id64"] ?? space["ManagedSpaceID"]) as? NSNumber)?.uint64Value else { return nil }
                return DesktopNumbering.Space(id: id, isFullScreen: (space["type"] as? Int ?? 0) != 0)
            }
        }
        return DesktopNumbering.numbers(spacesPerDisplay: spacesPerDisplay)
    }

    /// Every Space the window belongs to. Empty for windows that are on no Space (helper/offscreen windows).
    static func spaceIDs(forWindow windowID: CGWindowID) -> Set<SpaceID> {
        guard let copy = symbols.copySpacesForWindows,
              let spaces = copy(connection, allSpacesMask, [NSNumber(value: windowID)] as CFArray)?
                .takeRetainedValue() as? [NSNumber]
        else { return [] }
        return Set(spaces.map(\.uint64Value))
    }

    // MARK: - Native switcher

    /// Enables or disables a system shortcut. This state is **global and outlives the process**,
    /// so whoever disables it must restore it on exit.
    @discardableResult
    static func setSymbolicHotKey(_ hotKey: SymbolicHotKey, enabled: Bool) -> Bool {
        guard let set = symbols.setSymbolicHotKeyEnabled else { return false }
        return set(hotKey.rawValue, enabled) == .success
    }

    // MARK: - Windows

    /// The WindowServer ID of the window behind an accessibility element.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let getWindow = symbols.axGetWindow else { return nil }
        var windowID: CGWindowID = 0
        guard getWindow(element, &windowID) == .success, windowID != 0 else { return nil }
        return windowID
    }

    /// Window elements among the app's Accessibility element ids in `range`, including windows on
    /// other Spaces, which `kAXWindowsAttribute` leaves out. An element is addressed by a token of the
    /// app's pid and an element id; each lookup takes about 12 µs. Stops early once every window in
    /// `wanted` is found. Returns what it found and where it stopped.
    static func windowElements(
        pid: pid_t,
        in range: Range<UInt64>,
        wanted: Set<CGWindowID>
    ) -> (elements: [CGWindowID: AXUIElement], scannedTo: UInt64) {
        guard let create = symbols.axCreateWithRemoteToken else { return ([:], range.upperBound) }
        var found: [CGWindowID: AXUIElement] = [:]
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { bytes in
            bytes.storeBytes(of: pid, toByteOffset: 0, as: Int32.self)
            bytes.storeBytes(of: 0x636f636f, toByteOffset: 8, as: Int32.self) // "coco"
        }
        var elementID = range.lowerBound
        while elementID < range.upperBound {
            defer { elementID += 1 }
            token.withUnsafeMutableBytes { $0.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self) }
            // Every element inside a window reports that window, so keep only the window itself.
            guard let element = create(token as CFData)?.takeRetainedValue(),
                  let windowID = windowID(of: element), found[windowID] == nil,
                  element.value(of: kAXRoleAttribute) as String? == kAXWindowRole
            else { continue }
            found[windowID] = element
            if !wanted.isEmpty, wanted.isSubset(of: found.keys) {
                return (found, elementID + 1)
            }
        }
        return (found, range.upperBound)
    }

    /// Makes `windowID` the frontmost, key window of process `pid`, switching Space if needed.
    /// `NSRunningApplication.activate` can only target an app, not one of its windows.
    @discardableResult
    static func focusWindow(_ windowID: CGWindowID, pid: pid_t) -> Bool {
        guard let getProcess = symbols.getProcessForPID,
              let setFront = symbols.setFrontProcess,
              let postEvent = symbols.postEventRecord
        else { return false }

        var psn = ProcessSerialNumber()
        guard getProcess(pid, &psn) == noErr,
              setFront(&psn, windowID, userGeneratedFlag) == .success
        else { return false }

        // Synthesised "make key window" event records, the layout used by open-source window managers.
        var record = [UInt8](repeating: 0, count: 0xF8)
        record[0x04] = 0xF8
        record[0x3A] = 0x10
        withUnsafeBytes(of: windowID.littleEndian) { record.replaceSubrange(0x3C..<0x40, with: $0) }
        for offset in 0x20..<0x30 { record[offset] = 0xFF }
        record[0x08] = 0x01
        _ = postEvent(&psn, &record)
        record[0x08] = 0x02
        _ = postEvent(&psn, &record)
        return true
    }

    // MARK: - Symbol resolution

    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SetSymbolicHotKeyEnabledFn = @convention(c) (Int32, Bool) -> CGError
    private typealias AXCreateWithRemoteTokenFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFrontProcessFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecordFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

    private struct Symbols: @unchecked Sendable {
        let mainConnectionID: MainConnectionIDFn?
        let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn?
        let copySpacesForWindows: CopySpacesForWindowsFn?
        let setSymbolicHotKeyEnabled: SetSymbolicHotKeyEnabledFn?
        let axGetWindow: AXGetWindowFn?
        let axCreateWithRemoteToken: AXCreateWithRemoteTokenFn?
        let getProcessForPID: GetProcessForPIDFn?
        let setFrontProcess: SetFrontProcessFn?
        let postEventRecord: PostEventRecordFn?
    }

    private static let symbols: Symbols = {
        let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        let appServices = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)

        func resolve<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as _: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }

        return Symbols(
            mainConnectionID: resolve(skyLight, "CGSMainConnectionID", as: MainConnectionIDFn.self),
            copyManagedDisplaySpaces: resolve(skyLight, "CGSCopyManagedDisplaySpaces", as: CopyManagedDisplaySpacesFn.self),
            copySpacesForWindows: resolve(skyLight, "CGSCopySpacesForWindows", as: CopySpacesForWindowsFn.self),
            setSymbolicHotKeyEnabled: resolve(skyLight, "CGSSetSymbolicHotKeyEnabled", as: SetSymbolicHotKeyEnabledFn.self),
            axGetWindow: resolve(appServices, "_AXUIElementGetWindow", as: AXGetWindowFn.self),
            axCreateWithRemoteToken: resolve(appServices, "_AXUIElementCreateWithRemoteToken", as: AXCreateWithRemoteTokenFn.self),
            getProcessForPID: resolve(appServices, "GetProcessForPID", as: GetProcessForPIDFn.self),
            setFrontProcess: resolve(skyLight, "_SLPSSetFrontProcessWithOptions", as: SetFrontProcessFn.self),
            postEventRecord: resolve(skyLight, "SLPSPostEventRecordTo", as: PostEventRecordFn.self)
        )
    }()

    private static let connection: Int32 = symbols.mainConnectionID?() ?? 0
    private static let allSpacesMask: Int32 = 0x7
    private static let userGeneratedFlag: UInt32 = 0x200
}

/// Pure numbering rule, kept apart from the private call so it can be tested.
enum DesktopNumbering {
    struct Space: Equatable {
        let id: PrivateAPI.SpaceID
        let isFullScreen: Bool
    }

    /// Desktops are numbered from 1 on each display, in Mission Control order, skipping full-screen Spaces.
    static func numbers(spacesPerDisplay: [[Space]]) -> [PrivateAPI.SpaceID: Int] {
        var numbers: [PrivateAPI.SpaceID: Int] = [:]
        for spaces in spacesPerDisplay {
            for (index, space) in spaces.filter({ !$0.isFullScreen }).enumerated() {
                numbers[space.id] = index + 1
            }
        }
        return numbers
    }
}
