#!/usr/bin/env python3
"""An independent encoder of the Lonsdaleite item components, written from
Pumpkin's Rust readers (crates/pumpkin-protocol/src/codec/data_component.rs,
the `DataComponentCodec::deserialize` of each component) and NOT from the Dart
codec in packages/pumpkin_api, to produce the golden bytes that
test/component_codec_test.dart compares the Dart output with.

    python3 tool/golden_components.py [--assets <Pumpkin>/assets] > test/fixtures/component_bytes.json

Registry ids are read straight from Pumpkin's assets (sounds.json list order,
blocks.json ids, attributes.json ids, the sorted damage_type directory).
Every item's server view (components + server_components) is encoded; the
components the host has no reader for are left out, as the plugin does.
"""
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = "/Users/eric/Documents/development/languages/rust/Pumpkin/assets"
for i, a in enumerate(sys.argv):
    if a == "--assets":
        ASSETS = sys.argv[i + 1]


def load(name):
    with open(os.path.join(ASSETS, name)) as f:
        return json.load(f)


SOUNDS = load("sounds.json")
BLOCKS = {b["name"]: b["id"] for b in load("blocks.json")["blocks"]}
ATTRS = {k: v["id"] for k, v in load("attributes.json").items()}
DAMAGE = sorted(
    f[:-5] for f in os.listdir(os.path.join(ASSETS, "datapack/data/minecraft/damage_type"))
    if f.endswith(".json")
)
UNREADABLE = {"minecraft:interact_animation", "minecraft:block_transformer"}


def bare(key):
    return key[len("minecraft:"):] if key.startswith("minecraft:") else key


def varint(n):
    n &= 0xFFFFFFFF
    out = bytearray()
    while n > 0x7F:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    out.append(n)
    return bytes(out)


def string(s):
    b = s.encode()
    return varint(len(b)) + b


def f32(x):
    return struct.pack(">f", x)


def f64(x):
    return struct.pack(">d", x)


def boolean(b):
    return b"\x01" if b else b"\x00"


def sound(key):  # Holder<SoundEvent>: IdOr, id + 1
    return varint(SOUNDS.index(bare(key)) + 1)


def optional(value, enc):
    return b"\x00" if value is None else b"\x01" + enc(value)


def holder_set(value, ids):
    if isinstance(value, str) and value.startswith("#"):
        return varint(0) + string(value[1:])
    keys = [value] if isinstance(value, str) else value
    return varint(len(keys) + 1) + b"".join(varint(ids(k)) for k in keys)


def item_ids(key):
    raise KeyError("no direct item ids are used by the manifest: " + key)


SLOTS = {"mainhand": 0, "feet": 1, "legs": 2, "chest": 3, "head": 4, "offhand": 5, "body": 6, "saddle": 7}
ATTR_SLOTS = {"any": 0, "mainhand": 1, "offhand": 2, "hand": 3, "feet": 4, "legs": 5,
              "chest": 6, "head": 7, "armor": 8, "body": 9, "saddle": 10}
OPS = {"add_value": 0, "add_multiplied_base": 1, "add_multiplied_total": 2}


