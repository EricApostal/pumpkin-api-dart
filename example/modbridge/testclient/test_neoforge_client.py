#!/usr/bin/env python3
"""Self-test of neoforge_client.py: byte formats against the Java-made golden vectors, the client
logic rule by rule, and whole connections against neoforge_mock_server.py (no Pumpkin needed).

    python3 test_neoforge_client.py
"""

import json
import os
import unittest

import neoforge_proto as nf
from mcproto import write_string, write_varint
from neoforge_client import (CB, DEFAULT_MOD, DEFAULT_VANILLA, FAIL, WARN, ClientDisconnect, ModSpec,
                             NeoForgeClient, NeoForgeLogic, NeoOptions, load_vanilla, load_vanilla_state_count,
                             replay)
from neoforge_mock_server import NeoMockServer

HERE = os.path.dirname(os.path.abspath(__file__))
GOLDEN = os.path.normpath(os.path.join(HERE, "..", "..", "..", "packages", "pumpkin_neoforge", "test",
                                       "golden", "neoforge_codecs.txt"))
TRANSCRIPTS = os.path.join(HERE, "transcripts")

MOD = ModSpec.load(DEFAULT_MOD)
VANILLA = load_vanilla(DEFAULT_VANILLA)
VANILLA_STATES = load_vanilla_state_count(DEFAULT_VANILLA)
LC = nf.Component


def golden():
    result = {}
    with open(GOLDEN) as f:
        for line in f:
            if "=" in line and not line.startswith("ordinals"):
                k, v = line.strip().split("=", 1)
                result[k] = v
    return result


def logic(**kw) -> NeoForgeLogic:
    return NeoForgeLogic(MOD, VANILLA, vanilla_block_states=VANILLA_STATES, **kw)


def sync_messages(items=None, blocks=None, extra=None):
    """The messages of a correct registry sync for the Lonsdaleite client."""
    items = items if items is not None else VANILLA["minecraft:item"] + MOD.registries["minecraft:item"]
    blocks = blocks if blocks is not None else VANILLA["minecraft:block"] + MOD.registries["minecraft:block"]
    msgs = [(nf.SYNC_START, nf.encode_sync_start(["minecraft:item", "minecraft:block"])),
            (nf.SYNC_REGISTRY, nf.encode_registry("minecraft:item", dict(enumerate(items)))),
            (nf.SYNC_REGISTRY, nf.encode_registry("minecraft:block", dict(enumerate(blocks)))),
            (nf.SYNC_COMPLETED, b"")]
    return msgs


ANNOUNCE = nf.encode_register(nf.BUILTIN + [nf.SYNC_COMPLETED])


def adhoc_logic(**kw) -> NeoForgeLogic:
    """brand first, server announces the ack channel"""
    lg = logic(**kw)
    lg.on_payload(nf.MC_BRAND, write_string("Pumpkin"))
    lg.on_payload(nf.MC_REGISTER, ANNOUNCE)
    return lg


