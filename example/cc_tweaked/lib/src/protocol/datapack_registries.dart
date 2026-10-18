// CC: Tweaked's datapack registries (`computercraft:turtle_upgrade` and
// `computercraft:pocket_upgrade`) as the `minecraft:registry_data` packets the
// client builds its creative tab from.
//
// What the client does (CC: Tweaked `ModRegistry.CreativeTabs`, mc-26.3):
//
//     addTurtle(out, turtle, context.holders()):
//         out.accept(new ItemStack(turtle));
//         registries.lookupOrThrow(ITurtleUpgrade.REGISTRY).listElements().forEach(x ->
//             out.accept(createStack(turtle, RIGHT_TURTLE_UPGRADE, UpgradeData.ofDefault(x)), ...));
//
// `context.holders()` is the client's `RegistryAccess`, which a client builds
// from the `registry_data` packets of the configuration phase. Both registries
// are `NewDatapackRegistryEvent.worldRegistry(key, codec, networkCodec)`
// (`ComputerCraft.registerDynamicRegistries`), i.e. *synchronised* datapack
// registries: the server sends their entries. A server that does not (Pumpkin
// sends only vanilla registries) leaves them empty, and the tab shows only the
// base turtle and pocket computer. So the plugin sends the packets itself, in
// the NeoForge declaration (`plugin/cc_neoforge.dart`), the host adds them to the
// registry data NeoForge clients get.
//
// Packet layout (`CRegistryData` in Pumpkin, `ClientboundRegistryDataPacket`):
//
//     string  registry id                      `computercraft:turtle_upgrade`
//     VarInt  entry count
//     per entry:  string key, bool hasData, [network NBT of the entry]
//
// The entry is the file `data/<namespace>/computercraft/<turtle_upgrade |
// pocket_upgrade>/<name>.json` of the mod's data pack (inside the jar; the
// directory of a non-vanilla registry is `<registry namespace>/<registry
// path>`), converted by `JsonNbt`. Known packs do not matter: an entry with
// data is always decoded from the data; "no data" would make the client load
// it from a pack it says it knows, and the mod's pack is not one the server
// announces.
//
// The **ids** of the entries are their positions in the packet: the client
// registers them in order (`RegistryDataLoader.loadContentsFromNetwork`) and
// `ByteBufCodecs.holderRegistry` (the codec of the `left_turtle_upgrade`,
// `right_turtle_upgrade`, `top_pocket_upgrade` and `back_pocket_upgrade` item
// components, `UpgradeManager`) writes that id as a VarInt. So the order here
// is part of the protocol: [DatapackRegistry.indexOf] is what the plugin puts
// into item components, and it also is the order of the variants in the
// creative tab. A Java server lists the entries of a data pack directory in
// the order of a `TreeMap<Identifier, ...>` (`FileToIdConverter`), and
// `Identifier.compareTo` compares the *path* first and the namespace second;
// the plugin sorts the same way, so the tab looks like a real server's:
// `crafting_table`, `diamond_axe`, ..., `speaker`, `wireless_modem_advanced`,
// `wireless_modem_normal` (this order was derived from the sources, not
// observed).
import 'dart:convert';
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart' show NeoForgeDatapackEntry;
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../machine/zip.dart';
import 'json_nbt.dart';
import 'registries.dart';

/// The id of `minecraft:registry_data` in the configuration phase (26.3,
/// clientbound; docs/neoforge-protocol.md).
const int configRegistryDataPacketId = 7;

/// One entry of a datapack registry.
final class DatapackEntry {
  /// `namespace:path`.
  final String key;

  /// The decoded JSON file.
  final Map<String, Object?> json;

  /// Where it came from (`jar` or `built-in`), for the log.
  final String source;

  DatapackEntry(this.key, this.json, this.source);

  /// The `type` field: `computercraft:tool`, `computercraft:wireless_modem`, ...
  String get type => json['type'] is String ? json['type']! as String : '';

  late final Uint8List nbt = JsonNbt.encodeCompound(json, hints: upgradeNumberHints);
}

