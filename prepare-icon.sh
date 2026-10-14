#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin
cd "$(dirname "$0")"
INPUT="${1:?Pass the generated icon PNG path}"
mkdir -p Resources Sources/WordShelf/Assets
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
# Export standard macOS icon sizes while preserving the generated alpha channel.
sips -s format png -z 1024 1024 "$INPUT" --out Resources/AppIcon.png >/dev/null
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/python3 - "$ICONSET" Resources/AppIcon.icns <<'PYICON'
import struct, sys
from pathlib import Path
source = Path(sys.argv[1])
entries = [
 (b'icp4', 'icon_16x16.png'), (b'icp5', 'icon_32x32.png'),
 (b'icp6', 'icon_32x32@2x.png'), (b'ic07', 'icon_128x128.png'),
 (b'ic08', 'icon_256x256.png'), (b'ic09', 'icon_512x512.png'),
 (b'ic10', 'icon_512x512@2x.png'), (b'ic11', 'icon_16x16@2x.png'),
 (b'ic13', 'icon_128x128@2x.png'), (b'ic14', 'icon_256x256@2x.png')
]
body = b''.join(tag + struct.pack('>I', len(data) + 8) + data
               for tag, filename in entries for data in [(source / filename).read_bytes()])
Path(sys.argv[2]).write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
PYICON
cp Resources/AppIcon.icns Sources/WordShelf/Assets/AppIcon.icns
