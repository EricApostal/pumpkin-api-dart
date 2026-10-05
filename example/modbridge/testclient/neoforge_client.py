#!/usr/bin/env python3
"""A strict NeoForge 26.3 client with a content mod, for testing servers that
pretend to be NeoForge servers (the Dart library `pumpkin_neoforge`).

It behaves like a real NeoForge client that has a mod installed which adds
registry entries (items, a block, a creative tab; no custom payloads): it
speaks the client half of NeoForge's configuration-phase exchange exactly as
the NeoForge source does (docs/neoforge-protocol.md cites every rule), VERIFIES
the registry sync the way the real client does, and reports PASS/FAIL per
check with the real client's disconnect messages.

    python3 neoforge_client.py --port 35965 --neoforge-mod mods/lonsdaleite.json
    python3 modbridge_client.py --port 35965 --neoforge-mod mods/lonsdaleite.json   # same thing

What is emulated (NeoForge branch 26.3.x, files in brackets):

* classification of the connection: the server's minecraft:brand, or
  update_enabled_features, or finish-configuration makes the client treat the
  server as "other" (not NeoForge) unless a neoforge:register query came
  first [ClientConfigurationPacketListenerImpl patch, ClientNetworkRegistry];
* the ad hoc channel rules: a modded payload before classification
  disconnects ("No Payload Setup"); an unannounced channel cannot be sent
  [NetworkRegistry.checkPacket]; an optional payload is readable ad hoc;
* neoforge:register / neoforge:network / minecraft:register / c:version /
  c:register, the registry sync (neoforge:frozen_registry*), the data map
  negotiation, extensible enums and feature flag checks;
* RegistryManager.applySnapshot: unknown keys disconnect the client; the
  server's ids replace the client's.

Two checks are STRICTER than the real client, because the real one would just
fail later in game (use --lenient to downgrade them to warnings): ids of a
synced registry must be contiguous, and every entry the client has must get an
id.

Exit status: 0 PASS, 1 FAIL.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass, field
from typing import Optional

import mc_ids
import neoforge_proto as nf
from mcproto import Buf, ProtocolError, write_string, write_uuid, write_varint
from modbridge_client import (CONFIG, PLAY, Failure, ModbridgeClient, Options,
                              Result)

NEOFORGE_VERSION = "26.3.0.7-beta (simulated)"
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_MOD = os.path.join(HERE, "mods", "lonsdaleite.json")
DEFAULT_VANILLA = os.path.normpath(os.path.join(
    HERE, "..", "..", "..", "packages", "pumpkin_neoforge", "data", "vanilla_registries.json"))

PASS, FAIL, WARN, INFO = "PASS", "FAIL", "WARN", "INFO"


class ClientDisconnect(Exception):
    """The real client would disconnect here; the text is what it would show."""


# --------------------------------------------------------------------------- #
# What the client has installed
# --------------------------------------------------------------------------- #
def _c(cid, flow, version="1", optional=True):
    return nf.Component(cid, version, flow, optional)


CB, SB = nf.CLIENTBOUND, nf.SERVERBOUND
# NetworkInitialization + GenericPacketSplitter: every registration is optional, version "1"
OWN_REGISTRATIONS = {
    nf.CONFIGURATION: [
        _c(nf.CONFIG_FILE, CB), _c(nf.SYNC_START, CB), _c(nf.SYNC_REGISTRY, CB),
        _c(nf.SYNC_COMPLETED, None), _c(nf.DATAMAPS, CB), _c(nf.ENUM_DATA, CB), _c(nf.FLAGS, CB),
        _c(nf.DATAMAPS_REPLY, SB), _c(nf.ENUM_ACK, SB), _c(nf.FLAGS_ACK, SB), _c(nf.SPLIT, None),
    ],
    nf.PLAY: [
        _c(nf.CONFIG_FILE, CB),
        _c("neoforge:advanced_add_entity", CB), _c("neoforge:advanced_open_screen", CB),
        _c("neoforge:auxiliary_light_data", CB), _c("neoforge:registry_data_map_sync", CB),
        _c("neoforge:advanced_container_set_data", CB), _c("neoforge:recipe_content", CB),
        _c("neoforge:sync_attachments", CB), _c(nf.SPLIT, None),
    ],
}

# NeoForgeDataMaps: the data maps NeoForge itself registers (RegistryManager.getDataMaps())
OWN_DATA_MAPS = {
    "minecraft:entity_type": ["neoforge:acceptable_villager_distances", "neoforge:monster_room_mobs",
                              "neoforge:parrot_imitations"],
    "minecraft:block": ["neoforge:oxidizables", "neoforge:strippables", "neoforge:waxables"],
    "minecraft:villager_profession": ["neoforge:raid_hero_gifts"],
    "minecraft:game_event": ["neoforge:vibration_frequencies"],
    "minecraft:item": ["neoforge:villager_compostables"],
    "minecraft:worldgen/biome": ["neoforge:villager_types"],
}

# Registries that exist in vanilla / NeoForge but for which no entry list is bundled: a snapshot
# for them cannot be verified (the real client knows their entries).
UNVERIFIABLE_PREFIXES = ("minecraft:", "neoforge:")


@dataclass
class ModSpec:
    mod_id: str = "mod"
    display_name: str = "mod"
    version: str = "1"
    registries: dict = field(default_factory=dict)       # registry -> [entries] the mod registers
    payloads: list = field(default_factory=list)         # [{id, version, protocols, flow, optional}]
    data_maps: list = field(default_factory=list)        # [{registry, id, mandatory}]
    feature_flags: list = field(default_factory=list)
    extended_enums: list = field(default_factory=list)   # [{class, check, vanilla, total, entries}]
    # block -> {"properties": {name: [values]}}: the state properties of the mod's blocks, in any order
    block_states: dict = field(default_factory=dict)

    @staticmethod
    def load(path: str) -> "ModSpec":
        with open(path, encoding="utf-8") as f:
            raw = json.load(f)
        return ModSpec(
            mod_id=raw.get("mod_id", "mod"), display_name=raw.get("display_name", raw.get("mod_id", "mod")),
            version=raw.get("version", "1"), registries=raw.get("registries", {}),
            payloads=raw.get("payloads", []), data_maps=raw.get("data_maps", []),
            feature_flags=raw.get("feature_flags", []), extended_enums=raw.get("extended_enums", []),
            block_states=raw.get("block_states", {}))

    def components(self) -> dict:
        """The mod's payload registrations per protocol."""
        flows = {"clientbound": CB, "serverbound": SB, None: None}
        out = {nf.CONFIGURATION: [], nf.PLAY: []}
        for p in self.payloads:
            comp = nf.Component(nf.normalize_id(p["id"]), p.get("version", "1"), flows[p.get("flow")],
                                bool(p.get("optional", False)))
            for phase in p.get("protocols", ["play"]):
                out[nf.PHASE_BY_ID[phase]].append(comp)
        return out


