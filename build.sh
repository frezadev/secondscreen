#!/bin/bash
# build.sh — kompilasi PoC second screen
set -e

cd "$(dirname "$0")/Sources"

swiftc -O \
  -import-objc-header CGVirtualDisplay.h \
  Log.swift \
  VirtualDisplayManager.swift \
  FrameCapturer.swift \
  H264Encoder.swift \
  TCPServer.swift \
  main.swift \
  -framework CoreGraphics -framework Foundation \
  -framework ScreenCaptureKit -framework CoreVideo -framework CoreMedia \
  -framework VideoToolbox -framework Network \
  -o ../vdpoc

echo "OK -> ./vdpoc"
echo "Jalankan: ./vdpoc       (normal)"
echo "          ./vdpoc -v    (dengan log detail/FPS)"
