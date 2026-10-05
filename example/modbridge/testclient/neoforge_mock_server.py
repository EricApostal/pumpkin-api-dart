#!/usr/bin/env python3
"""A mock NeoForge SERVER speaking the byte formats of docs/neoforge-protocol.md.

It exists to test neoforge_client.py without a Pumpkin plugin, and doubles as a byte-level reference
(a second, Python implementation of what `pumpkin_neoforge` sends). Scenarios:

  adhoc            brand first (what Pumpkin does), then the registry sync over ad hoc channels
  query-first      the real NeoForge order: unregister, register, query, network, then brand, sync
  brand-then-query brand first, then the full handshake (neoforge:network arrives after classification)
  unknown-key      the item registry contains an entry the client does not know
  missing-entry    the item registry lacks an entry the client has
  id-gap           the item ids skip a number
  no-announce      the server does not announce neoforge:frozen_registry_sync_completed (client cannot ack)
  sync-first       query-first order, but the sync comes before neoforge:network (No Payload Setup)
  no-sync          no registry sync at all
  partial-sync     sync_start lists the block registry, but it is never sent
  trailing-bytes   the sync completed payload has an extra byte
  bad-common       c:version offers only version 7
"""

from __future__ import annotations

import argparse
import json
import socket
import threading
import time

import neoforge_proto as nf
from mcproto import Buf, ConnectionClosed, write_string, write_varint
from mock_server import _ServerConn
from neoforge_client import DEFAULT_MOD, DEFAULT_VANILLA, ModSpec, load_vanilla

SERVER_LISTENING = nf.BUILTIN + [nf.SYNC_COMPLETED, nf.DATAMAPS_REPLY, nf.ENUM_ACK, nf.FLAGS_ACK, nf.SPLIT]