/// A datapack registry with its entries in id order.
final class DatapackRegistry {
  /// `computercraft:turtle_upgrade` or `computercraft:pocket_upgrade`.
  final String id;
  final List<DatapackEntry> entries;

  DatapackRegistry(this.id, this.entries);

  /// The id (position) of the entry [key] as the client numbers it, or null.
  int? indexOf(String key) {
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].key == key) return i;
    }
    return null;
  }

  DatapackEntry? entry(String key) {
    final index = indexOf(key);
    return index == null ? null : entries[index];
  }

  DatapackEntry? entryAt(int index) => index >= 0 && index < entries.length ? entries[index] : null;

  /// The body of the `registry_data` packet (without the packet id).
  Uint8List toPacket() => PacketBuffer.encode((w) {
    w.writeString(id);
    w.writeVarInt(entries.length);
    for (final entry in entries) {
      w.writeString(entry.key);
      w.writeBool(true);
      w.writeBytes(entry.nbt);
    }
  });
}

/// The two registries of the mod.
final class CcDatapackRegistries {
  static const String turtleUpgradeRegistry = 'computercraft:turtle_upgrade';
  static const String pocketUpgradeRegistry = 'computercraft:pocket_upgrade';

  final DatapackRegistry turtleUpgrades;
  final DatapackRegistry pocketUpgrades;

  /// What went wrong while reading, one line each (logged by the plugin).
  final List<String> notes;

  CcDatapackRegistries(this.turtleUpgrades, this.pocketUpgrades, this.notes);

  Iterable<DatapackRegistry> get all => [turtleUpgrades, pocketUpgrades];

  /// Every entry of both registries as a declaration entry, in id order (the
  /// host sends them in the order given).
  List<NeoForgeDatapackEntry> toDeclared() => [
    for (final registry in all)
      for (final entry in registry.entries) NeoForgeDatapackEntry(registry.id, entry.key, entry.nbt),
  ];

  /// Reads both registries from the jar of the mod ([archive], null for none):
  /// every entry under `data/<namespace>/computercraft/<registry>/` (other data
  /// packs bundled in the jar included), sorted by path and then namespace like
  /// a Java server lists them. An entry of `CcRegistries.turtleUpgrades` /
  /// `pocketUpgrades` that the jar lacks falls back to the built-in copy of its
  /// definition (the same content as the mod's data pack).
  factory CcDatapackRegistries.load(ZipArchive? archive) {
    final notes = <String>[];
    return CcDatapackRegistries(
      _readRegistry(archive, turtleUpgradeRegistry, CcRegistries.turtleUpgrades, _builtInTurtle, notes),
      _readRegistry(archive, pocketUpgradeRegistry, CcRegistries.pocketUpgrades, _builtInPocket, notes),
      notes,
    );
  }
}

/// `Identifier.compareTo`: the path first, then the namespace.
int _compareKeys(DatapackEntry a, DatapackEntry b) {
  final ai = a.key.indexOf(':');
  final bi = b.key.indexOf(':');
  final path = a.key.substring(ai + 1).compareTo(b.key.substring(bi + 1));
  return path != 0 ? path : a.key.substring(0, ai).compareTo(b.key.substring(0, bi));
}

