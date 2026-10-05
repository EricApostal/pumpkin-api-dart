#!/usr/bin/env python3
"""Scripted headless Minecraft 26.3 client for the `modbridge` example.

It speaks just enough of the Java protocol (handshake, login, configuration,
play) to join an OFFLINE-mode server without encryption, and takes part in the
modbridge protocol:

  config  S2C modbridge:hello      [varint protocolVersion][string serverName]
  config  C2S modbridge:hello_ack  [varint protocolVersion][string modVersion]
  play    C2S modbridge:ping       [long nonce]
  play    S2C modbridge:pong       [long nonce][long serverTick]
  play    S2C modbridge:toast      [string title][string message]

Library use:

    from modbridge_client import ModbridgeClient, Options
    result = ModbridgeClient(Options(host="127.0.0.1", port=25565)).run()
    assert result.ok, result.message

CLI: see `modbridge_client.py --help`.  Exit status: 0 success, 1 failure.
"""

from __future__ import annotations

import argparse
import hashlib
import random
import socket
import struct
import sys
import time
import uuid
from dataclasses import dataclass, field
from typing import Optional

import mc_ids
from mcproto import (
    Buf,
    Connection,
    ConnectionClosed,
    ProtocolError,
    decode_disconnect_reason,
    write_string,
    write_uuid,
    write_varint,
)

# --- modbridge protocol ----------------------------------------------------- #
CH_HELLO = "modbridge:hello"
CH_HELLO_ACK = "modbridge:hello_ack"
CH_PING = "modbridge:ping"
CH_PONG = "modbridge:pong"
CH_TOAST = "modbridge:toast"
CH_BRAND = "minecraft:brand"
MODBRIDGE_PROTOCOL = 1
MOD_VERSION = "1.0.0-testclient"

# connection states
HANDSHAKE, LOGIN, CONFIG, PLAY = "HANDSHAKE", "LOGIN", "CONFIG", "PLAY"


class Failure(Exception):
    """The scripted flow did not go as expected."""


class _Done(Exception):
    """Raised when an expected disconnect arrived (--expect-kick): flow is over."""


@dataclass
class Options:
    host: str = "127.0.0.1"
    port: int = 25565
    username: str = "ModBot"
    protocol: int = mc_ids.PROTOCOL_VERSION
    brand: str = "vanilla"
    # modbridge behaviour
    ack: bool = True              # answer modbridge:hello
    bad_version: bool = False     # answer with an unsupported protocol version
    send_ping: bool = True        # send modbridge:ping in play
    expect_toast: bool = False    # fail unless a toast arrives
    expect_kick: bool = False     # success == being disconnected
    expect_kick_text: str = ""    # ... and the reason must contain this
    # behave like the NeoForge client mod: announce channels with minecraft:register and
    # refuse (like NeoForge's NetworkRegistry.checkPacket) to send a payload the server did
    # not announce with minecraft:register / refuse a modbridge payload before the brand
    neoforge_like: bool = False
    # known packs answer: "empty" or "echo"
    known_packs: str = "empty"
    # timings (seconds)
    config_timeout: float = 45.0  # max silence while in login/config
    pong_timeout: float = 5.0
    toast_timeout: float = 5.0
    kick_wait: float = 5.0        # how long to wait for a kick once in play
    linger: float = 1.0           # keep listening this long after the goals are met
    idle: float = 0.0             # stay in play at least this long
    quiet: bool = False           # do not print the packet log
    verbose: bool = False         # print every packet, not just the first of each kind


@dataclass
class Result:
    ok: bool
    message: str
    kicked: bool = False
    kick_reason: str = ""
    reached_play: bool = False
    rtt_ms: Optional[float] = None
    server_tick: Optional[int] = None
    hello: Optional[tuple] = None          # (protocolVersion, serverName)
    toasts: list = field(default_factory=list)  # [(title, message)]
    events: list = field(default_factory=list)  # structured log lines