class GoldenVectors(unittest.TestCase):
    def test_encoders_match_the_java_vectors(self):
        g = golden()
        self.assertEqual(nf.encode_query({nf.CONFIGURATION: [LC("neoforge:frozen_registry_sync_completed", "1", None, True)]}).hex(), g["query_config_bidirectional"])
        self.assertEqual(nf.encode_query({nf.PLAY: [LC("neoforge:recipe_content", "1", CB, True)]}).hex(), g["query_play_clientbound"])
        self.assertEqual(nf.encode_query({}).hex(), g["query_empty"])
        self.assertEqual(nf.encode_query({nf.CONFIGURATION: [LC("mymod:x", "2", nf.SERVERBOUND, False)]}).hex(), g["query_config_serverbound_required"])
        self.assertEqual(nf.encode_setup({nf.CONFIGURATION: {"neoforge:frozen_registry": "1"}}).hex(), g["network_config_one"])
        self.assertEqual(nf.encode_setup({nf.PLAY: {}}).hex(), g["network_play_empty"])
        self.assertEqual(nf.encode_common_version([1]).hex(), g["common_version"])
        self.assertEqual(nf.encode_common_version([1, 300]).hex(), g["common_version_two"])
        self.assertEqual(nf.encode_common_register(1, nf.PLAY, ["c:foo"]).hex(), g["common_register_play_one"])
        self.assertEqual(nf.encode_sync_start(["minecraft:item", "minecraft:block"]).hex(), g["sync_start"])
        self.assertEqual(nf.encode_registry("minecraft:item", {0: "minecraft:air", 1: "minecraft:stone", 300: "lonsdaleite:raw_lonsdaleite"}).hex(), g["frozen_registry_item"])
        self.assertEqual(nf.encode_registry("minecraft:block", {0: "minecraft:air"}, {"old:thing": "minecraft:stone"}).hex(), g["frozen_registry_with_alias"])
        self.assertEqual(nf.encode_known_datamaps({"minecraft:item": [("neoforge:villager_compostables", False), ("mymod:tiers", True)]}).hex(), g["known_data_maps"])
        self.assertEqual(nf.encode_datamaps_reply({"minecraft:item": ["neoforge:villager_compostables"]}).hex(), g["known_data_maps_reply"])
        self.assertEqual(nf.encode_enum_data([nf.EnumEntry("net.minecraft.world.item.Rarity", "BIDIRECTIONAL")]).hex(), g["enum_data_plain"])
        self.assertEqual(nf.encode_enum_data([nf.EnumEntry("x.Y", "CLIENTBOUND", (2, 4, ["A", "B"]))]).hex(), g["enum_data_extended"])
        self.assertEqual(nf.encode_enum_data([]).hex(), g["enum_data_empty"])
        self.assertEqual(nf.encode_flags(["mymod:flag"]).hex(), g["feature_flags_one"])
        self.assertEqual(nf.encode_flags([]).hex(), g["feature_flags_empty"])
        self.assertEqual(nf.encode_config_file("neoforge-server.toml", b"a=1").hex(), g["config_file"])

    def test_decoders_round_trip(self):
        g = golden()
        self.assertEqual(nf.decode_query(bytes.fromhex(g["query_play_clientbound"]))[nf.PLAY][0], LC("neoforge:recipe_content", "1", CB, True))
        self.assertEqual(nf.decode_setup(bytes.fromhex(g["network_config_one"])), {nf.CONFIGURATION: {"neoforge:frozen_registry": "1"}})
        self.assertEqual(nf.decode_common_register(bytes.fromhex(g["common_register_play_one"])), (1, nf.PLAY, ["c:foo"]))
        name, ids, aliases = nf.decode_registry(bytes.fromhex(g["frozen_registry_with_alias"]))
        self.assertEqual((name, ids, aliases), ("minecraft:block", {0: "minecraft:air"}, {"old:thing": "minecraft:stone"}))
        self.assertEqual(nf.decode_known_datamaps(bytes.fromhex(g["known_data_maps"]))["minecraft:item"][1], ("mymod:tiers", True))
        self.assertEqual(nf.decode_enum_data(bytes.fromhex(g["enum_data_extended"]))[0].extension, (2, 4, ["A", "B"]))

    def test_malformed_input(self):
        g = golden()
        full = bytes.fromhex(g["frozen_registry_item"])
        for cut in range(len(full)):
            with self.assertRaises(Exception):
                nf.decode_registry(full[:cut])
        with self.assertRaises(Exception):
            nf.decode_registry(full + b"\x00")           # PacketDecoder: extra bytes
        with self.assertRaises(Exception):
            nf.decode_query(write_varint(1) + write_varint(9) + write_varint(0))   # unknown protocol

    def test_register_list_ignores_invalid_names(self):
        self.assertEqual(nf.decode_register(b"a:b\0A:B\0plain\0a:b\0"), ["a:b", "minecraft:plain"])