def load_vanilla(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)["registries"]


def load_vanilla_state_count(path: str) -> Optional[int]:
    """The number of vanilla block states (the first state id of a modded block), if the file has it."""
    with open(path, encoding="utf-8") as f:
        return json.load(f).get("block_state_count")


# --------------------------------------------------------------------------- #
# The registries of the client (RegistryManager.applySnapshot)
# --------------------------------------------------------------------------- #
class ClientRegistries:
    """The client's registries: vanilla entries, then the mod's, with natural ids."""

    def __init__(self, vanilla: dict, mod: dict):
        self.entries: dict[str, list] = {}
        self.vanilla_count: dict[str, int] = {}
        for name in set(vanilla) | set(mod):
            v = list(vanilla.get(name, []))
            self.vanilla_count[name] = len(v)
            self.entries[name] = v + [e for e in mod.get(name, []) if e not in v]
        self.ids: dict[str, dict] = {n: {e: i for i, e in enumerate(es)} for n, es in self.entries.items()}
        self.applied: dict[str, dict] = {}

    def apply(self, snapshots: dict, lenient: bool):
        """Returns (missing keys, notes[(status, text)]). Raises ClientDisconnect for unknown registries."""
        missing, notes = [], []
        for name, (ids, aliases) in snapshots.items():
            if name not in self.entries:
                if not ids:
                    continue   # "Ignore registries that the client is not aware of as long as they are empty"
                if name.startswith(UNVERIFIABLE_PREFIXES):
                    notes.append((WARN, f"{name}: no entry list bundled, {len(ids)} entries cannot be verified"))
                    self.applied[name] = {e: i for i, e in ids.items()}
                    continue
                raise ClientDisconnect(
                    "Failed to sync registries from the server: java.lang.IllegalStateException: Tried to "
                    f"applied snapshot with registry name {name} but was not found")
            known = set(self.entries[name])
            new_ids, found_missing = {}, False
            for i in sorted(ids):
                key = ids[i]
                if key not in known:
                    missing.append(f"ResourceKey[{name} / {key}]")
                    found_missing = True
                elif not found_missing:
                    new_ids[key] = i
            if found_missing:
                continue
            # --- stricter than NeoForge ------------------------------------- #
            status = WARN if lenient else FAIL
            keys = sorted(ids)
            if keys and keys != list(range(len(keys))):
                notes.append((status, f"{name}: ids are not contiguous 0..{len(keys) - 1} "
                                      f"(gap or offset; the client's id table would contain holes)"))
            uncovered = [e for e in self.entries[name] if e not in new_ids]
            if uncovered:
                notes.append((status, f"{name}: {len(uncovered)} entr{'y' if len(uncovered) == 1 else 'ies'} the "
                                      f"client has got no id from the server, e.g. {uncovered[:3]}"))
            vanilla_n = self.vanilla_count.get(name, 0)
            natural = {e: i for i, e in enumerate(self.entries[name][:vanilla_n])}
            moved = [(e, natural[e], new_ids[e]) for e in natural if e in new_ids and new_ids[e] != natural[e]]
            if moved:
                notes.append((WARN, f"{name}: {len(moved)} vanilla entries have other ids than the client's own, "
                                    f"e.g. {moved[:2]} (fine if the server uses them)"))
            self.ids[name] = new_ids
            self.applied[name] = new_ids
            for alias in aliases:
                notes.append((INFO, f"{name}: alias {alias} -> {aliases[alias]}"))
        return missing, notes


