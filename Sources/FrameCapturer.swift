// FrameCapturer.swift
// Menangkap isi sebuah display via ScreenCaptureKit, mengalirkan CVPixelBuffer.

import Foundation
import ScreenCaptureKit
import CoreVideo

@available(macOS 14.0, *)
final class FrameCapturer: NSObject, SCStreamOutput, SCStreamDelegate {

    private var stream: SCStream?
    private let targetDisplayID: CGDirectDisplayID
    private let scale: Int
    private let onFrame: ((CVPixelBuffer) -> Void)?

    // Pengukuran FPS opsional (hanya saat verbose)
    private var frameCount = 0
    private var lastReport = Date()

    init(displayID: CGDirectDisplayID,
         scale: Int = 2,
         onFrame: ((CVPixelBuffer) -> Void)? = nil) {
        self.targetDisplayID = displayID
        self.scale = scale
        self.onFrame = onFrame
        super.init()
    }

    func start() async throws {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false)

        guard let scDisplay = content.displays.first(
            where: { $0.displayID == targetDisplayID }) else {
            throw NSError(domain: "FrameCapturer", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "display \(targetDisplayID) tidak ditemukan di shareable content"])
        }

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])

        let cfg = SCStreamConfiguration()
        cfg.width  = scDisplay.width  * scale   // points -> pixels
        cfg.height = scDisplay.height * scale
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = true
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        cfg.queueDepth = 5

        Log.info("capture config \(cfg.width)x\(cfg.height) px")

        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen,
                              sampleHandlerQueue: DispatchQueue(label: "capture.q"))
        try await s.startCapture()
        self.stream = s
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    // MARK: SCStreamDelegate
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.error("stream berhenti: \(error)")
    }

    // MARK: SCStreamOutput
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen else { return }

        let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        let statusRaw = attachments?.first?[.status] as? Int
        let status = statusRaw.flatMap { SCFrameStatus(rawValue: $0) }

        guard status == .complete || status == .idle else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if Log.verbose {
            frameCount += 1
            let elapsed = Date().timeIntervalSince(lastReport)
            if elapsed >= 1.0 {
                Log.debug(String(format: "FPS %.1f", Double(frameCount) / elapsed))
                frameCount = 0
                lastReport = Date()
            }
        }

        onFrame?(pixelBuffer)
    }
}
