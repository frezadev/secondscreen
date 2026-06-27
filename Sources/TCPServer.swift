// TCPServer.swift
// Server TCP (Mac) yang mengirim NAL ke client (Android) dengan length-prefix:
//   [4 byte panjang big-endian][payload NAL Annex-B]
// Menyimpan SPS/PPS terakhir agar client yang baru connect bisa langsung decode.

import Foundation
import Network

@available(macOS 14.0, *)
final class TCPServer {

    private let listener: NWListener
    private let queue = DispatchQueue(label: "tcp.server")
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let connLock = NSLock()

    // Parameter set terakhir (SPS/PPS), dikirim ulang ke client baru.
    private var parameterSets: [Data] = []
    private let psLock = NSLock()

    // Dipanggil saat client baru connect (untuk memaksa keyframe).
    var onClientConnected: (() -> Void)?

    init(port: UInt16) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Matikan Nagle agar latensi rendah (penting untuk live screen).
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "TCPServer", code: 1)
        }
        self.listener = try NWListener(using: params, on: nwPort)
    }

    func start() {
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:   Log.info("TCP server siap, menunggu client…")
            case .failed(let e): Log.error("listener gagal: \(e)")
            default: break
            }
        }
        listener.start(queue: queue)
    }

    private func accept(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                Log.info("client connect: \(conn.endpoint)")
                self.connLock.lock(); self.connections[id] = conn; self.connLock.unlock()
                // Kirim SPS/PPS terakhir lebih dulu, lalu minta keyframe.
                self.sendParameterSetsTo(conn)
                self.onClientConnected?()
            case .failed(let e):
                Log.error("client error: \(e)")
                self.remove(id)
            case .cancelled:
                self.remove(id)
            default: break
            }
        }
        conn.start(queue: queue)
    }

    private func remove(_ id: ObjectIdentifier) {
        connLock.lock(); connections[id] = nil; connLock.unlock()
    }

    /// Catat parameter set (SPS/PPS) supaya bisa dikirim ke client baru.
    func registerParameterSet(_ nal: Data) {
        psLock.lock()
        // SPS=7, PPS=8 (5 bit terbawah byte setelah start code).
        // Simpan maksimal 2 (SPS+PPS); reset kalau SPS datang lagi.
        let nalType = nalUnitType(nal)
        if nalType == 7 { parameterSets = [] }     // SPS awal sekuens baru
        parameterSets.append(nal)
        if parameterSets.count > 2 { parameterSets.removeFirst(parameterSets.count - 2) }
        psLock.unlock()
    }

    private func sendParameterSetsTo(_ conn: NWConnection) {
        psLock.lock(); let sets = parameterSets; psLock.unlock()
        for nal in sets { sendFramed(nal, to: conn) }
    }

    private func nalUnitType(_ nal: Data) -> UInt8 {
        // Lewati start code (00 00 00 01) lalu ambil 5 bit terbawah.
        guard nal.count > 4 else { return 0 }
        return nal[4] & 0x1F
    }

    /// Kirim satu NAL ke semua client (dengan length-prefix).
    func broadcast(_ nal: Data) {
        connLock.lock(); let conns = Array(connections.values); connLock.unlock()
        for c in conns { sendFramed(nal, to: c) }
    }

    private func sendFramed(_ payload: Data, to conn: NWConnection) {
        var frame = Data(capacity: payload.count + 4)
        let len = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: len) { frame.append(contentsOf: $0) }
        frame.append(payload)
        conn.send(content: frame, completion: .contentProcessed { error in
            if let error = error { Log.error("send gagal: \(error)") }
        })
    }
}