class ClassificationRules(unittest.TestCase):
    def test_brand_first_makes_it_a_non_neoforge_connection(self):
        lg = logic()
        lg.on_payload(nf.MC_BRAND, write_string("Pumpkin"))
        self.assertEqual((lg.conn_type, lg.attr_conn_type, lg.initialized), ("OTHER", "OTHER", True))
        # the client announces what it can receive, as sendInitialListeningChannels does
        (channel, data), = lg.outbox
        self.assertEqual(channel, nf.MC_REGISTER)
        announced = nf.decode_register(data)
        for expected in nf.BUILTIN + [nf.SYNC_START, nf.SYNC_REGISTRY, nf.SYNC_COMPLETED, nf.DATAMAPS, nf.ENUM_DATA, nf.FLAGS, nf.CONFIG_FILE, nf.SPLIT]:
            self.assertIn(expected, announced)
        self.assertNotIn(nf.DATAMAPS_REPLY, announced)   # serverbound only

    def test_query_before_brand_makes_it_neoforge(self):
        lg = logic()
        lg.on_payload(nf.MC_REGISTER, nf.encode_register(nf.BUILTIN))
        lg.on_payload(nf.NF_QUERY, nf.encode_query({}))
        self.assertEqual(lg.conn_type, "NEOFORGE")
        reply = [d for c, d in lg.outbox if c == nf.NF_QUERY][-1]
        query = nf.decode_query(reply)
        ids = {c.id for c in query[nf.CONFIGURATION]}
        self.assertIn(nf.SYNC_COMPLETED, ids)
        self.assertTrue(all(c.optional and c.version == "1" for c in query[nf.CONFIGURATION] + query[nf.PLAY]))
        lg.on_payload(nf.NF_NETWORK, nf.encode_setup({nf.CONFIGURATION: {nf.SYNC_REGISTRY: "1"}}))
        self.assertEqual(lg.attr_conn_type, "NEOFORGE")
        lg.on_payload(nf.MC_BRAND, write_string("NeoForge"))
        self.assertEqual(lg.attr_conn_type, "NEOFORGE")

    def test_network_after_the_brand_is_ignored(self):
        lg = logic()
        lg.on_payload(nf.MC_BRAND, write_string("Pumpkin"))
        lg.on_payload(nf.NF_QUERY, nf.encode_query({}))
        lg.on_payload(nf.NF_NETWORK, nf.encode_setup({nf.CONFIGURATION: {nf.SYNC_REGISTRY: "1"}}))
        self.assertTrue(lg.negotiation_ignored)
        self.assertEqual(lg.attr_conn_type, "OTHER")
        self.assertEqual(lg.payload_setup, {})

    def test_enabled_features_and_finish_are_fallbacks(self):
        lg = logic()
        lg.on_enabled_features()
        self.assertTrue(lg.initialized)
        lg2 = logic()
        lg2.on_finish_configuration()
        self.assertTrue(lg2.initialized)

    def test_modded_payload_before_classification_disconnects(self):
        lg = logic()
        with self.assertRaises(ClientDisconnect) as e:
            lg.on_payload(nf.SYNC_START, nf.encode_sync_start(["minecraft:item"]))
        self.assertIn("No Payload Setup", str(e.exception))

    def test_unregistered_channel_is_discarded(self):
        lg = adhoc_logic()
        lg.on_payload("othermod:thing", b"\x01")      # no registration: ignored like vanilla
        self.assertFalse(any(c.status == FAIL for c in lg.checks))

    def test_required_mod_payload_aborts_a_non_neoforge_connection(self):
        mod = ModSpec.load(DEFAULT_MOD)
        mod.payloads = [{"id": "lonsdaleite:hello", "protocols": ["play"], "flow": "clientbound", "optional": False}]
        lg = NeoForgeLogic(mod, VANILLA)
        with self.assertRaises(ClientDisconnect) as e:
            lg.on_payload(nf.MC_BRAND, write_string("Pumpkin"))
        self.assertIn("not running NeoForge", str(e.exception))

    def test_feature_flags_and_serverbound_enums_abort_vanilla_servers(self):
        mod = ModSpec.load(DEFAULT_MOD)
        mod.feature_flags = ["lonsdaleite:experimental"]
        with self.assertRaises(ClientDisconnect):
            NeoForgeLogic(mod, VANILLA).on_payload(nf.MC_BRAND, write_string("x"))
        mod = ModSpec.load(DEFAULT_MOD)
        mod.extended_enums = [{"class": "a.B", "check": "BIDIRECTIONAL", "vanilla": 1, "total": 2, "entries": ["X"]}]
        with self.assertRaises(ClientDisconnect):
            NeoForgeLogic(mod, VANILLA).on_payload(nf.MC_BRAND, write_string("x"))