# --------------------------------------------------------------------------- #
# The client logic (no sockets)
# --------------------------------------------------------------------------- #
@dataclass
class Check:
    status: str
    name: str
    detail: str = ""

    def __str__(self) -> str:
        return f"{self.status:<4} {self.name}" + (f": {self.detail}" if self.detail else "")


class NeoForgeLogic:
    """The client side state machine of NeoForge's configuration exchange.

    Feed it what the server sends (`on_payload`, `on_enabled_features`,
    `on_finish_configuration`); read what the client answers from `outbox`.
    `ClientDisconnect` means the real client would disconnect itself.
    """

    def __init__(self, mod: ModSpec, vanilla: dict, lenient: bool = False, require_sync: bool = True,
                 vanilla_block_states: Optional[int] = None):
        self.mod, self.lenient, self.require_sync = mod, lenient, require_sync
        self.vanilla_block_states = vanilla_block_states
        self.registries = ClientRegistries(vanilla, mod.registries)
        mod_comps = mod.components()
        self.regs: dict[int, dict] = {
            phase: {c.id: c for c in OWN_REGISTRATIONS[phase] + mod_comps[phase]}
            for phase in (nf.CONFIGURATION, nf.PLAY)
        }
        # listener state (ClientConfigurationPacketListenerImpl)
        self.conn_type = "OTHER"
        # channel attributes (ChannelAttributes / ClientNetworkRegistry)
        self.initialized = False
        self.attr_conn_type: Optional[str] = None
        self.payload_setup: Optional[dict] = None
        self.adhoc: set = set()
        self.common: dict = {}
        # registry sync (ClientPayloadHandler)
        self.to_sync: set = set()
        self.synced: dict = {}
        self.sync_acked = False
        self.sync_count = 0
        self.failure_reasons: dict = {}
        self.block_state_ranges: list = []
        self.server_brand: Optional[str] = None
        self.negotiation_ignored = False
        # bookkeeping
        self.outbox: list = []
        self.checks: list[Check] = []
        self.sequence: list = []     # (direction, channel, size)
        self.finished = False
        self.config_files: dict = {}
        self.server_datamaps: dict = {}

    # ----------------------------------------------------------- bookkeeping -- #
    def check(self, status: str, name: str, detail: str = "") -> None:
        self.checks.append(Check(status, name, detail))

    def fail(self, name: str, message: str) -> "ClientDisconnect":
        self.check(FAIL, name, message)
        return ClientDisconnect(message)

    def _incompatible(self, what: str) -> str:
        return f"Incompatible client! Multiplayer is only available on NeoForge {NEOFORGE_VERSION} ({what})"

    # --------------------------------------------------------------- sending -- #
    def has_channel(self, phase: int, channel: str) -> bool:
        """NetworkRegistry.hasChannel"""
        if self.payload_setup is not None and channel in self.payload_setup.get(phase, {}):
            return True
        if channel in self.common.get(phase, set()):
            return True
        return channel in self.adhoc

    def send(self, channel: str, data: bytes, phase: int = nf.CONFIGURATION) -> None:
        """ClientCommonPacketListenerImpl.send -> NetworkRegistry.checkPacket"""
        if channel not in nf.BUILTIN and not channel.startswith("minecraft:") \
                and not self.has_channel(phase, channel):
            raise self.fail(
                "checkPacket",
                f"java.lang.UnsupportedOperationException: Payload {channel} may not be sent to the server! "
                f"(the server did not announce it with minecraft:register; announced: {sorted(self.adhoc)})")
        self.sequence.append(("C2S", channel, len(data)))
        self.outbox.append((channel, data))

    def _initial_listening(self) -> list:
        """ClientNetworkRegistry.sendInitialListeningChannels"""
        own = [c.id for c in self.regs[nf.CONFIGURATION].values()
               if c.optional and c.flow in (None, nf.CLIENTBOUND)]
        return nf.BUILTIN + own

    def _send_initial_listening(self) -> None:
        self.send(nf.MC_REGISTER, nf.encode_register(self._initial_listening()))

    # ------------------------------------------------------ classification ---- #
    def _initialize_other(self, trigger: str) -> None:
        """ClientNetworkRegistry.initializeOtherConnection"""
        if self.conn_type != "OTHER":
            return
        if self.initialized:
            return
        self.initialized = True
        self.payload_setup = {}
        self.attr_conn_type = self.conn_type
        self.check(INFO, "classification",
                   f"the server is treated as NOT NeoForge (trigger: {trigger}); channels are ad hoc only")
        # negotiate against an empty server: any non-optional registration aborts
        for phase, comps in self.regs.items():
            for comp in comps.values():
                if not comp.optional:
                    raise self.fail(
                        "vanilla-server compatibility",
                        "You are trying to connect to a server that is not running NeoForge, but you have mods "
                        f"that require it. A connection could not be established. (payload {comp.id} is not optional)")
        if any(e.get("check") in ("SERVERBOUND", "BIDIRECTIONAL") for e in self.mod.extended_enums):
            raise self.fail("extensible enums", "This client does not support vanilla servers as it has "
                                                "extended enums used in serverbound networking")
        if self.mod.feature_flags:
            raise self.fail("feature flags", "This client does not support vanilla servers as it has custom "
                                             "FeatureFlags")
        self._send_initial_listening()

    def _initialize_neoforge(self, setup: dict) -> None:
        """ClientNetworkRegistry.initializeNeoForgeConnection"""
        if self.initialized:
            self.negotiation_ignored = True
            self.check(INFO, "neoforge:network",
                       "ignored: the connection was already initialised as non-NeoForge (the server's brand "
                       "came before its neoforge:register query); channels stay ad hoc")
            return
        self.initialized = True
        self.payload_setup = setup
        self.attr_conn_type = self.conn_type
        self.check(PASS, "neoforge:network", "payload setup stored; connection is NeoForge")
        listening = list(self._initial_listening_set()) + list(setup.get(nf.CONFIGURATION, {}))
        self.send(nf.MC_REGISTER, nf.encode_register(listening))

    def _initial_listening_set(self) -> list:
        return list(nf.BUILTIN)

    # ------------------------------------------------------------- inputs ---- #
    def on_enabled_features(self) -> None:
        """handleEnabledFeatures: a fallback detection layer for vanilla servers"""
        self._initialize_other("update_enabled_features")

    def on_payload(self, channel: str, data: bytes) -> None:
        """ClientConfigurationPacketListenerImpl.handleCustomPayload, then the common one."""
        self.sequence.append(("S2C", channel, len(data)))
        if channel == nf.MC_REGISTER:
            try:
                names = nf.decode_register(data)
            except ProtocolError as e:
                raise self.fail("minecraft:register", f"malformed: {e}")
            self.adhoc |= set(names)
            if not self.initialized:
                # handled first so implementations that only send it once are not ignored
                self._send_initial_listening()
            return
        if channel == nf.NF_QUERY:
            self.conn_type = "NEOFORGE"
            self.check(INFO, "neoforge:register", "query received: the listener now counts as NeoForge")
            self.send(nf.NF_QUERY, nf.encode_query({
                phase: list(self.regs[phase].values()) for phase in (nf.CONFIGURATION, nf.PLAY)}))
            return
        if channel == nf.NF_NETWORK:
            try:
                setup = nf.decode_setup(data)
            except ProtocolError as e:
                raise self.fail("neoforge:network", f"malformed: {e}")
            self._initialize_neoforge(setup)
            return
        if channel == nf.NF_SETUP_FAILED:
            try:
                self.failure_reasons = nf.decode_setup_failed(data)
            except ProtocolError as e:
                raise self.fail("neoforge:modded_network_setup_failed", f"malformed: {e}")
            self.check(INFO, "setup failed", f"the server reported {self.failure_reasons}")
            return
        if channel == nf.MC_BRAND:
            try:
                self.server_brand = Buf(data).string()
            except ProtocolError:
                self.server_brand = None
            if self.conn_type == "OTHER":
                self._initialize_other("minecraft:brand")
            return
        if channel == nf.MC_UNREGISTER:
            self.adhoc -= set(nf.decode_register(data))
            return
        if channel == nf.C_VERSION:
            return self._on_common_version(data)
        if channel == nf.C_REGISTER:
            return self._on_common_register(data)
        if channel.startswith("minecraft:"):
            return    # vanilla payloads (and DiscardedPayload) are not modded
        self._on_modded(channel, data)

    def on_finish_configuration(self) -> None:
        """handleConfigurationFinished (before the client sends finish_configuration)"""
        if self.conn_type == "OTHER":
            self._initialize_other("finish_configuration")
        self.finished = True
        setup = self.payload_setup
        if setup is None:
            self.check(WARN, "onConfigurationFinished", "no payload setup: the client sends no register/unregister")
            return
        self.send(nf.MC_UNREGISTER, nf.encode_register(
            self._initial_listening_set() + list(setup.get(nf.CONFIGURATION, {}))))
        register = [nf.MC_REGISTER, nf.MC_UNREGISTER]
        if self.conn_type == "NEOFORGE":
            register.append(nf.NF_QUERY)
        else:
            register += [c.id for c in self.regs[nf.PLAY].values() if c.optional and c.flow in (None, CB)]
        self.send(nf.MC_REGISTER, nf.encode_register(register))

    # ----------------------------------------------------- modded payloads ---- #
    def _on_modded(self, channel: str, data: bytes) -> None:
        """ClientNetworkRegistry.handleModdedPayload"""
        reg = self.regs[nf.CONFIGURATION].get(channel)
        if reg is None:
            self.check(INFO, f"payload {channel}", "no registration on this client: discarded like vanilla does")
            return
        if reg.flow is not None and reg.flow != CB:
            self.check(WARN, f"payload {channel}", "registered for the other direction; refusing to decode")
            return
        if self.payload_setup is None:
            raise self.fail("payload setup",
                            f"multiplayer.disconnect.incompatible: {self._incompatible('No Payload Setup')} "
                            f"- {channel} arrived before the connection was classified")
        in_setup = channel in self.payload_setup.get(nf.CONFIGURATION, {})
        adhoc_readable = reg.optional
        if not in_setup and not adhoc_readable:
            raise self.fail("channel", f"multiplayer.disconnect.incompatible: "
                                       f"{self._incompatible('No Channel for ' + channel)}")
        handler = self.HANDLERS.get(channel)
        if handler is None:
            raise self.fail("handler", f"multiplayer.disconnect.incompatible: "
                                       f"{self._incompatible('No Handler for ' + channel)}")
        try:
            handler(self, data)
        except ProtocolError as e:
            raise self.fail(channel, f"Internal Exception: Failed decoding custom payload {channel}: {e}")

    def _on_common_version(self, data: bytes) -> None:
        try:
            versions = nf.decode_common_version(data)
        except ProtocolError as e:
            raise self.fail("c:version", f"malformed: {e}")
        if 1 not in versions:
            raise self.fail("c:version", "Unsupported common network version. This installation of NeoForge only "
                                         "supports: 1")
        self.check(PASS, "c:version", f"server versions {versions}")
        self.send(nf.C_VERSION, nf.encode_common_version([1]))

    def _on_common_register(self, data: bytes) -> None:
        try:
            version, phase, channels = nf.decode_common_register(data)
        except ProtocolError as e:
            raise self.fail("c:register", f"malformed: {e}")
        self.common[phase] = set(channels)
        self.check(PASS, "c:register", f"server receives {sorted(channels)} in {nf.PHASE_ID[phase]}")
        play = [c.id for c in self.regs[nf.PLAY].values() if c.optional and c.flow in (None, CB)]
        self.send(nf.C_REGISTER, nf.encode_common_register(1, nf.PLAY, play))

    # --- handlers of the payloads NeoForge registers --------------------------- #
    def _h_sync_start(self, data: bytes) -> None:
        names = nf.decode_sync_start(data)
        self.to_sync |= set(names)
        self.synced.clear()
        self.check(INFO, "sync start", f"server will send {names}")

    def _h_registry(self, data: bytes) -> None:
        name, ids, aliases = nf.decode_registry(data)
        self.synced[name] = (ids, aliases)
        self.to_sync.discard(name)

    def _check_block_states(self) -> None:
        """The client numbers block states by walking the block registry in id order and appending the
        states of each block (NeoForgeRegistryCallbacks.BlockCallbacks). A modded block therefore has
        its states after all vanilla ones, in the order of Java's StateDefinition: the properties
        sorted by name, the first the most significant, the values in declaration order."""
        ids = self.registries.applied.get("minecraft:block")
        if not self.mod.block_states or ids is None or self.vanilla_block_states is None:
            return
        vanilla_n = self.registries.vanilla_count.get("minecraft:block", 0)
        mod_blocks = sorted((i, k) for k, i in ids.items() if k in self.mod.block_states)
        low = [(k, i) for i, k in mod_blocks if i < vanilla_n]
        if low:
            raise self.fail("block states", f"{low[0][0]} has the id {low[0][1]}, inside the {vanilla_n} vanilla "
                                            "blocks: every state after it would be numbered differently")
        nxt, parts = self.vanilla_block_states, []
        for _, key in mod_blocks:
            props = self.mod.block_states[key]["properties"]
            count = 1
            for name in sorted(props):
                count *= len(props[name])
            parts.append(f"{key} states {nxt}..{nxt + count - 1} ({count}, properties {sorted(props)})")
            nxt += count
        self.block_state_ranges = parts
        if parts:
            self.check(PASS, "block states", "; ".join(parts))

    def _h_sync_completed(self, data: bytes) -> None:
        if data:
            raise ProtocolError(f"{len(data)} byte(s) extra after reading the payload")
        if self.to_sync:
            raise self.fail("registry sync", "Not all expected registries were received from the server! "
                                             f"(missing: {', '.join(sorted(self.to_sync))})")
        missing, notes = self.registries.apply(self.synced, self.lenient)
        for status, text in notes:
            self.check(status, "registry sync", text)
        if missing:
            shown = ", ".join(missing)
            raise self.fail("registry sync", f"The server sent registries with unknown keys: {shown}")
        bad = [n for s, n in notes if s == FAIL]
        if bad:
            # the real client would accept this and break later; this checker refuses it now
            raise ClientDisconnect("registry sync verification failed (stricter than NeoForge): " + "; ".join(bad))
        counts = ", ".join(f"{n} ({len(i)})" for n, i in self.registries.applied.items())
        self.check(PASS, "registry sync", f"applied {len(self.synced)} registr{'y' if len(self.synced) == 1 else 'ies'}: {counts}")
        self._check_block_states()
        self.sync_count = len(self.synced)
        self.to_sync.clear()
        self.synced.clear()
        self.sync_acked = True
        self.send(nf.SYNC_COMPLETED, b"")

    def _h_datamaps(self, data: bytes) -> None:
        known = nf.decode_known_datamaps(data)
        self.server_datamaps = known
        ours = {(r, d["id"]) for d in self.mod.data_maps if d.get("mandatory")
                for r in [nf.normalize_id(d["registry"])]}
        theirs = {(r, did) for r, entries in known.items() for did, mandatory in entries if mandatory}
        parts = []
        if ours - theirs:
            parts.append("Cannot connect to server as it is missing mandatory registry data maps present on the "
                         "client: " + ", ".join(f"{d} ({r})" for r, d in sorted(ours - theirs)))
        if theirs - ours:
            parts.append("Cannot connect to server as it has mandatory registry data maps not present on the "
                         "client: " + ", ".join(f"{d} ({r})" for r, d in sorted(theirs - ours)))
        if parts:
            raise self.fail("data maps", "\n".join(parts))
        mine = {r: list(ids) for r, ids in OWN_DATA_MAPS.items()}
        for d in self.mod.data_maps:
            mine.setdefault(nf.normalize_id(d["registry"]), []).append(nf.normalize_id(d["id"]))
        self.check(PASS, "data maps", "mandatory data maps agree")
        self.send(nf.DATAMAPS_REPLY, nf.encode_datamaps_reply(mine))

    def _h_enums(self, data: bytes) -> None:
        remote = {e.class_name: e for e in nf.decode_enum_data(data)}
        local = {e["class"]: e for e in self.mod.extended_enums}
        problems = []
        for cls in sorted(set(local) | set(remote)):
            l, r = local.get(cls), remote.get(cls)
            l_ext = l is not None
            r_ext = r is not None and r.extension is not None
            if (l is None and r_ext) or (r is None and l_ext):
                problems.append(f"{cls}: extensible on one side only")
                continue
            if not l_ext and not r_ext:
                continue
            if l["check"] != r.network_check:
                problems.append(f"{cls}: mismatched NetworkCheck")
            elif (l["vanilla"], l["total"]) != r.extension[:2] or list(l["entries"]) != r.extension[2]:
                problems.append(f"{cls}: set of entries does not match")
        if problems:
            raise self.fail("extensible enums", "The set of values added to extensible enums on the client and "
                                                "server do not match. " + "; ".join(problems))
        self.check(PASS, "extensible enums", "match")
        self.send(nf.ENUM_ACK, b"")

    def _h_flags(self, data: bytes) -> None:
        remote, local = set(nf.decode_flags(data)), set(nf.normalize_id(f) for f in self.mod.feature_flags)
        if remote != local:
            raise self.fail("feature flags", "The server and client have different sets of custom FeatureFlags: "
                                             f"server-only {sorted(remote - local)}, client-only {sorted(local - remote)}")
        self.check(PASS, "feature flags", "match")
        self.send(nf.FLAGS_ACK, b"")

    def _h_config_file(self, data: bytes) -> None:
        name, contents = nf.decode_config_file(data)
        self.config_files[name] = contents
        self.check(INFO, "config file", f"{name} ({len(contents)} bytes)")

    HANDLERS = {
        nf.SYNC_START: _h_sync_start,
        nf.SYNC_REGISTRY: _h_registry,
        nf.SYNC_COMPLETED: _h_sync_completed,
        nf.DATAMAPS: _h_datamaps,
        nf.ENUM_DATA: _h_enums,
        nf.FLAGS: _h_flags,
        nf.CONFIG_FILE: _h_config_file,
    }

    # ---------------------------------------------------------- the verdict ---- #
    def verdict(self, reached_play: bool) -> list[Check]:
        """The end-of-run checks. Returns all checks (FAIL ones decide the result)."""
        out = list(self.checks)
        if not reached_play:
            return out
        wanted = [r for r, es in self.mod.registries.items()
                  if es and r != "minecraft:creative_mode_tab" and r in self.registries.entries]
        if self.require_sync:
            if not self.sync_acked:
                out.append(Check(FAIL, "registry sync",
                                 "the server never completed a registry sync (no neoforge:frozen_registry_sync_"
                                 "completed): it does not prove it knows the mod's registry entries"))
            else:
                for registry in wanted:
                    if registry not in self.registries.applied:
                        out.append(Check(FAIL, "registry sync", f"{registry} was not synced although the mod adds "
                                                                f"{len(self.mod.registries[registry])} entries"))
                    else:
                        ids = self.registries.applied[registry]
                        mod_ids = [ids.get(e) for e in self.mod.registries[registry]]
                        if any(i is None for i in mod_ids):
                            out.append(Check(WARN if self.lenient else FAIL, "registry sync",
                                             f"{registry}: some mod entries got no id"))
                        else:
                            out.append(Check(PASS, f"mod ids {registry}",
                                             f"{len(mod_ids)} entries -> ids {min(mod_ids)}..{max(mod_ids)}"))
        if self.conn_type == "NEOFORGE" and self.initialized and self.attr_conn_type == "OTHER":
            out.append(Check(WARN, "classification", "the listener is NeoForge but the channel attributes say "
                                                      "other: the server sent its brand before the query"))
        return out