class ModbridgeClient:
    def __init__(self, options: Options):
        self.o = options
        self.conn: Optional[Connection] = None
        self.state = HANDSHAKE
        self.t0 = time.monotonic()
        self.res = Result(ok=False, message="not started")
        self.counts: dict[str, int] = {}
        self.ping_sent_at: Optional[float] = None
        self.ping_nonce: Optional[int] = None
        self.pong_received = False
        self.announced: set = set()   # channels the server announced via minecraft:register
        self.brand_seen = False

    # ------------------------------------------------------------- logging -- #
    def log(self, kind: str, text: str) -> None:
        line = f"[{time.monotonic() - self.t0:7.3f}s] {self.state:<9} {kind:<5} {text}"
        self.res.events.append(line)
        if not self.o.quiet:
            print(line, flush=True)

    def _names(self, outbound: bool) -> dict:
        prefix = "C2S_" if outbound else "S2C_"
        return getattr(mc_ids, prefix + self.state, {})

    def log_packet(self, outbound: bool, pid: int, size: int, detail: str = "") -> None:
        name = self._names(outbound).get(pid, "?")
        key = f"{self.state}/{'C2S' if outbound else 'S2C'}/{name}"
        self.counts[key] = self.counts.get(key, 0) + 1
        # Play-phase traffic is mostly entity/chunk spam: print each kind once
        # (the totals are in the summary at the end). Registries likewise.
        always = ("custom_payload", "disconnect", "keep_alive", "ping", "player_position",
                  "start_configuration", "login", "finish_configuration")
        if not self.o.verbose and name not in always and self.counts[key] > 1 and (
                self.state == PLAY or name == "registry_data"):
            return
        self.log("C2S" if outbound else "S2C",
                 f"#{pid:<3} {name:<26} {size:>6}B {detail}".rstrip())

    # ---------------------------------------------------------------- send -- #
    def send(self, pid: int, payload: bytes = b"", detail: str = "") -> None:
        assert self.conn
        self.log_packet(True, pid, len(payload), detail)
        self.conn.send(pid, payload)

    def send_plugin_message(self, channel: str, data: bytes) -> None:
        if (self.o.neoforge_like and not channel.startswith("minecraft:")
                and channel not in self.announced):
            raise Failure(f"[neoforge-like] NeoForge would refuse to send {channel}: the server never "
                          f"announced it with minecraft:register (announced: {sorted(self.announced)})")
        pid = 2 if self.state == CONFIG else 22  # serverbound custom_payload
        self.send(pid, write_string(channel) + data, f"channel={channel} data={data.hex()}")

    # ----------------------------------------------------------------- run -- #
    def run(self) -> Result:
        o = self.o
        try:
            self.log("INFO", f"connecting to {o.host}:{o.port} as {o.username} "
                             f"(MC 26.3, protocol {o.protocol})")
            self.conn = Connection(o.host, o.port)
            self._handshake_and_login()
            self._configuration()
            self._play()
            self._finish_ok()
        except _Done:
            self._finish_ok()
        except Failure as failure:
            self.res.ok = False
            self.res.message = str(failure)
        except ConnectionClosed as closed:
            self.res.ok = False
            self.res.message = f"{closed} (state {self.state})"
        except socket.timeout:
            self.res.ok = False
            self.res.message = f"timed out in state {self.state}"
        except ProtocolError as error:
            self.res.ok = False
            self.res.message = f"protocol error in state {self.state}: {error}"
        except OSError as error:
            self.res.ok = False
            self.res.message = f"socket error: {error}"
        finally:
            if self.conn:
                self.conn.close()
        if not self.o.quiet:
            spam = {k: v for k, v in self.counts.items() if v > 1}
            self.log("INFO", "packet counts (kinds seen more than once): "
                     + ", ".join(f"{k}={v}" for k, v in sorted(spam.items())))
        self.log("END", ("OK: " if self.res.ok else "FAIL: ") + self.res.message)
        return self.res

    def _finish_ok(self) -> None:
        r = self.res
        r.ok = True
        if r.kicked:
            r.message = f"disconnected as expected: {r.kick_reason!r}"
        else:
            bits = ["reached PLAY"]
            if r.rtt_ms is not None:
                bits.append(f"ping/pong ok rtt={r.rtt_ms:.1f}ms serverTick={r.server_tick}")
            if r.toasts:
                bits.append(f"{len(r.toasts)} toast(s)")
            r.message = ", ".join(bits)

    # ----------------------------------------------- disconnect handling ---- #
    def _on_disconnect(self, payload: bytes) -> None:
        reason = decode_disconnect_reason(payload, nbt=self.state != LOGIN)
        self.res.kicked = True
        self.res.kick_reason = reason
        self.log("KICK", f"disconnected by server: {reason!r}")
        if not self.o.expect_kick:
            raise Failure(f"disconnected by server in {self.state}: {reason!r}")
        if self.o.expect_kick_text and self.o.expect_kick_text not in reason:
            raise Failure(f"kick reason {reason!r} does not contain "
                          f"{self.o.expect_kick_text!r}")
        raise _Done()

    # ---------------------------------------------------- handshake/login --- #
    def _handshake_and_login(self) -> None:
        o = self.o
        body = (write_varint(o.protocol) + write_string(o.host)
                + o.port.to_bytes(2, "big") + write_varint(2))
        self.send(0, body, f"protocol={o.protocol} next=login")
        self.state = LOGIN
        offline = uuid.UUID(bytes=_offline_uuid_bytes(o.username))
        self.send(0, write_string(o.username) + write_uuid(offline),
                  f"name={o.username} uuid={offline}")
        while True:
            pid, payload = self._recv(o.config_timeout)
            self.log_packet(False, pid, len(payload))
            if pid == 0:                      # login_disconnect (JSON)
                self._on_disconnect(payload)
            elif pid == 1:                    # hello == encryption request
                raise Failure("server wants encryption (online_mode / encryption=true); "
                              "this client needs `encryption = false` and offline mode")
            elif pid == 3:                    # set compression
                threshold = Buf(payload).varint()
                self.conn.compression_threshold = threshold
                self.log("INFO", f"compression threshold = {threshold}")
            elif pid == 4:                    # custom_query -> not understood
                message_id = Buf(payload).varint()
                self.send(2, write_varint(message_id) + b"\x00", "custom_query answer: none")
            elif pid == 5:                    # cookie_request -> no cookie
                key = Buf(payload).string()
                self.send(4, write_string(key) + b"\x00", "cookie_response: none")
            elif pid == 2:                    # login_finished
                buf = Buf(payload)
                uid, name = buf.uuid(), buf.string()
                self.log("INFO", f"login success: {name} {uid}")
                self.send(3, b"", "login_acknowledged")
                self.state = CONFIG
                self._send_config_hello()
                return
            else:
                self.log("WARN", f"unexpected login packet {pid}")

    # -------------------------------------------------------- configuration -- #
    def _send_config_hello(self) -> None:
        """What a vanilla client sends right after entering CONFIG."""
        o = self.o
        self.send_plugin_message(CH_BRAND, write_string(o.brand))
        info = (write_string("en_us") + bytes([8])      # locale, view distance
                + write_varint(0) + b"\x01"             # chat mode, chat colors
                + bytes([0x7F]) + write_varint(1)       # skin parts, main hand
                + b"\x00\x01" + write_varint(0))        # text filtering, listing, particles
        self.send(0, info, "client_information en_us")
        if o.neoforge_like:
            names = ["minecraft:register", "minecraft:unregister", "neoforge:register",
                     "neoforge:network", "neoforge:modded_network_setup_failed",
                     "c:version", "c:register", CH_HELLO]
            self.send_plugin_message("minecraft:register", b"".join(n.encode() + b"\0" for n in names))

    def _configuration(self) -> None:
        o = self.o
        registries = 0
        while True:
            pid, payload = self._recv(o.config_timeout)
            buf = Buf(payload)
            name = mc_ids.S2C_CONFIG.get(pid, "?")
            if name == "registry_data":
                registries += 1
            detail = ""
            if name == "custom_payload":
                channel = buf.string()
                detail = f"channel={channel} data={buf.data[buf.pos:].hex()}"
            self.log_packet(False, pid, len(payload), detail)

            if name == "custom_payload":
                self._config_payload(channel, Buf(buf.rest()))
            elif name == "disconnect":
                self._on_disconnect(payload)
            elif name == "keep_alive":
                self.send(4, payload, "keep_alive echo")
            elif name == "ping":
                self.send(5, payload, "pong")
            elif name == "cookie_request":
                self.send(1, write_string(buf.string()) + b"\x00", "cookie_response: none")
            elif name == "select_known_packs":
                count = buf.varint()
                packs = [(buf.string(), buf.string(), buf.string()) for _ in range(count)]
                self.log("INFO", f"known packs offered: {packs}")
                if o.known_packs == "echo":
                    answer = write_varint(count) + b"".join(
                        write_string(a) + write_string(b) + write_string(c) for a, b, c in packs)
                else:
                    answer = write_varint(0)
                self.send(7, answer, f"select_known_packs ({o.known_packs})")
            elif name == "resource_pack_push":
                pack_id = buf.uuid()
                for status, label in ((3, "accepted"), (4, "downloaded"), (0, "loaded")):
                    self.send(6, write_uuid(pack_id) + write_varint(status),
                              f"resource_pack {label}")
            elif name == "code_of_conduct":
                self.log("INFO", "accepting code of conduct")
                self.send(9, b"", "accept_code_of_conduct")
            elif name == "transfer":
                raise Failure("server sent a transfer packet")
            elif name == "finish_configuration":
                self.log("INFO", f"configuration finished ({registries} registries)")
                self.send(3, b"", "finish_configuration ack")
                self.state = PLAY
                self.res.reached_play = True
                if o.neoforge_like:     # NetworkRegistry.onConfigurationFinished
                    self.send_plugin_message("minecraft:unregister", b"minecraft:register\0minecraft:unregister\0" + CH_HELLO.encode() + b"\0")
                    self.send_plugin_message("minecraft:register", b"minecraft:register\0minecraft:unregister\0"
                                             + CH_PONG.encode() + b"\0" + CH_TOAST.encode() + b"\0")
                return
            # everything else (registry_data, update_tags, features, links, ...) needs no answer

    def _config_payload(self, channel: str, data: Buf) -> None:
        o = self.o
        if channel == "minecraft:register":
            names = {n for n in data.rest().decode().split("\0") if n}
            self.announced |= names
            self.log("MB", f"server announced channels: {sorted(names)}")
        elif channel == CH_HELLO:
            if o.neoforge_like and not self.brand_seen:
                raise Failure("[neoforge-like] modbridge:hello arrived before minecraft:brand; "
                              "NeoForge disconnects ('No Payload Setup')")
            version = data.varint()
            server_name = data.string()
            self.res.hello = (version, server_name)
            self.log("MB", f"hello from server: protocol={version} serverName={server_name!r}")
            if not o.ack:
                self.log("MB", "NOT acknowledging hello (--no-ack / --vanilla)")
                return
            ack_version = 99 if o.bad_version else MODBRIDGE_PROTOCOL
            self.send_plugin_message(
                CH_HELLO_ACK, write_varint(ack_version) + write_string(MOD_VERSION))
            self.log("MB", f"sent hello_ack protocol={ack_version} modVersion={MOD_VERSION}")
        elif channel == CH_BRAND:
            self.brand_seen = True
            self.log("INFO", f"server brand: {data.string()!r}")

    # ------------------------------------------------------------------ play -- #
    def _play(self) -> None:
        o = self.o
        entered = time.monotonic()
        want_ping = o.send_ping and o.ack and not o.expect_kick
        pong_deadline = toast_deadline = None
        ping_pending = want_ping
        got_login = False
        login_at = 0.0
        goals_met_at: Optional[float] = None
        idle_until = entered + o.idle

        while True:
            now = time.monotonic()
            if o.expect_kick and now > entered + o.kick_wait:
                raise Failure(f"expected a kick, but still in PLAY after {o.kick_wait}s")
            if pong_deadline and not self.pong_received and now > pong_deadline:
                raise Failure(f"no modbridge:pong within {o.pong_timeout}s")
            if o.expect_toast and not self.res.toasts:
                toast_deadline = toast_deadline or entered + o.toast_timeout
                if now > toast_deadline:
                    raise Failure(f"no modbridge:toast within {o.toast_timeout}s")
            goals = ((not want_ping or self.pong_received)
                     and (not o.expect_toast or self.res.toasts)
                     and not o.expect_kick and got_login)
            if goals:
                goals_met_at = goals_met_at or now
                if now >= max(goals_met_at + o.linger, idle_until):
                    return
            # send the ping once play started; a (NeoForge-like) mod user presses a key
            # later, so wait up to 1s for the server to announce the channel
            if ping_pending and got_login and (
                    not o.neoforge_like or CH_PING in self.announced or now > login_at + 1.0):
                ping_pending = False
                self.ping_nonce = random.getrandbits(62)
                self.ping_sent_at = time.monotonic()
                pong_deadline = self.ping_sent_at + o.pong_timeout
                self.send_plugin_message(CH_PING, self.ping_nonce.to_bytes(8, "big"))
                self.log("MB", f"sent ping nonce={self.ping_nonce}")
            try:
                pid, payload = self._recv(0.2)
            except socket.timeout:
                continue
            buf = Buf(payload)
            name = mc_ids.S2C_PLAY.get(pid, "?")
            detail = ""
            if name == "custom_payload":
                channel = buf.string()
                detail = f"channel={channel}"
            self.log_packet(False, pid, len(payload), detail)

            if name == "disconnect":
                self._on_disconnect(payload)
            elif name == "keep_alive":
                self.send(28, payload, "keep_alive echo")
            elif name == "ping":
                self.send(45, payload, "pong")
            elif name == "player_position":
                # 26.3: the confirmation echoes id + position + rotation
                tp_id = buf.varint()
                pos = struct.unpack(">ddd", buf.read(24))
                buf.read(24)                           # delta movement
                yaw, pitch = struct.unpack(">ff", buf.read(8))
                self.send(0, write_varint(tp_id) + struct.pack(">dddff", *pos, yaw, pitch),
                          f"accept_teleportation id={tp_id}")
            elif name == "chunk_batch_finished":
                self.send(11, b"\x41\xa0\x00\x00", "chunk_batch_received 20.0")
            elif name == "cookie_request":
                self.send(21, write_string(buf.string()) + b"\x00", "cookie_response: none")
            elif name == "start_configuration":
                self.send(16, b"", "configuration_acknowledged")
                self.state = CONFIG
                self._configuration()      # reconfiguration, then back to PLAY
                continue
            elif name == "login":
                got_login = True
                self.send(44, b"", "player_loaded")
                login_at = time.monotonic()
            elif name == "custom_payload":
                self._play_payload(channel, Buf(buf.rest()))

    def _play_payload(self, channel: str, data: Buf) -> None:
        if channel == "minecraft:register":
            names = {n for n in data.rest().decode().split("\0") if n}
            self.announced |= names
            self.log("MB", f"server announced play channels: {sorted(names)}")
        elif channel == CH_PONG:
            nonce, tick = data.i64(), data.i64()
            if nonce != self.ping_nonce:
                raise Failure(f"pong nonce mismatch: got {nonce}, sent {self.ping_nonce}")
            self.pong_received = True
            self.res.rtt_ms = (time.monotonic() - self.ping_sent_at) * 1000
            self.res.server_tick = tick
            self.log("MB", f"pong nonce={nonce} serverTick={tick} rtt={self.res.rtt_ms:.1f}ms")
        elif channel == CH_TOAST:
            title, message = data.string(), data.string()
            self.res.toasts.append((title, message))
            self.log("MB", f"TOAST title={title!r} message={message!r}")
        elif channel == CH_BRAND:
            self.log("INFO", f"server brand: {data.string()!r}")

    # ---------------------------------------------------------------- misc --- #
    def _recv(self, timeout: float) -> tuple[int, bytes]:
        return self.conn.recv(timeout)