class SendingRules(unittest.TestCase):
    def test_an_unannounced_channel_cannot_be_sent(self):
        lg = logic()
        lg.on_payload(nf.MC_BRAND, write_string("Pumpkin"))
        lg.outbox.clear()
        lg.on_payload(nf.SYNC_START, nf.encode_sync_start(["minecraft:item"]))
        lg.on_payload(nf.SYNC_REGISTRY, nf.encode_registry("minecraft:item", dict(enumerate(VANILLA["minecraft:item"] + MOD.registries["minecraft:item"]))))
        with self.assertRaises(ClientDisconnect) as e:
            lg.on_payload(nf.SYNC_COMPLETED, b"")
        self.assertIn("UnsupportedOperationException", str(e.exception))
        self.assertIn(nf.SYNC_COMPLETED, str(e.exception))

    def test_register_announces_the_channel(self):
        lg = adhoc_logic()
        for name, data in sync_messages():
            lg.on_payload(name, data)
        self.assertIn((nf.SYNC_COMPLETED, b""), lg.outbox)

    def test_unregister_removes_it_again(self):
        lg = adhoc_logic()
        lg.on_payload(nf.MC_UNREGISTER, nf.encode_register([nf.SYNC_COMPLETED]))
        with self.assertRaises(ClientDisconnect):
            for name, data in sync_messages():
                lg.on_payload(name, data)

    def test_register_unregister_when_the_configuration_finishes(self):
        lg = adhoc_logic()
        lg.outbox.clear()
        lg.on_finish_configuration()
        (c1, d1), (c2, d2) = lg.outbox
        self.assertEqual((c1, c2), (nf.MC_UNREGISTER, nf.MC_REGISTER))
        self.assertEqual(set(nf.decode_register(d1)), set(nf.BUILTIN))
        registered = nf.decode_register(d2)
        self.assertIn("neoforge:recipe_content", registered)       # non-NeoForge connection: its play channels
        self.assertNotIn(nf.NF_QUERY, registered)


