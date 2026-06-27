# Protokol Wire — Second Screen

Transport: **TCP**, Mac = **server**, Android = **client**.
Default port: **9000**.

## Framing: length-prefix

Setiap pesan di wire:

```
+-------------------+--------------------------+
| length (4 byte)   | payload (length byte)    |
| big-endian uint32 | satu NAL unit Annex-B    |
+-------------------+--------------------------+
```

- `length` = jumlah byte payload (TIDAK termasuk 4 byte length itu sendiri).
- `payload` = satu NAL unit **lengkap dengan start code** `00 00 00 01` di depannya.

Artinya payload sudah berformat Annex-B; setelah melepas length-prefix,
byte payload bisa langsung di-feed ke MediaCodec (yang menerima Annex-B).

## Urutan saat client connect

1. Client membuka koneksi TCP ke `mac-ip:9000`.
2. Server segera mengirim **SPS** lalu **PPS** terakhir (masing-masing sebagai
   satu frame length-prefixed) — supaya decoder punya parameter sebelum frame.
3. Server memaksa **keyframe (IDR)** pada frame encode berikutnya, jadi client
   tidak perlu menunggu keyframe periodik.
4. Selanjutnya server mem-broadcast tiap NAL (SPS/PPS/IDR/slice) begitu tersedia.

## Tipe NAL (informasi)

Tipe NAL = 5 bit terbawah dari byte pertama setelah start code (`nal[4] & 0x1F`):

- `7` = SPS
- `8` = PPS
- `5` = IDR (keyframe)
- `1` = non-IDR slice (frame antar)

Client tidak wajib mem-parse tipe; cukup feed semua payload ke decoder
secara berurutan. Tipe berguna untuk logging/diagnostik.

## Sisi Android (ringkas, untuk M4)

Loop baca:

```
while (connected) {
    int len = readBigEndianUInt32();      // baca 4 byte
    byte[] nal = readExactly(len);        // baca tepat len byte
    feedToMediaCodec(nal);                // input buffer Annex-B
}
```

`readExactly` harus mengulang `InputStream.read` sampai cukup `len` byte
(TCP bisa memberi sebagian). MediaCodec dikonfigurasi:
`MediaFormat.createVideoFormat("video/avc", 1920, 1200)` dan di-render ke
`Surface` dari `SurfaceView`/`TextureView`.

## Catatan latensi

- Server mematikan Nagle (`TCP_NODELAY`) untuk mengurangi penundaan.
- Belum ada handling re-sync/packet loss (TCP menjamin urutan & keutuhan,
  jadi tidak perlu; tapi kalau pindah ke UDP/WebRTC nanti, perlu).
