"""Byte formats of NeoForge's (26.3.x) negotiation payloads, stdlib only.

An independent Python implementation of the layouts in
docs/neoforge-protocol.md (the Dart library `pumpkin_neoforge` has its own and
both are checked against the golden vectors in
packages/pumpkin_neoforge/test/golden/neoforge_codecs.txt, which a Java program
produced from Minecraft's own codec primitives).

Everything here works on `bytes` and returns plain Python values.
"""

from __future__ import annotations

import re
import struct
from dataclasses import dataclass
from typing import Optional

from mcproto import Buf, ProtocolError, write_string, write_varint

# --- enums ----------------------------------------------------------------- #
# ConnectionProtocol ordinals / ids and PacketFlow ordinals
HANDSHAKING, PLAY, STATUS, LOGIN, CONFIGURATION = 0, 1, 2, 3, 4
PHASE_ID = {HANDSHAKING: "handshake", PLAY: "play", STATUS: "status", LOGIN: "login",
            CONFIGURATION: "configuration"}
PHASE_BY_ID = {v: k for k, v in PHASE_ID.items()}
SERVERBOUND, CLIENTBOUND = 0, 1
FLOW_NAME = {SERVERBOUND: "SERVERBOUND", CLIENTBOUND: "CLIENTBOUND"}

# --- channel ids ----------------------------------------------------------- #
MC_REGISTER = "minecraft:register"
MC_UNREGISTER = "minecraft:unregister"
MC_BRAND = "minecraft:brand"
NF_QUERY = "neoforge:register"
NF_NETWORK = "neoforge:network"
NF_SETUP_FAILED = "neoforge:modded_network_setup_failed"
C_VERSION = "c:version"
C_REGISTER = "c:register"
BUILTIN = [MC_REGISTER, MC_UNREGISTER, NF_QUERY, NF_NETWORK, NF_SETUP_FAILED, C_VERSION, C_REGISTER]

SYNC_START = "neoforge:frozen_registry_sync_start"
SYNC_REGISTRY = "neoforge:frozen_registry"
SYNC_COMPLETED = "neoforge:frozen_registry_sync_completed"
DATAMAPS = "neoforge:known_registry_data_maps"
DATAMAPS_REPLY = "neoforge:known_registry_data_maps_reply"
ENUM_DATA = "neoforge:extensible_enum_data"
ENUM_ACK = "neoforge:extensible_enum_ack"
FLAGS = "neoforge:feature_flags"
FLAGS_ACK = "neoforge:feature_flags_ack"
CONFIG_FILE = "neoforge:config_file"
SPLIT = "neoforge:split"

_NS = re.compile(r"^[a-z0-9_.-]+$")
_PATH = re.compile(r"^[a-z0-9_./-]+$")


def normalize_id(text: str) -> str:
    """Identifier.parse: `path` -> `minecraft:path`; raises ProtocolError if invalid."""
    ns, sep, path = text.partition(":")
    if not sep:
        ns, path = "minecraft", text
    ns = ns or "minecraft"
    if not _NS.match(ns) or not path or not _PATH.match(path):
        raise ProtocolError(f"invalid identifier {text!r}")
    return f"{ns}:{path}"


# --- minecraft:register ----------------------------------------------------- #
def encode_register(channels) -> bytes:
    out, seen = bytearray(), set()
    for c in channels:
        c = normalize_id(c)
        if c in seen:
            continue
        seen.add(c)
        out += c.encode("latin-1") + b"\0"
    return bytes(out)


def decode_register(data: bytes) -> list[str]:
    """DinnerboneProtocolUtils.readChannels: NUL separated, invalid names ignored."""
    result, seen = [], set()
    for part in data.decode("latin-1").split("\0"):
        if not part:
            continue
        try:
            n = normalize_id(part)
        except ProtocolError:
            continue
        if n not in seen:
            seen.add(n)
            result.append(n)
    return result


# --- shared helpers ---------------------------------------------------------- #
def write_id(text: str) -> bytes:
    return write_string(normalize_id(text))


def read_id(buf: Buf) -> str:
    return normalize_id(buf.string())


def write_bool(value: bool) -> bytes:
    return b"\x01" if value else b"\x00"


def read_count(buf: Buf, what: str, limit: int = 1 << 20) -> int:
    n = buf.varint()
    if n < 0 or n > limit:
        raise ProtocolError(f"bad {what} count {n}")
    return n


def expect_end(buf: Buf, what: str) -> None:
    """PacketDecoder: 'Packet was larger than I expected, found N bytes extra'."""
    if buf.remaining():
        raise ProtocolError(f"{what}: {buf.remaining()} byte(s) extra after reading the payload")


# --- neoforge:register (query) ----------------------------------------------- #
@dataclass(frozen=True)
class Component:
    id: str
    version: str
    flow: Optional[int] = None   # PacketFlow ordinal or None (both)
    optional: bool = False