# --------------------------------------------------------------------------- #
# The socket client
# --------------------------------------------------------------------------- #
@dataclass
class NeoOptions(Options):
    mod_path: str = DEFAULT_MOD
    vanilla_path: str = DEFAULT_VANILLA
    brand: str = "neoforge"
    ack: bool = False
    send_ping: bool = False
    lenient: bool = False
    require_sync: bool = True


@dataclass
class NeoResult(Result):
    checks: list = field(default_factory=list)
    sequence: list = field(default_factory=list)
    classification: str = ""
    report: str = ""


class NeoForgeClient(ModbridgeClient):
    """ModbridgeClient with the NeoForge client mod's behaviour in the configuration phase."""

    def __init__(self, options: NeoOptions, logic: Optional[NeoForgeLogic] = None):
        super().__init__(options)
        self.logic = logic or NeoForgeLogic(ModSpec.load(options.mod_path), load_vanilla(options.vanilla_path),
                                            lenient=options.lenient, require_sync=options.require_sync,
                                            vanilla_block_states=load_vanilla_state_count(options.vanilla_path))
        self.res = NeoResult(ok=False, message="not started")

    # what a NeoForge client sends right after entering CONFIG: brand and client information only
    def _send_config_hello(self) -> None:
        o = self.o
        self.send(2, write_string(nf.MC_BRAND) + write_string(o.brand), f"channel={nf.MC_BRAND}")
        info = (write_string("en_us") + bytes([8]) + write_varint(0) + b"\x01" + bytes([0x7F]) + write_varint(1)
                + b"\x00\x01" + write_varint(0))
        self.send(0, info, "client_information en_us")

    def send_plugin_message(self, channel: str, data: bytes) -> None:
        pid = 2 if self.state == CONFIG else 22
        self.send(pid, write_string(channel) + data, f"channel={channel} data={data[:48].hex()}")

    def _flush(self) -> None:
        out, self.logic.outbox = self.logic.outbox, []
        for channel, data in out:
            self.send_plugin_message(channel, data)
            self.log("NF", f"C2S {channel} ({len(data)}B)")

    def _logic(self, fn, *args) -> None:
        try:
            fn(*args)
        except ClientDisconnect as e:
            self._flush()
            raise Failure(f"[NeoForge client disconnects] {e}")
        self._flush()

    # ----------------------------------------------------------------- config -- #
    def _configuration(self) -> None:
        o = self.o
        registries = 0
        while True:
            pid, payload = self._recv(o.config_timeout)
            buf = Buf(payload)
            name = mc_ids.S2C_CONFIG.get(pid, "?")
            registries += name == "registry_data"
            detail = ""
            if name == "custom_payload":
                channel = buf.string()
                detail = f"channel={channel} data={buf.data[buf.pos:buf.pos + 32].hex()}"
            self.log_packet(False, pid, len(payload), detail)

            if name == "custom_payload":
                data = buf.rest()
                self.log("NF", f"S2C {channel} ({len(data)}B)")
                if channel == nf.MC_BRAND:
                    self.brand_seen = True
                self._logic(self.logic.on_payload, channel, data)
            elif name == "disconnect":
                self._on_disconnect(payload)
            elif name == "keep_alive":
                self.send(4, payload, "keep_alive echo")
            elif name == "ping":
                self.send(5, payload, "pong")
            elif name == "cookie_request":
                self.send(1, write_string(buf.string()) + b"\x00", "cookie_response: none")
            elif name == "update_enabled_features":
                self._logic(self.logic.on_enabled_features)
            elif name == "select_known_packs":
                count = buf.varint()
                packs = [(buf.string(), buf.string(), buf.string()) for _ in range(count)]
                if o.known_packs == "echo":
                    answer = write_varint(count) + b"".join(
                        write_string(a) + write_string(b) + write_string(c) for a, b, c in packs)
                else:
                    answer = write_varint(0)
                self.send(7, answer, f"select_known_packs ({o.known_packs})")
            elif name == "resource_pack_push":
                pack_id = buf.uuid()
                for status, label in ((3, "accepted"), (4, "downloaded"), (0, "loaded")):
                    self.send(6, write_uuid(pack_id) + write_varint(status), f"resource_pack {label}")
            elif name == "code_of_conduct":
                self.send(9, b"", "accept_code_of_conduct")
            elif name == "transfer":
                raise Failure("server sent a transfer packet")
            elif name == "finish_configuration":
                self.log("INFO", f"configuration finished ({registries} registries)")
                self._logic(self.logic.on_finish_configuration)
                self.send(3, b"", "finish_configuration ack")
                self.state = PLAY
                self.res.reached_play = True
                return

    def _play_payload(self, channel: str, data: Buf) -> None:
        raw = data.rest()
        if channel == nf.MC_REGISTER:
            self.logic.adhoc |= set(nf.decode_register(raw))
            self.log("NF", f"server announced play channels: {nf.decode_register(raw)}")
        elif channel == nf.MC_UNREGISTER:
            self.log("NF", f"server unregistered: {nf.decode_register(raw)}")
        else:
            self.log("NF", f"play payload {channel} ({len(raw)}B)")

    # ---------------------------------------------------------------- the end ---- #
    def _finish_ok(self) -> None:
        super()._finish_ok()
        self._conclude(True)

    def run(self) -> NeoResult:
        res = super().run()
        if not res.ok or not self.res.reached_play:
            self._conclude(False)
        return res

    def _conclude(self, reached: bool) -> None:
        r: NeoResult = self.res
        checks = self.logic.verdict(reached or r.reached_play)
        r.checks = checks
        r.sequence = list(self.logic.sequence)
        r.classification = ("NeoForge (query first)" if self.logic.attr_conn_type == "NEOFORGE"
                            else "other/ad hoc (brand first)" if self.logic.attr_conn_type == "OTHER"
                            else "unclassified")
        failed = [c for c in checks if c.status == FAIL]
        if failed and r.ok:
            r.ok = False
            r.message = "NeoForge verification failed: " + "; ".join(f"{c.name}: {c.detail}" for c in failed)
        elif r.ok:
            r.message += (f", registry sync verified ({self.logic.sync_count} registries), "
                          f"classification {r.classification}")
        r.report = format_report(self.logic, r)


