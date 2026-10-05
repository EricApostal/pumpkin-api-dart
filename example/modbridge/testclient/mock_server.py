#!/usr/bin/env python3
"""A minimal fake server that speaks the SERVER side of modbridge.

It exists to test modbridge_client.py without a real Pumpkin plugin, and doubles
as a byte-level reference for what the plugin must send / expect:

  login      -> set_compression(256), login_finished
  config     -> modbridge:hello, wait for modbridge:hello_ack, finish_configuration
  play       -> login (dummy), then answer modbridge:ping with modbridge:pong,
                and send one modbridge:toast.

Not a real server: the play `login` packet has a dummy body.
"""

from __future__ import annotations

import argparse
import socket
import struct
import threading
import time

from mcproto import Buf, Connection, ConnectionClosed, write_string, write_varint

NBT_STRING = 8


def nbt_text(text: str) -> bytes:
    """Network NBT string tag, i.e. a plain text component (config/play disconnect)."""
    data = text.encode()
    return bytes([NBT_STRING]) + struct.pack(">H", len(data)) + data


class _ServerConn(Connection):
    def __init__(self, sock: socket.socket):  # noqa: super().__init__ opens a socket itself
        self.sock = sock
        self.compression_threshold = -1
        self._buffer = bytearray()


def serve_one(sock: socket.socket, mode: str, hello_timeout: float = 3.0, announce: bool = False) -> list:
    """Handle one client; returns a list of observations for the test."""
    seen: list = []
    c = _ServerConn(sock)
    try:
        pid, data = c.recv(5)                       # handshake
        pid, data = c.recv(5)                       # login start
        c.send(3, write_varint(256))                # set compression
        c.compression_threshold = 256
        c.send(2, b"\x11" * 16 + write_string("Bot") + write_varint(0) + b"\x22" * 16)
        pid, data = c.recv(5)                       # login acknowledged
        assert pid == 3
        c.send(1, write_string("minecraft:brand") + write_string("MockPumpkin"))
        if announce:   # what a NeoForge/Fabric client needs before it may send our channels
            c.send(1, write_string("minecraft:register") + b"modbridge:hello_ack\0")
        # modbridge:hello
        if mode != "no-hello":
            c.send(1, write_string("modbridge:hello") + write_varint(1) + write_string("mock-server"))
        deadline = time.monotonic() + hello_timeout
        acked = mode == "no-hello"
        finish_sent = False
        while not finish_sent:
            try:
                pid, data = c.recv(max(0.05, deadline - time.monotonic()))
            except socket.timeout:
                if mode == "timeout-kick":
                    c.send(2, nbt_text("modbridge: no hello_ack received in time"))
                    seen.append("timeout-kick")
                    return seen
                if mode == "vanilla-ok":
                    acked = True
                else:
                    raise
            else:
                buf = Buf(data)
                if pid == 2:                        # custom payload
                    channel = buf.string()
                    seen.append(channel)
                    if channel == "modbridge:hello_ack":
                        version, mod = buf.varint(), buf.string()
                        seen.append(("ack", version, mod))
                        if version != 1:
                            c.send(2, nbt_text(f"modbridge: unsupported protocol {version}"))
                            return seen
                        acked = True
                elif pid == 0:
                    seen.append("client_information")
                elif pid == 7:
                    seen.append("known_packs")
            if acked:
                c.send(3)                           # finish configuration
                finish_sent = True
        pid, data = c.recv(5)                       # finish ack
        assert pid == 3
        c.send(50, b"\x00" * 8)                     # play login (dummy)
        if announce:
            c.send(24, write_string("minecraft:register") + b"modbridge:ping\0")
        if mode != "no-toast":
            c.send(24, write_string("modbridge:toast") + write_string("Welcome") + write_string("hi there"))
        while True:
            pid, data = c.recv(5)
            if pid == 22:
                buf = Buf(data)
                channel = buf.string()
                if channel == "modbridge:ping":
                    nonce = buf.i64()
                    seen.append(("ping", nonce))
                    if mode != "no-pong":
                        c.send(24, write_string("modbridge:pong") + struct.pack(">qq", nonce, 4242))
    except (ConnectionClosed, socket.timeout, OSError):
        return seen
    finally:
        sock.close()


class MockServer:
    def __init__(self, mode: str = "ok", port: int = 0, hello_timeout: float = 3.0, announce: bool = False):
        self.listener = socket.socket()
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.listener.bind(("127.0.0.1", port))
        self.listener.listen(1)
        self.port = self.listener.getsockname()[1]
        self.mode, self.hello_timeout, self.announce = mode, hello_timeout, announce
        self.seen: list = []
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self):
        try:
            client, _ = self.listener.accept()
        except OSError:
            return
        self.seen = serve_one(client, self.mode, self.hello_timeout, self.announce)

    def close(self):
        self.listener.close()
        self.thread.join(5)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=35966)
    ap.add_argument("--mode", default="ok")
    ap.add_argument("--announce", action="store_true", help="send minecraft:register like a plugin must for mod clients")
    args = ap.parse_args()
    server = MockServer(args.mode, args.port, announce=args.announce)
    print(f"mock modbridge server on 127.0.0.1:{server.port} (mode {args.mode})")
    server.thread.join()
    print(server.seen)