def encode_query(by_phase: dict) -> bytes:
    out = bytearray(write_varint(len(by_phase)))
    for phase in sorted(by_phase):
        out += write_varint(phase)
        comps = list(by_phase[phase])
        out += write_varint(len(comps))
        for c in comps:
            out += write_id(c.id) + write_string(c.version)
            if c.flow is None:
                out += b"\x00"
            else:
                out += b"\x01" + write_varint(c.flow)
            out += write_bool(c.optional)
    return bytes(out)


def decode_query(data: bytes) -> dict:
    buf = Buf(data)
    result = {}
    for _ in range(read_count(buf, "protocol", 5)):
        phase = buf.varint()
        if phase not in PHASE_ID:
            raise ProtocolError(f"unknown connection protocol {phase}")
        comps = []
        for _ in range(read_count(buf, "component", 4096)):
            cid = read_id(buf)
            version = buf.string()
            flow = None
            if buf.boolean():
                flow = buf.varint()
                if flow not in FLOW_NAME:
                    raise ProtocolError(f"unknown packet flow {flow}")
            comps.append(Component(cid, version, flow, buf.boolean()))
        result[phase] = comps
    expect_end(buf, NF_QUERY)
    return result


# --- neoforge:network (setup) -------------------------------------------------- #
def encode_setup(by_phase: dict) -> bytes:
    """by_phase: {phase: {channel_id: version}}"""
    out = bytearray(write_varint(len(by_phase)))
    for phase in sorted(by_phase):
        out += write_varint(phase)
        channels = by_phase[phase]
        out += write_varint(len(channels))
        for cid, version in channels.items():
            out += write_id(cid) + write_id(cid) + write_string(version)
    return bytes(out)


def decode_setup(data: bytes) -> dict:
    buf = Buf(data)
    result = {}
    for _ in range(read_count(buf, "protocol", 5)):
        phase = buf.varint()
        if phase not in PHASE_ID:
            raise ProtocolError(f"unknown connection protocol {phase}")
        channels = {}
        for _ in range(read_count(buf, "channel", 4096)):
            key = read_id(buf)
            inner = read_id(buf)
            if inner != key:
                raise ProtocolError(f"channel {key} is described as {inner}")
            channels[key] = buf.string()
        result[phase] = channels
    expect_end(buf, NF_NETWORK)
    return result


# --- neoforge:modded_network_setup_failed -------------------------------------- #
def encode_nbt_text(text: str, translate: bool = False, args=()) -> bytes:
    """Network NBT of a text component: a string tag, or {translate, with:[{text}...]}."""
    def s(value: str) -> bytes:
        raw = value.encode("utf-8")  # fine for the ASCII this module writes
        return struct.pack(">H", len(raw)) + raw

    if not translate:
        return b"\x08" + s(text)
    out = bytearray(b"\x0a")
    out += b"\x08" + s("translate") + s(text)
    if args:
        out += b"\x09" + s("with") + b"\x0a" + struct.pack(">i", len(args))
        for a in args:
            out += b"\x08" + s("text") + s(a) + b"\x00"
    out += b"\x00"
    return bytes(out)


def encode_setup_failed(reasons: dict) -> bytes:
    """reasons: {channel_id: already-encoded NBT bytes}"""
    out = bytearray(write_varint(len(reasons)))
    for cid, nbt in reasons.items():
        out += write_id(cid) + nbt
    return bytes(out)


def decode_setup_failed(data: bytes) -> dict:
    from mcproto import _component_text, _nbt_payload
    buf = Buf(data)
    result = {}
    for _ in range(read_count(buf, "reason", 4096)):
        cid = read_id(buf)
        tag = buf.byte()
        result[cid] = _component_text(_nbt_payload(buf, tag))
    expect_end(buf, NF_SETUP_FAILED)
    return result


# --- c:version, c:register ------------------------------------------------------ #
def encode_common_version(versions) -> bytes:
    return write_varint(len(versions)) + b"".join(write_varint(v) for v in versions)


def decode_common_version(data: bytes) -> list[int]:
    buf = Buf(data)
    versions = [buf.varint() for _ in range(read_count(buf, "version", 4096))]
    expect_end(buf, C_VERSION)
    return versions


def encode_common_register(version: int, phase: int, channels) -> bytes:
    out = write_varint(version) + write_string(PHASE_ID[phase])
    out += write_varint(len(list(channels)))
    return out + b"".join(write_id(c) for c in channels)


def decode_common_register(data: bytes):
    buf = Buf(data)
    version = buf.varint()
    pid = buf.string()
    if pid not in PHASE_BY_ID:
        raise ProtocolError(f"unknown connection protocol {pid!r}")
    channels = [read_id(buf) for _ in range(read_count(buf, "channel", 4096))]
    expect_end(buf, C_REGISTER)
    return version, PHASE_BY_ID[pid], channels