class RegistrySync(unittest.TestCase):
    def test_correct_sync_is_acknowledged_and_ids_applied(self):
        lg = adhoc_logic()
        for name, data in sync_messages():
            lg.on_payload(name, data)
        self.assertTrue(lg.sync_acked)
        item_ids = lg.registries.applied["minecraft:item"]
        self.assertEqual(item_ids["minecraft:air"], 0)
        self.assertEqual(item_ids["lonsdaleite:lonsdaleite_wardframe"], len(VANILLA["minecraft:item"]))
        verdict = lg.verdict(True)
        self.assertFalse([c for c in verdict if c.status == FAIL], [str(c) for c in verdict])

    def test_unknown_keys_disconnect_with_the_real_message(self):
        lg = adhoc_logic()
        items = VANILLA["minecraft:item"] + MOD.registries["minecraft:item"] + ["lonsdaleite:ghost", "other:thing"]
        with self.assertRaises(ClientDisconnect) as e:
            for name, data in sync_messages(items=items):
                lg.on_payload(name, data)
        self.assertEqual(str(e.exception), "The server sent registries with unknown keys: "
                                           "ResourceKey[minecraft:item / lonsdaleite:ghost], "
                                           "ResourceKey[minecraft:item / other:thing]")

    def test_a_server_without_the_mod_is_refused_by_the_client(self):
        """A server that does not know the mod's entries sends vanilla only: the client keeps its own
        ids for the mod, which is not a failure for NeoForge but is for this verification."""
        lg = adhoc_logic()
        with self.assertRaises(ClientDisconnect) as e:
            for name, data in sync_messages(items=VANILLA["minecraft:item"], blocks=VANILLA["minecraft:block"]):
                lg.on_payload(name, data)
        self.assertIn("got no id", str(lg.checks[-1]) + str(e.exception))

    def test_lenient_mode_only_warns(self):
        lg = adhoc_logic(lenient=True)
        for name, data in sync_messages(items=VANILLA["minecraft:item"], blocks=VANILLA["minecraft:block"]):
            lg.on_payload(name, data)
        self.assertTrue(lg.sync_acked)
        self.assertTrue([c for c in lg.checks if c.status == WARN and "got no id" in c.detail])

    def test_id_gaps_fail(self):
        lg = adhoc_logic()
        items = VANILLA["minecraft:item"] + MOD.registries["minecraft:item"]
        ids = {(i if i < 3 else i + 1): e for i, e in enumerate(items)}
        with self.assertRaises(ClientDisconnect):
            lg.on_payload(nf.SYNC_START, nf.encode_sync_start(["minecraft:item"]))
            lg.on_payload(nf.SYNC_REGISTRY, nf.encode_registry("minecraft:item", ids))
            lg.on_payload(nf.SYNC_COMPLETED, b"")
        self.assertTrue([c for c in lg.checks if c.status == FAIL and "contiguous" in c.detail])

    def test_a_registry_that_was_announced_but_not_sent(self):
        lg = adhoc_logic()
        lg.on_payload(nf.SYNC_START, nf.encode_sync_start(["minecraft:item", "minecraft:block"]))
        lg.on_payload(nf.SYNC_REGISTRY, nf.encode_registry("minecraft:item", {0: "minecraft:air"}))
        with self.assertRaises(ClientDisconnect) as e:
            lg.on_payload(nf.SYNC_COMPLETED, b"")
        self.assertEqual(str(e.exception), "Not all expected registries were received from the server! (missing: minecraft:block)")

    def test_the_wardframe_states_follow_the_vanilla_states(self):
        """The client numbers the states of the block registry in id order: the wardframe's 64 states
        (six booleans, 2^6) start right after the 35723 vanilla ones."""
        self.assertEqual(VANILLA_STATES, 35723)
        lg = adhoc_logic()
        for name, data in sync_messages():
            lg.on_payload(name, data)
        self.assertTrue(lg.sync_acked)
        self.assertEqual(len(lg.block_state_ranges), 1)
        self.assertIn("lonsdaleite:lonsdaleite_wardframe states 35723..35786 (64, properties "
                      "['down', 'east', 'north', 'south', 'up', 'west'])", lg.block_state_ranges[0])
        self.assertTrue([c for c in lg.checks if c.name == "block states" and "35723..35786" in c.detail])

    def test_a_modded_block_inside_the_vanilla_ids_is_refused(self):
        """A server that puts the wardframe at an id of a vanilla block shifts the states of every
        vanilla block after it."""
        lg = adhoc_logic()
        blocks = list(VANILLA["minecraft:block"])
        # the wardframe takes the id of vanilla block 10: the vanilla blocks 10.. move up by one
        blocks.insert(10, "lonsdaleite:lonsdaleite_wardframe")
        with self.assertRaises(ClientDisconnect) as e:
            for name, data in sync_messages(blocks=blocks):
                lg.on_payload(name, data)
        self.assertIn("inside the 1286 vanilla blocks", str(e.exception))

    def test_completed_without_start_syncs_nothing_and_is_acked(self):
        lg = adhoc_logic()
        lg.on_payload(nf.SYNC_COMPLETED, b"")
        self.assertTrue(lg.sync_acked)
        verdict = lg.verdict(True)
        self.assertTrue([c for c in verdict if c.status == FAIL and "registry sync" in c.name])

    def test_unknown_custom_registry_with_entries_fails(self):
        lg = adhoc_logic()
        lg.on_payload(nf.SYNC_START, nf.encode_sync_start(["foo:bar"]))
        lg.on_payload(nf.SYNC_REGISTRY, nf.encode_registry("foo:bar", {0: "foo:x"}))
        with self.assertRaises(ClientDisconnect) as e:
            lg.on_payload(nf.SYNC_COMPLETED, b"")
        self.assertIn("Tried to applied snapshot with registry name foo:bar but was not found", str(e.exception))

    def test_unknown_empty_registry_is_ignored(self):
        lg = adhoc_logic()
        lg.on_payload(nf.SYNC_START, nf.encode_sync_start(["foo:bar"]))
        lg.on_payload(nf.SYNC_REGISTRY, nf.encode_registry("foo:bar", {}))
        lg.on_payload(nf.SYNC_COMPLETED, b"")
        self.assertTrue(lg.sync_acked)

    def test_trailing_bytes_are_a_decode_error(self):
        lg = adhoc_logic()
        with self.assertRaises(ClientDisconnect) as e:
            lg.on_payload(nf.SYNC_START, nf.encode_sync_start(["minecraft:item"]) + b"\x00")
        self.assertIn("extra", str(e.exception))


