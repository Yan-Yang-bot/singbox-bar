"""Exercise the actual logger process, not a reimplementation of the buffer."""
from pathlib import Path
import subprocess
import sys
import tempfile
import time

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    fake = root / "sing-box"
    # Use the test runner's interpreter explicitly (no dependency on PATH).
    fake.write_text(f"#!{sys.executable}\n" + '''import os, time
for n in range(700):
    os.write(1 if n % 2 else 2, f"line {n}\\n".encode())
    time.sleep(0.001)
raw = "ERROR 中文\\n".encode()
for byte in raw:
    os.write(1, bytes([byte]))
    time.sleep(0.01)
os.write(1, b"last partial")
''')
    fake.chmod(0o755)
    log = root / "logs" / "capture.log"
    process = subprocess.Popen([sys.argv[1], str(fake), str(root / "config.json"), str(log)])
    observed_live = False
    deadline = time.monotonic() + 20
    while process.poll() is None:
        assert time.monotonic() < deadline, "logger did not exit on child EOF"
        if log.exists():
            text = log.read_text()
            assert len(text.splitlines()) <= 500, "live log exceeded 500 lines"
            observed_live |= bool(text)
        time.sleep(0.01)
    assert process.returncode == 0
    expected = "".join(f"line {n}\n" for n in range(202, 700)) + "ERROR 中文\nlast partial"
    assert log.read_text() == expected, repr(log.read_text()[-100:])
    assert observed_live, "logs were only written after child exit"
    # Startup failure must leave a useful error and a nonzero exit status.
    failed = subprocess.run([sys.argv[1], str(root / "missing"), str(root / "config.json"), str(log)])
    assert failed.returncode != 0
    assert "ERROR: Log capture failed:" in log.read_text()
    assert len(log.read_text().splitlines()) <= 500
print("Logger integration tests passed")
