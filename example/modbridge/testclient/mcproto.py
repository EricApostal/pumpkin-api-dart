"""Tiny Minecraft Java protocol toolkit (stdlib only), targeting 26.3.

Contains the pieces every scripted client needs: FriendlyByteBuf style
encoding/decoding, the packet framing with optional zlib compression, and a
minimal reader for the NBT text components used by disconnect packets.

Encryption is NOT implemented (it would need AES/CFB8 + RSA, which the standard
library does not have). Use an offline-mode server with `encryption = false`.
"""

from __future__ import annotations

import socket
import struct
import time
import zlib
from typing import Optional

from mc_ids import PROTOCOL_VERSION  # noqa: F401  (re-exported)


class ProtocolError(Exception):
    """The peer sent something we cannot decode."""


class ConnectionClosed(Exception):
    """The peer closed the socket."""


# --------------------------------------------------------------------------- #
# FriendlyByteBuf
# --------------------------------------------------------------------------- #

def write_varint(value: int) -> bytes:
    value &= 0xFFFFFFFF
    out = bytearray()
    while True:
        if value & ~0x7F == 0:
            out.append(value)
            return bytes(out)
        out.append((value & 0x7F) | 0x80)
        value >>= 7


def write_string(text: str) -> bytes:
    data = text.encode("utf-8")
    return write_varint(len(data)) + data


def write_uuid(value) -> bytes:
    return value.bytes


class Buf:
    """Cursor over a bytes object, with the read methods of FriendlyByteBuf."""

    def __init__(self, data: bytes):
        self.data = data
        self.pos = 0

    def remaining(self) -> int:
        return len(self.data) - self.pos

    def read(self, n: int) -> bytes:
        if n < 0 or self.pos + n > len(self.data):
            raise ProtocolError(f"buffer underflow: need {n}, have {self.remaining()}")
        chunk = self.data[self.pos:self.pos + n]
        self.pos += n
        return chunk

    def rest(self) -> bytes:
        return self.read(self.remaining())

    def byte(self) -> int:
        return self.read(1)[0]

    def boolean(self) -> bool:
        return self.byte() != 0

    def varint(self) -> int:
        result = 0
        for shift in range(0, 35, 7):
            b = self.byte()
            result |= (b & 0x7F) << shift
            if not b & 0x80:
                break
        else:
            raise ProtocolError("varint too long")
        return result - (1 << 32) if result & 0x80000000 else result

    def i32(self) -> int:
        return struct.unpack(">i", self.read(4))[0]

    def i64(self) -> int:
        return struct.unpack(">q", self.read(8))[0]

    def f32(self) -> float:
        return struct.unpack(">f", self.read(4))[0]

    def string(self) -> str:
        n = self.varint()
        return self.read(n).decode("utf-8")

    def uuid(self):
        import uuid
        return uuid.UUID(bytes=self.read(16))


# --------------------------------------------------------------------------- #
# NBT text components (disconnect reasons in config/play)
# --------------------------------------------------------------------------- #

def _nbt_payload(buf: Buf, tag: int):
    if tag == 1:
        return struct.unpack(">b", buf.read(1))[0]
    if tag == 2:
        return struct.unpack(">h", buf.read(2))[0]
    if tag == 3:
        return struct.unpack(">i", buf.read(4))[0]
    if tag == 4:
        return struct.unpack(">q", buf.read(8))[0]
    if tag == 5:
        return struct.unpack(">f", buf.read(4))[0]
    if tag == 6:
        return struct.unpack(">d", buf.read(8))[0]
    if tag == 7:
        return buf.read(struct.unpack(">i", buf.read(4))[0])
    if tag == 8:
        return buf.read(struct.unpack(">H", buf.read(2))[0]).decode("utf-8", "replace")
    if tag == 9:
        inner = buf.byte()
        count = struct.unpack(">i", buf.read(4))[0]
        return [_nbt_payload(buf, inner) for _ in range(count)]
    if tag == 10:
        compound = {}
        while True:
            t = buf.byte()
            if t == 0:
                return compound
            name = buf.read(struct.unpack(">H", buf.read(2))[0]).decode("utf-8", "replace")
            compound[name] = _nbt_payload(buf, t)
    if tag == 11:
        return [struct.unpack(">i", buf.read(4))[0] for _ in range(struct.unpack(">i", buf.read(4))[0])]
    if tag == 12:
        return [struct.unpack(">q", buf.read(8))[0] for _ in range(struct.unpack(">i", buf.read(4))[0])]
    raise ProtocolError(f"unknown nbt tag {tag}")


