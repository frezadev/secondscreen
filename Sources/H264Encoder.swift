// H264Encoder.swift
// Encode CVPixelBuffer -> H.264 Annex-B (NAL dipisah start code 00 00 00 01).
// SPS/PPS di-emit setiap format description berubah (termasuk frame pertama).

import Foundation
import VideoToolbox
import CoreVideo
import CoreMedia

@available(macOS 14.0, *)
final class H264Encoder {

    private var session: VTCompressionSession?
    private let width: Int32
    private let height: Int32
    private let onData: (Data) -> Void

    private var lastFormatDesc: CMFormatDescription?
    private let startCode = Data([0x00, 0x00, 0x00, 0x01])

    init(width: Int32, height: Int32, onData: @escaping (Data) -> Void) {
        self.width = width
        self.height = height
        self.onData = onData
    }

    func prepare() -> Bool {
        let props: [CFString: Any] = [
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_AutoLevel,
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            kVTCompressionPropertyKey_MaxKeyFrameInterval: 60,
            kVTCompressionPropertyKey_AverageBitRate: 8_000_000,
        ]
        let imgAttrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ]

        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width, height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: imgAttrs as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session)

        guard status == noErr, let session = session else {
            Log.error("VTCompressionSessionCreate gagal: \(status)")
            return false
        }

        for (k, v) in props {
            VTSessionSetProperty(session, key: k, value: v as CFTypeRef)
        }
        VTCompressionSessionPrepareToEncodeFrames(session)
        return true
    }

    // Diset true dari luar (thread-safe) saat client baru connect.
    private var forceKeyframeNext = false
    private let kfLock = NSLock()

    func requestKeyframe() {
        kfLock.lock(); forceKeyframeNext = true; kfLock.unlock()
    }

    func encode(_ pixelBuffer: CVPixelBuffer, pts: CMTime) {
        guard let session = session else { return }

        kfLock.lock()
        let force = forceKeyframeNext
        forceKeyframeNext = false
        kfLock.unlock()

        var frameProps: CFDictionary?
        if force {
            frameProps = [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
        }

        VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer,
            presentationTimeStamp: pts, duration: .invalid,
            frameProperties: frameProps, infoFlagsOut: nil) { [weak self] status, _, sb in
                guard status == noErr, let sb = sb, let self = self else { return }
                self.handleEncoded(sb)
            }
    }

    private func handleEncoded(_ sb: CMSampleBuffer) {
        if let fmt = CMSampleBufferGetFormatDescription(sb) {
            // Cek nil DULU sebelum CFEqual (CFEqual trap kalau argumen nil)
            let isNew = (lastFormatDesc == nil) || !CFEqual(fmt, lastFormatDesc!)
            if isNew {
                lastFormatDesc = fmt
                emitParameterSets(fmt)
            }
        }

        guard let dataBuffer = CMSampleBufferGetDataBuffer(sb) else { return }
        let totalLen = CMBlockBufferGetDataLength(dataBuffer)
        guard totalLen > 4 else { return }

        var bytes = [UInt8](repeating: 0, count: totalLen)
        let st = CMBlockBufferCopyDataBytes(
            dataBuffer, atOffset: 0, dataLength: totalLen, destination: &bytes)
        guard st == kCMBlockBufferNoErr else {
            Log.error("CMBlockBufferCopyDataBytes gagal \(st)")
            return
        }

        // AVCC (panjang 4-byte big-endian) -> Annex-B
        var offset = 0
        while offset + 4 <= totalLen {
            let nalLength =
                (Int(bytes[offset])     << 24) |
                (Int(bytes[offset + 1]) << 16) |
                (Int(bytes[offset + 2]) << 8)  |
                 Int(bytes[offset + 3])
            guard nalLength > 0, offset + 4 + nalLength <= totalLen else { break }

            var nal = startCode
            nal.append(contentsOf: bytes[(offset + 4)..<(offset + 4 + nalLength)])
            onData(nal)
            offset += 4 + nalLength
        }
    }

    private func emitParameterSets(_ fmt: CMFormatDescription) {
        var index = 0
        while true {
            var psPtr: UnsafePointer<UInt8>?
            var psSize = 0
            var count = 0
            let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                fmt, parameterSetIndex: index,
                parameterSetPointerOut: &psPtr,
                parameterSetSizeOut: &psSize,
                parameterSetCountOut: &count,
                nalUnitHeaderLengthOut: nil)

            guard status == noErr, let psPtr = psPtr, psSize > 0 else { break }

            var nal = startCode
            nal.append(Data(bytes: psPtr, count: psSize))
            onData(nal)
            Log.debug("emit param set \(index): \(psSize) bytes")

            index += 1
            if index >= count { break }
        }
    }
}