def encode(name, v):
    if name == "minecraft:max_stack_size" or name in (
            "minecraft:max_damage", "minecraft:damage", "minecraft:repair_cost"):
        return varint(v)
    if name == "minecraft:enchantable":
        return varint(v["value"])
    if name == "minecraft:rarity":
        return varint(["common", "uncommon", "rare", "epic"].index(v))
    if name == "minecraft:item_model":
        return string(v)
    if name == "minecraft:item_name":
        return string(v["translate"])
    if name == "minecraft:lore":
        assert v == []
        return varint(0)
    if name == "minecraft:enchantments":
        assert v == {}
        return varint(0)
    if name == "minecraft:repairable":
        return holder_set(v["items"], item_ids)
    if name == "minecraft:tool":
        out = varint(len(v["rules"]))
        for r in v["rules"]:
            out += holder_set(r["blocks"], lambda k: BLOCKS[bare(k)])
            out += optional(r.get("speed"), f32)
            out += optional(r.get("correct_for_drops"), boolean)
        out += f32(v.get("default_mining_speed", 1.0))
        out += varint(v.get("damage_per_block", 1))
        out += boolean(v.get("can_destroy_blocks_in_creative", True))
        return out
    if name == "minecraft:weapon":
        return varint(v.get("item_damage_per_attack", 1)) + f32(v.get("disable_blocking_for_seconds", 0.0))
    if name == "minecraft:equippable":
        out = varint(SLOTS[v["slot"]])
        out += sound(v.get("equip_sound", "minecraft:item.armor.equip_generic"))
        out += optional(v.get("asset_id"), string)
        out += optional(v.get("camera_overlay"), string)
        assert "allowed_entities" not in v
        out += b"\x00"
        for k, d in (("dispensable", True), ("swappable", True), ("damage_on_hurt", True),
                     ("equip_on_interact", False), ("can_be_sheared", False)):
            out += boolean(v.get(k, d))
        out += sound(v.get("shearing_sound", "minecraft:item.shears.snip"))
        return out
    if name == "minecraft:attribute_modifiers":
        out = varint(len(v))
        for m in v:
            out += varint(ATTRS[bare(m["type"])]) + string(m["id"]) + f64(m["amount"])
            out += varint(OPS[m["operation"]]) + varint(ATTR_SLOTS[m["slot"]]) + varint(0)
        return out
    if name == "minecraft:use_effects":
        return (boolean(v.get("can_sprint", False)) + boolean(v.get("interact_vibrations", True))
                + f32(v.get("speed_multiplier", 0.2)))
    if name == "minecraft:tooltip_display":
        assert v == {}
        return boolean(False) + varint(0)
    if name == "minecraft:break_sound":
        return sound(v)
    if name == "minecraft:attack_animation":
        # Pumpkin's SwingAnimationType::from_id: whack 0, stab 1, none 2
        return varint({"whack": 0, "stab": 1, "none": 2}[v.get("type", "whack")]) + varint(v.get("duration", 6))
    if name == "minecraft:attack_range":
        d = {"min_reach": 0.0, "max_reach": 3.0, "min_creative_reach": 0.0,
             "max_creative_reach": 5.0, "hitbox_margin": 0.3, "mob_factor": 1.0}
        d.update(v)
        return b"".join(f32(d[k]) for k in ("min_reach", "max_reach", "min_creative_reach",
                                            "max_creative_reach", "hitbox_margin", "mob_factor"))
    if name == "minecraft:minimum_attack_charge":
        return f32(v)
    if name == "minecraft:damage_type":
        return varint(DAMAGE.index(bare(v)))
    if name == "minecraft:piercing_weapon":
        return (boolean(v.get("deals_knockback", True)) + boolean(v.get("dismounts", False))
                + optional(v.get("sound"), sound) + optional(v.get("hit_sound"), sound))
    if name == "minecraft:kinetic_weapon":
        def cond(c):
            return varint(c["max_duration_ticks"]) + f32(c.get("min_speed", 0.0)) + f32(c.get("min_relative_speed", 0.0))
        return (varint(v.get("contact_cooldown_ticks", 10)) + varint(v.get("delay_ticks", 0))
                + optional(v.get("dismount_conditions"), cond)
                + optional(v.get("knockback_conditions"), cond)
                + optional(v.get("damage_conditions"), cond)
                + f32(v.get("forward_movement", 0.0)) + f32(v.get("damage_multiplier", 1.0))
                + optional(v.get("sound"), sound) + optional(v.get("hit_sound"), sound))
    raise KeyError(name)


def main():
    with open(os.path.join(HERE, "..", "data", "manifest.json")) as f:
        manifest = json.load(f)
    out = {}
    for item in manifest["items"]:
        components = dict(item["components"])
        components.update(item.get("server_components") or {})
        out[item["id"]] = {
            name: encode(name, value).hex()
            for name, value in components.items() if name not in UNREADABLE
        }
    json.dump(out, sys.stdout, indent=1, sort_keys=True)
    print()


main()