# --- registry sync -------------------------------------------------------------- #
def encode_sync_start(registries) -> bytes:
    return write_varint(len(registries)) + b"".join(write_id(r) for r in registries)


def decode_sync_start(data: bytes) -> list[str]:
    buf = Buf(data)
    names = [read_id(buf) for _ in range(read_count(buf, "registry", 4096))]
    expect_end(buf, SYNC_START)
    return names


def encode_registry(name: str, ids: dict, aliases: Optional[dict] = None) -> bytes:
    """ids: {numeric id: entry name}; written in increasing id order."""
    out = bytearray(write_id(name))
    out += write_varint(len(ids))
    for i in sorted(ids):
        out += write_varint(i) + write_id(ids[i])
    aliases = aliases or {}
    out += write_varint(len(aliases))
    for a in sorted(aliases):
        out += write_id(a) + write_id(aliases[a])
    return bytes(out)


def decode_registry(data: bytes):
    buf = Buf(data)
    name = read_id(buf)
    count = read_count(buf, "entry", 1 << 20)
    ids = {}
    for _ in range(count):
        i = buf.varint()
        ids[i] = read_id(buf)
    aliases = {}
    for _ in range(read_count(buf, "alias", 1 << 20)):
        a = read_id(buf)
        aliases[a] = read_id(buf)
    expect_end(buf, SYNC_REGISTRY)
    return name, ids, aliases


# --- data maps -------------------------------------------------------------------- #
def encode_known_datamaps(maps: dict) -> bytes:
    """maps: {registry: [(data map id, mandatory)]}"""
    out = bytearray(write_varint(len(maps)))
    for registry, entries in maps.items():
        out += write_id(registry) + write_varint(len(entries))
        for did, mandatory in entries:
            out += write_id(did) + write_bool(mandatory)
    return bytes(out)


def decode_known_datamaps(data: bytes) -> dict:
    buf = Buf(data)
    result = {}
    for _ in range(read_count(buf, "registry", 4096)):
        registry = read_id(buf)
        result[registry] = [(read_id(buf), buf.boolean()) for _ in range(read_count(buf, "data map", 4096))]
    expect_end(buf, DATAMAPS)
    return result


def encode_datamaps_reply(maps: dict) -> bytes:
    """maps: {registry: [data map id]}"""
    out = bytearray(write_varint(len(maps)))
    for registry, ids in maps.items():
        out += write_id(registry) + write_varint(len(ids)) + b"".join(write_id(i) for i in ids)
    return bytes(out)


def decode_datamaps_reply(data: bytes) -> dict:
    buf = Buf(data)
    result = {}
    for _ in range(read_count(buf, "registry", 4096)):
        registry = read_id(buf)
        result[registry] = [read_id(buf) for _ in range(read_count(buf, "data map", 4096))]
    expect_end(buf, DATAMAPS_REPLY)
    return result


# --- extensible enums, feature flags, config files ------------------------------------ #
@dataclass(frozen=True)
class EnumEntry:
    class_name: str
    network_check: str            # CLIENTBOUND | SERVERBOUND | BIDIRECTIONAL
    extension: Optional[tuple] = None   # (vanilla_count, total_count, [names])


def encode_enum_data(entries) -> bytes:
    out = bytearray(write_varint(len(entries)))
    for e in entries:
        out += write_string(e.class_name) + write_string(e.network_check)
        if e.extension is None:
            out += b"\x00"
        else:
            vanilla, total, names = e.extension
            out += b"\x01" + write_varint(vanilla) + write_varint(total) + write_varint(len(names))
            out += b"".join(write_string(n) for n in names)
    return bytes(out)


def decode_enum_data(data: bytes) -> list[EnumEntry]:
    buf = Buf(data)
    entries = []
    for _ in range(read_count(buf, "enum", 4096)):
        cls = buf.string()
        check = buf.string()
        if check not in ("CLIENTBOUND", "SERVERBOUND", "BIDIRECTIONAL"):
            raise ProtocolError(f"unknown NetworkCheck {check!r}")
        ext = None
        if buf.boolean():
            vanilla, total = buf.varint(), buf.varint()
            ext = (vanilla, total, [buf.string() for _ in range(read_count(buf, "enum entry", 4096))])
        entries.append(EnumEntry(cls, check, ext))
    expect_end(buf, ENUM_DATA)
    return entries


def encode_flags(flags) -> bytes:
    return write_varint(len(flags)) + b"".join(write_id(f) for f in flags)


def decode_flags(data: bytes) -> list[str]:
    buf = Buf(data)
    flags = [read_id(buf) for _ in range(read_count(buf, "flag", 4096))]
    expect_end(buf, FLAGS)
    return flags


def encode_config_file(name: str, contents: bytes) -> bytes:
    return write_string(name) + write_varint(len(contents)) + contents


def decode_config_file(data: bytes):
    buf = Buf(data)
    name = buf.string()
    contents = buf.read(buf.varint())
    expect_end(buf, CONFIG_FILE)
    return name, contents