def format_report(logic: NeoForgeLogic, res: Result) -> str:
    lines = ["", "=== NeoForge client report ==="]
    lines.append(f"mod: {logic.mod.display_name} ({logic.mod.mod_id} {logic.mod.version}); "
                 f"server brand: {logic.server_brand!r}; classification: {getattr(res, 'classification', '')}")
    lines.append("server -> client, in order:")
    for direction, channel, size in logic.sequence:
        lines.append(f"  {direction} {channel} ({size}B)")
    lines.append("checks:")
    lines += [f"  {c}" for c in (res.checks if hasattr(res, 'checks') else logic.checks)]
    lines.append(f"RESULT: {'PASS' if res.ok else 'FAIL'} - {res.message}")
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
# Replaying a transcript of the server's messages (no socket)
# --------------------------------------------------------------------------- #
def _message_bytes(message: dict) -> bytes:
    if "z" in message:
        import base64
        import zlib
        return zlib.decompress(base64.b64decode(message["z"]))
    return bytes.fromhex(message["hex"])


def replay(transcript: dict, logic: NeoForgeLogic) -> NeoResult:
    """Feeds the server messages of a transcript to the client logic.

    transcript: {"brand": "Pumpkin" | null, "start": [{"channel", "z" | "hex"}...], "finish": [...]}
    ("z" is zlib + base64, "hex" plain hex)
    Order: the pre-brand messages (if any), server brand (if any), the start-hold messages, update_enabled_features, the finish-hold
    messages, finish_configuration.
    """
    res = NeoResult(ok=False, message="replay")
    try:
        # "preBrand": what the server sends before its brand (the full mode)
        for m in transcript.get("preBrand", []):
            logic.on_payload(m["channel"], _message_bytes(m))
        if transcript.get("brand") is not None:
            logic.on_payload(nf.MC_BRAND, write_string(transcript["brand"]))
        for m in transcript["start"]:
            logic.on_payload(m["channel"], _message_bytes(m))
        logic.on_enabled_features()
        for m in transcript.get("finish", []):
            logic.on_payload(m["channel"], _message_bytes(m))
        logic.on_finish_configuration()
        res.reached_play = True
        res.ok = True
        res.message = "replayed to the end of the configuration"
    except ClientDisconnect as e:
        res.message = f"[NeoForge client disconnects] {e}"
    res.checks = logic.verdict(res.reached_play)
    res.sequence = list(logic.sequence)
    res.classification = logic.attr_conn_type or "unclassified"
    failed = [c for c in res.checks if c.status == FAIL]
    if failed and res.ok:
        res.ok = False
        res.message = "NeoForge verification failed: " + "; ".join(f"{c.name}: {c.detail}" for c in failed)
    res.report = format_report(logic, res)
    return res


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def add_arguments(p: argparse.ArgumentParser) -> None:
    g = p.add_argument_group("NeoForge client mod")
    g.add_argument("--neoforge-mod", nargs="?", const=DEFAULT_MOD, metavar="MOD.json",
                   help="behave like a NeoForge client with this mod (default: mods/lonsdaleite.json)")
    g.add_argument("--vanilla-registries", default=DEFAULT_VANILLA, metavar="JSON",
                   help="vanilla registry lists (packages/pumpkin_neoforge/data/vanilla_registries.json)")
    g.add_argument("--lenient", action="store_true",
                   help="downgrade the checks that are stricter than NeoForge (id gaps, entries without id)")
    g.add_argument("--no-require-sync", action="store_true",
                   help="do not fail if the server never synchronised the mod's registries")
    g.add_argument("--replay", metavar="TRANSCRIPT.json",
                   help="verify a transcript of server messages instead of connecting")


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=25565)
    p.add_argument("--username", default="NeoBot")
    p.add_argument("--protocol", type=int, default=mc_ids.PROTOCOL_VERSION)
    p.add_argument("--known-packs", choices=("empty", "echo"), default="empty")
    p.add_argument("--config-timeout", type=float, default=45.0)
    p.add_argument("--linger", type=float, default=1.0)
    p.add_argument("-v", "--verbose", action="store_true")
    p.add_argument("-q", "--quiet", action="store_true")
    add_arguments(p)
    a = p.parse_args(argv)
    mod_path = a.neoforge_mod or DEFAULT_MOD
    logic_args = dict(lenient=a.lenient, require_sync=not a.no_require_sync)
    if a.replay:
        with open(a.replay, encoding="utf-8") as f:
            transcript = json.load(f)
        logic = NeoForgeLogic(ModSpec.load(mod_path), load_vanilla(a.vanilla_registries),
                              vanilla_block_states=load_vanilla_state_count(a.vanilla_registries), **logic_args)
        res = replay(transcript, logic)
        print(res.report)
        return 0 if res.ok else 1
    options = NeoOptions(
        host=a.host, port=a.port, username=a.username, protocol=a.protocol, known_packs=a.known_packs,
        config_timeout=a.config_timeout, linger=a.linger, quiet=a.quiet, verbose=a.verbose,
        mod_path=mod_path, vanilla_path=a.vanilla_registries, lenient=a.lenient, require_sync=not a.no_require_sync)
    client = NeoForgeClient(options)
    res = client.run()
    print(res.report)
    return 0 if res.ok else 1


if __name__ == "__main__":
    sys.exit(main())