def _offline_uuid_bytes(name: str) -> bytes:
    """UUID v3 of "OfflinePlayer:<name>" (Java's UUID.nameUUIDFromBytes)."""
    digest = bytearray(hashlib.md5(f"OfflinePlayer:{name}".encode()).digest())
    digest[6] = (digest[6] & 0x0F) | 0x30
    digest[8] = (digest[8] & 0x3F) | 0x80
    return bytes(digest)


def parse_args(argv=None) -> tuple[Options, argparse.Namespace]:
    p = argparse.ArgumentParser(
        description="Scripted modbridge test client for Minecraft Java 26.3 "
                    "(offline-mode, no-encryption servers).",
        epilog="--neoforge-mod [MOD.json] runs neoforge_client.py instead: a strict NeoForge client with a "
               "content mod (registry sync verification). See `neoforge_client.py --help`.")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=25565)
    p.add_argument("--username", default="ModBot")
    p.add_argument("--protocol", type=int, default=mc_ids.PROTOCOL_VERSION,
                   help="protocol number sent in the handshake (default 777 = 26.3)")
    p.add_argument("--brand", default="vanilla", help="client brand to send")
    g = p.add_argument_group("modbridge behaviour")
    g.add_argument("--no-ack", action="store_true",
                   help="receive modbridge:hello but do not answer it")
    g.add_argument("--vanilla", action="store_true",
                   help="behave like a vanilla client: ignore hello, never send ping")
    g.add_argument("--bad-version", action="store_true",
                   help="answer hello with an unsupported protocol version (99)")
    g.add_argument("--no-ping", action="store_true", help="do not send modbridge:ping in play")
    g.add_argument("--expect-toast", action="store_true",
                   help="fail unless a modbridge:toast arrives in play")
    g.add_argument("--expect-kick", nargs="?", const="", metavar="TEXT",
                   help="succeed only if the server disconnects us (optionally with a "
                        "reason containing TEXT); the reason is printed")
    g.add_argument("--neoforge-like", action="store_true",
                   help="mimic the NeoForge client mod: announce channels via minecraft:register and "
                        "fail like NeoForge would if the server did not announce hello_ack / ping")
    g.add_argument("--known-packs", choices=("empty", "echo"), default="empty")
    t = p.add_argument_group("timing (seconds)")
    t.add_argument("--config-timeout", type=float, default=45.0,
                   help="max silence while logging in / configuring (default 45)")
    t.add_argument("--pong-timeout", type=float, default=5.0)
    t.add_argument("--toast-timeout", type=float, default=5.0)
    t.add_argument("--kick-wait", type=float, default=5.0)
    t.add_argument("--linger", type=float, default=1.0,
                   help="keep listening this long after the goals are met (default 1)")
    t.add_argument("--idle", type=float, default=0.0,
                   help="stay in PLAY at least this long (keep-alive test)")
    p.add_argument("-v", "--verbose", action="store_true", help="log every packet")
    p.add_argument("-q", "--quiet", action="store_true", help="only print the final result")
    a = p.parse_args(argv)
    o = Options(
        host=a.host, port=a.port, username=a.username, protocol=a.protocol, brand=a.brand,
        ack=not (a.no_ack or a.vanilla), bad_version=a.bad_version,
        send_ping=not (a.no_ping or a.vanilla), expect_toast=a.expect_toast,
        expect_kick=a.expect_kick is not None, expect_kick_text=a.expect_kick or "",
        neoforge_like=a.neoforge_like, known_packs=a.known_packs, config_timeout=a.config_timeout,
        pong_timeout=a.pong_timeout, toast_timeout=a.toast_timeout, kick_wait=a.kick_wait,
        linger=a.linger, idle=a.idle, quiet=a.quiet, verbose=a.verbose)
    return o, a


def main(argv=None) -> int:
    args = sys.argv[1:] if argv is None else list(argv)
    if any(a == "--neoforge-mod" or a.startswith("--neoforge-mod=") for a in args):
        # a strict NeoForge client with a content mod instead of the modbridge mod
        import neoforge_client
        return neoforge_client.main(args)
    options, _ = parse_args(argv)
    result = ModbridgeClient(options).run()
    if options.quiet:
        print(("OK: " if result.ok else "FAIL: ") + result.message)
    if result.kicked:
        print(f"DISCONNECT REASON: {result.kick_reason}")
    return 0 if result.ok else 1


if __name__ == "__main__":
    sys.exit(main())
