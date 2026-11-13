#!/bin/bash
# Compile without installing or launching the app, then exercise bounded logging.
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n install-singbox-bar.sh
bash -n uninstall.sh
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
python3 - "$WORK/main.swift" <<'PY'
import pathlib, sys
source = pathlib.Path('install-singbox-bar.sh').read_text()
swift = source.split("<<'SWIFT'\n", 1)[1].split('\nSWIFT\n', 1)[0]
pathlib.Path(sys.argv[1]).write_text(swift.replace('__VERSION__', '0.0.0-test'))
PY
xcrun swiftc -O "$WORK/main.swift" Sources/LogStore.swift Sources/Diagnostics.swift Sources/TextWindow.swift -o "$WORK/SingBoxBar"
xcrun swiftc Sources/LogStore.swift Tests/LogStoreTests.swift -o "$WORK/log-tests"
"$WORK/log-tests"
xcrun swiftc Sources/LogStore.swift Sources/LogCapture.swift -o "$WORK/SingBoxBarLogger"
python3 Tests/test_capture.py "$WORK/SingBoxBarLogger"