class OtherTasks(unittest.TestCase):
    def test_common_version_and_register(self):
        lg = adhoc_logic()
        lg.outbox.clear()
        lg.on_payload(nf.C_VERSION, nf.encode_common_version([1]))
        lg.on_payload(nf.C_REGISTER, nf.encode_common_register(1, nf.PLAY, []))
        self.assertEqual([c for c, _ in lg.outbox], [nf.C_VERSION, nf.C_REGISTER])
        self.assertEqual(nf.decode_common_version(lg.outbox[0][1]), [1])
        version, phase, channels = nf.decode_common_register(lg.outbox[1][1])
        self.assertEqual((version, phase), (1, nf.PLAY))
        self.assertIn("neoforge:recipe_content", channels)

    def test_unsupported_common_version(self):
        lg = adhoc_logic()
        with self.assertRaises(ClientDisconnect) as e:
            lg.on_payload(nf.C_VERSION, nf.encode_common_version([7]))
        self.assertIn("Unsupported common network version", str(e.exception))

    def test_mandatory_data_maps(self):
        mod = ModSpec.load(DEFAULT_MOD)
        mod.data_maps = [{"registry": "minecraft:item", "id": "lonsdaleite:tiers", "mandatory": True}]
        lg = NeoForgeLogic(mod, VANILLA)
        lg.on_payload(nf.MC_BRAND, write_string("x"))
        lg.on_payload(nf.MC_REGISTER, nf.encode_register([nf.DATAMAPS_REPLY]))
        with self.assertRaises(ClientDisconnect) as e:
            lg.on_payload(nf.DATAMAPS, nf.encode_known_datamaps({}))
        self.assertIn("missing mandatory registry data maps present on the client: lonsdaleite:tiers (minecraft:item)", str(e.exception))
        lg2 = NeoForgeLogic(mod, VANILLA)
        lg2.on_payload(nf.MC_BRAND, write_string("x"))
        lg2.on_payload(nf.MC_REGISTER, nf.encode_register([nf.DATAMAPS_REPLY]))
        with self.assertRaises(ClientDisconnect) as e:
            lg2.on_payload(nf.DATAMAPS, nf.encode_known_datamaps({"minecraft:block": [("x:y", True)]}))
        self.assertIn("mandatory registry data maps not present on the client", str(e.exception))

    def test_data_maps_match_and_reply(self):
        lg = adhoc_logic()
        lg.on_payload(nf.MC_REGISTER, nf.encode_register([nf.DATAMAPS_REPLY]))
        lg.outbox.clear()
        lg.on_payload(nf.DATAMAPS, nf.encode_known_datamaps({"minecraft:item": [("neoforge:villager_compostables", False)]}))
        (channel, data), = lg.outbox
        self.assertEqual(channel, nf.DATAMAPS_REPLY)
        self.assertIn("neoforge:waxables", nf.decode_datamaps_reply(data)["minecraft:block"])

    def test_feature_flags_must_match(self):
        lg = adhoc_logic()
        lg.on_payload(nf.MC_REGISTER, nf.encode_register([nf.FLAGS_ACK]))
        lg.on_payload(nf.FLAGS, nf.encode_flags([]))
        self.assertIn((nf.FLAGS_ACK, b""), lg.outbox)
        with self.assertRaises(ClientDisconnect):
            lg.on_payload(nf.FLAGS, nf.encode_flags(["a:b"]))

    def test_extensible_enums(self):
        lg = adhoc_logic()
        lg.on_payload(nf.MC_REGISTER, nf.encode_register([nf.ENUM_ACK]))
        lg.on_payload(nf.ENUM_DATA, nf.encode_enum_data([nf.EnumEntry("net.minecraft.world.item.Rarity", "BIDIRECTIONAL")]))
        self.assertIn((nf.ENUM_ACK, b""), lg.outbox)
        with self.assertRaises(ClientDisconnect) as e:
            lg.on_payload(nf.ENUM_DATA, nf.encode_enum_data([nf.EnumEntry("a.B", "CLIENTBOUND", (1, 2, ["X"]))]))
        self.assertIn("extensible enums", str(e.exception))