class Script:
    """One client connection."""

    def __init__(self, conn: _ServerConn, scenario: str, mod: ModSpec, vanilla: dict):
        self.c, self.scenario, self.mod = conn, scenario, mod
        self.seen: list = []                 # ("C2S", channel) in arrival order
        self.pending: list = []              # (channel, data) read but not consumed
        # item/block registries: vanilla then the mod, i.e. what a real server has
        self.registries = {r: vanilla.get(r, []) + list(mod.registries.get(r, []))
                           for r in ("minecraft:item", "minecraft:block")}

    # -- io ---------------------------------------------------------------- #
    def send(self, channel: str, data: bytes = b"") -> None:
        self.c.send(1, write_string(channel) + data)

    def _read(self, timeout: float):
        pid, data = self.c.recv(timeout)
        if pid == 2:                         # serverbound custom payload (config)
            buf = Buf(data)
            channel = buf.string()
            self.seen.append(("C2S", channel))
            return channel, buf.rest()
        if pid == 0:
            self.seen.append(("C2S", "client_information"))
        elif pid == 3:
            self.seen.append(("C2S", "finish_configuration"))
            return "<finish>", b""
        elif pid == 7:
            self.seen.append(("C2S", "select_known_packs"))
        return None

    def wait_for(self, channel: str, timeout: float = 3.0):
        for i, (ch, data) in enumerate(self.pending):
            if ch == channel:
                return self.pending.pop(i)[1]
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            item = self._read(remaining)
            if item is None:
                continue
            if item[0] == channel:
                return item[1]
            self.pending.append(item)

    # -- phases ------------------------------------------------------------ #
    def login(self) -> None:
        c = self.c
        c.recv(5)                            # handshake
        c.recv(5)                            # login start
        c.send(3, write_varint(256))
        c.compression_threshold = 256
        c.send(2, b"\x11" * 16 + write_string("NeoBot") + write_varint(0) + b"\x22" * 16)
        pid, _ = c.recv(5)
        assert pid == 3, f"expected login_acknowledged, got {pid}"

    def brand(self) -> None:
        self.send(nf.MC_BRAND, write_string("MockNeo"))

    def registry_ids(self, name: str) -> dict:
        entries = list(self.registries[name])
        if self.scenario == "unknown-key" and name == "minecraft:item":
            entries.append("lonsdaleite:ghost_item")
        if self.scenario == "missing-entry" and name == "minecraft:item":
            entries.remove(self.mod.registries[name][-1])
        ids = {i: e for i, e in enumerate(entries)}
        if self.scenario == "id-gap" and name == "minecraft:item":
            ids = {(i if i < 5 else i + 1): e for i, e in enumerate(entries)}
        return ids

    def sync(self) -> bool:
        names = ["minecraft:item", "minecraft:block"]
        self.send(nf.SYNC_START, nf.encode_sync_start(names))
        for name in names:
            if self.scenario == "partial-sync" and name == "minecraft:block":
                continue
            self.send(nf.SYNC_REGISTRY, nf.encode_registry(name, self.registry_ids(name)))
        self.send(nf.SYNC_COMPLETED, b"\x00" if self.scenario == "trailing-bytes" else b"")
        return self.wait_for(nf.SYNC_COMPLETED) is not None

    def negotiate(self) -> None:
        self.send(nf.MC_UNREGISTER, nf.encode_register([nf.MC_REGISTER, nf.MC_UNREGISTER]))
        self.send(nf.MC_REGISTER, nf.encode_register(SERVER_LISTENING))
        self.send(nf.NF_QUERY, nf.encode_query({}))

    def run(self) -> None:
        sc = self.scenario
        self.login()
        if sc in ("query-first", "sync-first"):
            self.negotiate()
            query = self.wait_for(nf.NF_QUERY)
            assert query is not None, "no query answer"
            if sc == "query-first":
                self._network(query)
            self.brand()
        elif sc == "brand-then-query":
            self.brand()
            self.negotiate()
            query = self.wait_for(nf.NF_QUERY)
            assert query is not None, "no query answer"
            self._network(query)
        else:                                 # adhoc and the fault scenarios
            self.brand()
            announced = SERVER_LISTENING if sc != "no-announce" else [c for c in SERVER_LISTENING if c != nf.SYNC_COMPLETED]
            self.send(nf.MC_REGISTER, nf.encode_register(announced))
            self.wait_for(nf.MC_REGISTER)
        if sc != "no-sync":
            if not self.sync():
                return
        if sc == "sync-first":
            self._network(query)
        # what vanilla sends next (tags etc. are irrelevant to this protocol)
        self.c.send(13, write_varint(1) + write_string("minecraft:vanilla"))      # update_enabled_features
        # finish hold: c:
        self.send(nf.C_VERSION, nf.encode_common_version([7] if sc == "bad-common" else [1]))
        if self.wait_for(nf.C_VERSION) is None:
            return
        self.send(nf.C_REGISTER, nf.encode_common_register(1, nf.PLAY, []))
        if self.wait_for(nf.C_REGISTER) is None:
            return
        self.c.send(3)                        # finish_configuration
        self.wait_for("<finish>")
        self.c.send(50, b"\x00" * 8)          # play login (dummy)
        try:
            while True:
                self.c.recv(0.6)
        except (socket.timeout, ConnectionClosed, OSError):
            pass

    def _network(self, query_bytes: bytes) -> None:
        query = nf.decode_query(query_bytes)
        setup = {phase: {c.id: c.version for c in comps} for phase, comps in query.items()}
        self.send(nf.NF_NETWORK, nf.encode_setup(setup))
        self.send(nf.MC_REGISTER, nf.encode_register(nf.BUILTIN + list(setup.get(nf.CONFIGURATION, {}))))


class NeoMockServer:
    def __init__(self, scenario: str = "adhoc", port: int = 0, mod_path: str = DEFAULT_MOD,
                 vanilla_path: str = DEFAULT_VANILLA):
        self.listener = socket.socket()
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.listener.bind(("127.0.0.1", port))
        self.listener.listen(1)
        self.port = self.listener.getsockname()[1]
        self.scenario = scenario
        self.mod, self.vanilla = ModSpec.load(mod_path), load_vanilla(vanilla_path)
        self.seen: list = []
        self.error = None
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self) -> None:
        try:
            client, _ = self.listener.accept()
        except OSError:
            return
        script = Script(_ServerConn(client), self.scenario, self.mod, self.vanilla)
        try:
            script.run()
        except (ConnectionClosed, socket.timeout, OSError):
            pass
        except Exception as e:      # noqa: BLE001 - surfaced to the test
            self.error = e
        finally:
            self.seen = script.seen
            client.close()

    def close(self) -> None:
        self.listener.close()
        self.thread.join(5)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=35966)
    ap.add_argument("--scenario", default="adhoc")
    args = ap.parse_args()
    server = NeoMockServer(args.scenario, args.port)
    print(f"mock NeoForge server on 127.0.0.1:{server.port} (scenario {args.scenario})")
    server.thread.join()
    print(server.seen)
