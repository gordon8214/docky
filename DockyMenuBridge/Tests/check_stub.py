"""Check that the remote loader matches its arm64e assembly source."""
import re
import struct
import sys
from pathlib import Path

binary = Path(sys.argv[1]).read_bytes()
source = Path(sys.argv[2]).read_text()
offset = 32
text = None
for _ in range(struct.unpack_from("<I", binary, 16)[0]):
    command, size = struct.unpack_from("<II", binary, offset)
    if command == 0x19:  # LC_SEGMENT_64
        for index in range(struct.unpack_from("<I", binary, offset + 64)[0]):
            section = offset + 72 + index * 80
            if binary[section:section + 16].rstrip(b"\0") == b"__text":
                length, start = struct.unpack_from("<QI", binary, section + 40)
                text = binary[start:start + length]
    offset += size
match = re.search(r"const unsigned char child\[\] = \{([^}]+)\}", source)
assert match is not None and text is not None
child = bytes(map(int, match.group(1).split(",")))
assert len(child) == 120 and text[:120] == child, "Recompile the loader's child stub"
assert text[120:144] == bytes(24) and len(text) == 144 + 4096
for location, symbol in [
    (216, "dlopen_address"), (224, "dlerror_address"), (232, "result_address")
]:
    assert f"memcpy(shell_code + {location}, &{symbol}, 8)" in source
assert "memcpy(shell_code + 240, payload_path" in source
print("Remote loader assembly and pointer offsets match")