class WholeConnections(unittest.TestCase):
    def run_client(self, scenario, **kw):
        server = NeoMockServer(scenario)
        try:
            options = NeoOptions(port=server.port, quiet=True, linger=0.2, config_timeout=6, **kw)
            return NeoForgeClient(options).run(), server
        finally:
            server.close()

    def assert_fail(self, res, *parts):
        self.assertFalse(res.ok, res.message)
        for part in parts:
            self.assertIn(part, res.message)

    def test_adhoc_sync_passes(self):
        res, server = self.run_client("adhoc")
        self.assertTrue(res.ok, res.message + "\n" + res.report)
        self.assertTrue(res.reached_play)
        self.assertEqual(res.classification, "other/ad hoc (brand first)")
        self.assertIn(("C2S", nf.SYNC_COMPLETED), server.seen)
        # the client announced itself before anything else and answered the c: handshake
        channels = [c for _, c in server.seen]
        self.assertLess(channels.index(nf.MC_REGISTER), channels.index(nf.SYNC_COMPLETED))
        self.assertIn(nf.C_VERSION, channels)
        self.assertIn("mod ids minecraft:item", res.report)
        self.assertIsNone(server.error)

    def test_query_first_is_the_real_neoforge_order(self):
        res, server = self.run_client("query-first")
        self.assertTrue(res.ok, res.message + "\n" + res.report)
        self.assertEqual(res.classification, "NeoForge (query first)")
        channels = [c for _, c in server.seen]
        self.assertLess(channels.index(nf.NF_QUERY), channels.index(nf.SYNC_COMPLETED))

    def test_brand_then_query_ignores_the_negotiation(self):
        res, _ = self.run_client("brand-then-query")
        self.assertTrue(res.ok, res.message + "\n" + res.report)
        self.assertIn("ignored", res.report)
        self.assertEqual(res.classification, "other/ad hoc (brand first)")

    def test_unknown_key(self):
        res, _ = self.run_client("unknown-key")
        self.assert_fail(res, "The server sent registries with unknown keys", "lonsdaleite:ghost_item")

    def test_missing_entry_is_caught_strictly(self):
        res, _ = self.run_client("missing-entry")
        self.assert_fail(res, "got no id")

    def test_missing_entry_lenient_warns(self):
        res, _ = self.run_client("missing-entry", lenient=True)
        self.assertTrue(res.ok, res.message)
        self.assertIn("WARN", res.report)

    def test_id_gap(self):
        res, _ = self.run_client("id-gap")
        self.assert_fail(res, "contiguous")

    def test_server_that_does_not_announce_the_ack_channel(self):
        res, _ = self.run_client("no-announce")
        self.assert_fail(res, "UnsupportedOperationException", nf.SYNC_COMPLETED)

    def test_payload_before_classification(self):
        res, _ = self.run_client("sync-first")
        self.assert_fail(res, "No Payload Setup")

    def test_no_sync_does_not_prove_anything(self):
        res, _ = self.run_client("no-sync")
        self.assert_fail(res, "never completed a registry sync")
        res2, _ = self.run_client("no-sync", require_sync=False)
        self.assertTrue(res2.ok, res2.message)

    def test_partial_sync(self):
        res, _ = self.run_client("partial-sync")
        self.assert_fail(res, "Not all expected registries were received", "minecraft:block")

    def test_trailing_bytes(self):
        res, _ = self.run_client("trailing-bytes")
        self.assert_fail(res, "extra")

    def test_bad_common_version(self):
        res, _ = self.run_client("bad-common")
        self.assert_fail(res, "Unsupported common network version")


class Transcripts(unittest.TestCase):
    """Transcripts of the Dart library (packages/pumpkin_neoforge, tool/dump_transcripts.dart)."""

    def load(self, name):
        path = os.path.join(TRANSCRIPTS, name)
        if not os.path.exists(path):
            self.skipTest(f"{name} not generated")
        with open(path) as f:
            return json.load(f)

    def test_dart_adhoc_transcript_is_accepted(self):
        res = replay(self.load("lonsdaleite_adhoc.json"), logic())
        self.assertTrue(res.ok, res.message + "\n" + res.report)
        self.assertEqual(res.classification, "OTHER")

    def test_dart_full_transcript_after_the_brand(self):
        res = replay(self.load("lonsdaleite_full.json"), logic())
        self.assertTrue(res.ok, res.message + "\n" + res.report)

    def test_dart_full_transcript_before_the_brand(self):
        t = self.load("lonsdaleite_full.json")
        t["brand"] = None
        # query first: the brand arrives after the negotiation (like real NeoForge)
        lg = logic()
        res = replay(t, lg)
        self.assertTrue(res.ok, res.message + "\n" + res.report)
        self.assertEqual(lg.attr_conn_type, "NEOFORGE")


if __name__ == "__main__":
    unittest.main(verbosity=2)