DatapackRegistry _readRegistry(
  ZipArchive? archive,
  String registry,
  List<String> canonical,
  Map<String, Map<String, Object?>> builtIn,
  List<String> notes,
) {
  final path = registry.substring(registry.indexOf(':') + 1);
  final directory = '${registry.substring(0, registry.indexOf(':'))}/$path';
  final entries = <DatapackEntry>[];
  final seen = <String>{};

  DatapackEntry? fromJar(String key) {
    if (archive == null) return null;
    final colon = key.indexOf(':');
    final file = archive.find('data/${key.substring(0, colon)}/$directory/${key.substring(colon + 1)}.json');
    if (file == null) return null;
    try {
      final json = jsonDecode(utf8.decode(file.read()));
      if (json is Map<String, Object?>) return DatapackEntry(key, json, 'jar');
      notes.add('${file.name} is not a JSON object');
    } on FormatException catch (e) {
      notes.add('${file.name}: ${e.message}');
    } on ZipException catch (e) {
      notes.add('${file.name}: $e');
    }
    return null;
  }

  // Everything the jar has under the registry's directory.
  if (archive != null) {
    final suffix = '/$directory/';
    for (final zipEntry in archive.entries) {
      final name = zipEntry.name;
      if (!name.startsWith('data/') || !name.endsWith('.json')) continue;
      final at = name.indexOf(suffix);
      if (at < 0) continue;
      final namespace = name.substring(5, at);
      if (namespace.contains('/')) continue;
      final rest = name.substring(at + suffix.length, name.length - 5);
      final key = '$namespace:$rest';
      if (seen.contains(key)) continue;
      final entry = fromJar(key);
      if (entry != null) {
        seen.add(key);
        entries.add(entry);
      }
    }
  }
  // The mod's own entries the jar did not have.
  for (final key in canonical) {
    if (seen.contains(key)) continue;
    final definition = builtIn[key];
    if (definition == null) {
      notes.add('$registry has no entry $key');
      continue;
    }
    seen.add(key);
    entries.add(DatapackEntry(key, definition, 'built-in'));
  }
  entries.sort(_compareKeys);
  return DatapackRegistry(registry, entries);
}

// The mod's own definitions, used when the jar does not have a file (they are
// the files of `data/{computercraft,minecraft}/computercraft/*` of the 1.120.3
// jar).
final Map<String, Map<String, Object?>> _builtInTurtle = {
  'computercraft:speaker': {'type': 'computercraft:speaker', 'item': 'computercraft:speaker'},
  'computercraft:wireless_modem_advanced': {
    'type': 'computercraft:wireless_modem',
    'advanced': true,
    'item': 'computercraft:wireless_modem_advanced',
  },
  'computercraft:wireless_modem_normal': {
    'type': 'computercraft:wireless_modem',
    'advanced': false,
    'item': 'computercraft:wireless_modem_normal',
  },
  'minecraft:crafting_table': {'type': 'computercraft:workbench', 'item': 'minecraft:crafting_table'},
  'minecraft:diamond_axe': {
    'type': 'computercraft:tool',
    'adjective': {'translate': 'upgrade.minecraft.diamond_axe.adjective'},
    'damageMultiplier': 6.0,
    'item': 'minecraft:diamond_axe',
  },
  'minecraft:diamond_hoe': {
    'type': 'computercraft:tool',
    'adjective': {'translate': 'upgrade.minecraft.diamond_hoe.adjective'},
    'breakable': 'computercraft:turtle_hoe_harvestable',
    'item': 'minecraft:diamond_hoe',
  },
  'minecraft:diamond_pickaxe': {
    'type': 'computercraft:tool',
    'adjective': {'translate': 'upgrade.minecraft.diamond_pickaxe.adjective'},
    'item': 'minecraft:diamond_pickaxe',
  },
  'minecraft:diamond_shovel': {
    'type': 'computercraft:tool',
    'adjective': {'translate': 'upgrade.minecraft.diamond_shovel.adjective'},
    'breakable': 'computercraft:turtle_shovel_harvestable',
    'item': 'minecraft:diamond_shovel',
  },
  'minecraft:diamond_sword': {
    'type': 'computercraft:tool',
    'adjective': {'translate': 'upgrade.minecraft.diamond_sword.adjective'},
    'breakable': 'computercraft:turtle_sword_harvestable',
    'damageMultiplier': 9.0,
    'item': 'minecraft:diamond_sword',
  },
};

final Map<String, Map<String, Object?>> _builtInPocket = {
  'computercraft:speaker': {'type': 'computercraft:speaker', 'item': 'computercraft:speaker'},
  'computercraft:wireless_modem_advanced': {
    'type': 'computercraft:wireless_modem',
    'advanced': true,
    'item': 'computercraft:wireless_modem_advanced',
  },
  'computercraft:wireless_modem_normal': {
    'type': 'computercraft:wireless_modem',
    'advanced': false,
    'item': 'computercraft:wireless_modem_normal',
  },
};
