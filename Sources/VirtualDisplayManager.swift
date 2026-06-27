// VirtualDisplayManager.swift
// Membuat & mengelola satu virtual display lewat private API CGVirtualDisplay.

import Foundation
import CoreGraphics

final class VirtualDisplayManager {

    struct Config {
        var enabled = true
        // Kill switch berbasis versi; private API bisa pecah antar build.
        var denylist: Set<String> = []
    }

    enum VDError: Error {
        case disabledByConfig
        case unsupportedOS(String)
        case applyFailed
    }

    private var display: CGVirtualDisplay?
    private let config: Config

    init(config: Config = Config()) {
        self.config = config
    }

    var currentDisplayID: CGDirectDisplayID? { display?.displayID }

    private func osVersionString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }

    private func gateCheck() throws {
        guard config.enabled else { throw VDError.disabledByConfig }
        let ver = osVersionString()
        if config.denylist.contains(ver) {
            throw VDError.unsupportedOS(ver)
        }
    }

    @discardableResult
    func create(name: String = "Android Tablet",
                width: UInt32 = 1920,
                height: UInt32 = 1200,
                refreshRate: Double = 60,
                hiDPI: Bool = true) throws -> CGDirectDisplayID {

        try gateCheck()

        let desc = CGVirtualDisplayDescriptor()
        desc.queue = DispatchQueue.main
        desc.name = name
        desc.maxPixelsWide = width
        desc.maxPixelsHigh = height
        desc.sizeInMillimeters = CGSize(width: 230, height: 144)
        desc.serialNum = 0x0001
        desc.productID = 0x1234
        desc.vendorID  = 0x3456
        desc.terminationHandler = { _, _ in
            Log.info("virtual display dihentikan oleh sistem")
        }

        let vd = CGVirtualDisplay(descriptor: desc)

        let mode = CGVirtualDisplayMode(
            width: width, height: height, refreshRate: refreshRate)
        let settings = CGVirtualDisplaySettings()
        settings.modes = [mode]
        settings.hiDPI = hiDPI ? 1 : 0

        guard vd.apply(settings) else { throw VDError.applyFailed }

        self.display = vd
        Log.info("virtual display dibuat id=\(vd.displayID) \(width)x\(height)")
        return vd.displayID
    }

    func destroy() {
        display = nil
    }
}
