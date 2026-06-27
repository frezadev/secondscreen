# Second Screen (macOS → Android) — PoC

Menjadikan tablet Android sebagai monitor kedua macOS, mirip Sidecar.
Tahap saat ini: sisi **Mac** (virtual display → capture → encode H.264).

## Status milestone

- [x] **M1** — Virtual display muncul di System Settings (`CGVirtualDisplay`, private API)
- [x] **M2** — Capture isi display via ScreenCaptureKit
- [x] **M3.1** — Continuous capture loop, 1920×1200, ~58 fps saat aktif
- [x] **M3.2** — Encode H.264 (Annex-B, SPS/PPS benar)
- [x] **M3.3** — Kirim stream via TCP (length-prefix, Mac=server, port 9000)
- [ ] **M4** — Sisi Android: decode (MediaCodec) + render
- [ ] **M5** — Input balik: touch + stylus → `CGEvent`

## Build & run

```bash
./build.sh
./vdpoc          # normal
./vdpoc -v       # log detail + FPS
```

Saat jalan: seret sebuah window ke display "Android Tablet", gerakkan
sedikit (SCK hanya mengirim frame saat ada perubahan piksel). Ctrl+C berhenti.


## Streaming (M3.3)

```bash
./build.sh
./vdpoc                 # server di port 9000
./vdpoc --port 9000 -v  # dengan log
./vdpoc --file          # sekaligus tulis out.h264 untuk verifikasi
```

Protokol wire ada di `PROTOCOL.md` (length-prefix + Annex-B). Android sebagai
client connect ke `mac-ip:9000`.

## Verifikasi output

```bash
ffprobe out.h264
ffmpeg -framerate 60 -i out.h264 -c copy out.mp4
ffplay out.mp4
```

`ffprobe` harus melaporkan `1920x1200`.

## Struktur

```
Sources/
  CGVirtualDisplay.h         private API bridging
  Log.swift                  logger ringan (verbose via -v)
  VirtualDisplayManager.swift  buat/hapus virtual display
  FrameCapturer.swift        ScreenCaptureKit -> CVPixelBuffer
  H264Encoder.swift          VideoToolbox -> H.264 Annex-B
  main.swift                 entry point
build.sh
```

## Catatan penting

- **Private API**: `CGVirtualDisplay` tak terdokumentasi; bisa berubah antar
  versi macOS. Tidak bisa masuk Mac App Store; distribusi via direct download +
  notarization. Refresh rate virtual display terbatas 60 Hz.
- **Permission**: butuh Screen Recording untuk terminal/app yang menjalankan.
  Setelah memberi izin, restart terminal.
- **Resolusi**: `scDisplay.width/height` itu *points*; dikali `scale` (2) untuk
  mendapat *pixels* penuh.
- **Bug yang sudah diperbaiki**: `CFEqual(fmt, nil)` memicu trace trap pada frame
  pertama — selalu cek `lastFormatDesc == nil` sebelum `CFEqual`.