def _component_text(node) -> str:
    """Flatten a text component (decoded NBT/JSON) to plain text."""
    if isinstance(node, str):
        return node
    if isinstance(node, list):
        return "".join(_component_text(n) for n in node)
    if isinstance(node, dict):
        text = node.get("text")
        if text is None and "translate" in node:
            text = node["translate"]
            if "with" in node:
                text += "(" + ", ".join(_component_text(w) for w in node["with"]) + ")"
        out = _component_text(text) if text is not None else ""
        for extra in node.get("extra", []):
            out += _component_text(extra)
        return out
    return str(node)


def decode_disconnect_reason(payload: bytes, nbt: bool = True) -> str:
    """Decode the reason of a disconnect packet to plain text.

    Handles all encodings seen in the wild: JSON text (login phase), a network
    NBT text component (vanilla config/play: a bare string tag or a compound),
    and a plain UTF string (what some servers send in the config phase).
    Pass nbt=False for the login phase, which is always a JSON string.
    """
    import json
    # network NBT: nameless root tag
    if nbt and payload and payload[0] in (8, 10):
        try:
            buf = Buf(payload)
            tag = buf.byte()
            value = _nbt_payload(buf, tag)
            if buf.remaining() == 0:
                return _component_text(value)
        except (ProtocolError, struct.error):
            pass
    try:
        text = Buf(payload).string()
    except (ProtocolError, UnicodeDecodeError):
        return payload.decode("utf-8", "replace")
    try:
        return _component_text(json.loads(text))
    except ValueError:
        return text


# --------------------------------------------------------------------------- #
# Framed connection
# --------------------------------------------------------------------------- #

class Connection:
    """Length-prefixed packet stream with optional zlib compression."""

    def __init__(self, host: str, port: int, timeout: float = 10.0):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.compression_threshold = -1  # -1 = disabled
        self._buffer = bytearray()

    def close(self) -> None:
        try:
            self.sock.close()
        except OSError:
            pass

    def send(self, packet_id: int, payload: bytes = b"") -> None:
        body = write_varint(packet_id) + payload
        if self.compression_threshold >= 0:
            if len(body) >= self.compression_threshold:
                body = write_varint(len(body)) + zlib.compress(body)
            else:
                body = write_varint(0) + body
        self.sock.sendall(write_varint(len(body)) + body)

    def _fill(self, deadline: Optional[float]) -> None:
        if deadline is not None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise socket.timeout("timed out")
            self.sock.settimeout(remaining)
        else:
            self.sock.settimeout(None)
        chunk = self.sock.recv(65536)
        if not chunk:
            raise ConnectionClosed("connection closed by server")
        self._buffer.extend(chunk)

    def _try_frame(self) -> Optional[bytes]:
        # parse the length varint without consuming
        length = 0
        for i in range(5):
            if i >= len(self._buffer):
                return None
            b = self._buffer[i]
            length |= (b & 0x7F) << (7 * i)
            if not b & 0x80:
                header = i + 1
                break
        else:
            raise ProtocolError("frame length varint too long")
        if len(self._buffer) < header + length:
            return None
        frame = bytes(self._buffer[header:header + length])
        del self._buffer[:header + length]
        return frame

    def recv(self, timeout: Optional[float] = 30.0) -> tuple[int, bytes]:
        """Receive one packet; returns (packet_id, payload). Raises socket.timeout."""
        deadline = None if timeout is None else time.monotonic() + timeout
        while True:
            frame = self._try_frame()
            if frame is not None:
                break
            self._fill(deadline)
        if self.compression_threshold >= 0:
            buf = Buf(frame)
            data_length = buf.varint()
            body = buf.rest()
            if data_length != 0:
                body = zlib.decompress(body)
                if len(body) != data_length:
                    raise ProtocolError("bad decompressed length")
        else:
            body = frame
        buf = Buf(body)
        packet_id = buf.varint()
        return packet_id, buf.rest()
