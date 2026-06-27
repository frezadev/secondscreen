// main.swift
// Entry point: virtual display -> capture -> encode H.264 -> kirim via TCP.
//
// Flag:
//   -v          log detail + FPS
//   --file      tulis juga ke out.h264 (untuk verifikasi)
//   --port N    port TCP (default 9000)

import Foundation
import CoreMedia

guard #available(macOS 14.0, *) else {
    Log.error("butuh macOS 14+")
    exit(1)
}

Log.verbose = CommandLine.arguments.contains("-v")
let alsoFile = CommandLine.arguments.contains("--file")

func argValue(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: name),
          i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}
let port = UInt16(argValue("--port") ?? "9000") ?? 9000

let manager = VirtualDisplayManager()

do {
    let id = try manager.create(name: "Android Tablet",
                                width: 1920, height: 1200,
                                refreshRate: 60, hiDPI: true)

    // Server TCP
    let server = try TCPServer(port: port)
    server.start()

    // Sink file opsional (verifikasi).
    let writeQueue = DispatchQueue(label: "file.write")
    var fileHandle: FileHandle?
    if alsoFile {
        let outURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("out.h264")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: outURL)
    }

    // Encoder: tiap NAL -> catat SPS/PPS, broadcast ke client, (opsional) tulis file.
    let encoder = H264Encoder(width: 1920, height: 1200) { nal in
        if nal.count > 4 {
            let t = nal[4] & 0x1F
            if t == 7 || t == 8 { server.registerParameterSet(nal) }
        }
        server.broadcast(nal)
        if let fh = fileHandle {
            writeQueue.async { fh.write(nal) }
        }
    }
    guard encoder.prepare() else { Log.error("encoder gagal"); exit(1) }

    // Client baru -> minta keyframe agar bisa langsung decode.
    server.onClientConnected = { [weak encoder] in
        encoder?.requestKeyframe()
    }

    var frameIndex: Int64 = 0
    let capturer = FrameCapturer(displayID: id) { pixelBuffer in
        let pts = CMTime(value: frameIndex, timescale: 60)
        frameIndex += 1
        encoder.encode(pixelBuffer, pts: pts)
    }

    Log.info("listening di port \(port). Seret window ke 'Android Tablet'. Ctrl+C berhenti.")

    Task {
        do { try await capturer.start(); Log.info("streaming…") }
        catch { Log.error("gagal start capture: \(error)"); exit(1) }
    }

    signal(SIGINT) { _ in Log.info("berhenti."); exit(0) }
    withExtendedLifetime((capturer, encoder, server)) {
        RunLoop.main.run()
    }

} catch {
    Log.error("\(error)")
    exit(1)
}
