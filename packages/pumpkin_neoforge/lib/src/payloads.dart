// Byte-level encoders and decoders of every NeoForge 26.3 negotiation payload.
// Binding-free. The layouts are documented in docs/neoforge-protocol.md, each
// with the NeoForge source it comes from; test/golden/ has byte vectors made
// by an independent Java implementation of the same codecs.
import 'dart:typed_data';

// ignore: implementation_imports
import 'package:pumpkin_api/src/packet_buffer.dart';

import 'identifier.dart';
import 'nbt_text.dart';
import 'protocol.dart';

/// The maximum number of elements the decoders accept in one list, map or set
/// that the *client* controls. Real clients send far fewer.
const int maxPayloadElements = 4096;

String _readId(PacketReader reader) =>
    normalizeIdentifier(reader.readString(maxLength: 32767));

void _writeId(PacketWriter writer, String id) =>
    writer.writeString(normalizeIdentifier(id));

// ---------------------------------------------------------------------------
// minecraft:register / minecraft:unregister
// ---------------------------------------------------------------------------

/// Encodes the payload of `minecraft:register` and `minecraft:unregister`
/// (`DinnerboneProtocolUtils`): every channel followed by a `0x00` byte, no
/// length prefix. Duplicates are written once.
Uint8List encodeRegisterChannels(Iterable<String> channels) {
  final seen = <String>{};
  final writer = PacketWriter();
  for (final channel in channels) {
    final id = normalizeIdentifier(channel);
    if (!seen.add(id)) continue;
    for (final unit in id.codeUnits) {
      writer.writeByte(unit & 0xFF);
    }
    writer.writeByte(0);
  }
  return writer.toBytes();
}

/// Decodes `minecraft:register` / `minecraft:unregister`, like NeoForge:
/// names are split at `0x00`, bytes are read as characters, and a name that is
/// not a valid identifier is ignored.
List<String> decodeRegisterChannels(List<int> data) {
  final result = <String>[];
  final seen = <String>{};
  final current = StringBuffer();
  void flush() {
    if (current.isEmpty) return;
    final name = current.toString();
    current.clear();
    try {
      final id = normalizeIdentifier(name);
      if (seen.add(id)) result.add(id);
    } on FormatException {
      // NeoForge logs "Invalid channel" and goes on.
    }
  }

  for (final byte in data) {
    if (byte == 0) {
      flush();
    } else {
      current.writeCharCode(byte & 0xFF);
    }
  }
  flush();
  return result;
}

// ---------------------------------------------------------------------------
// neoforge:register  (ModdedNetworkQueryPayload)
// ---------------------------------------------------------------------------

/// What one side registered for a payload channel
/// (`ModdedNetworkQueryComponent`).
final class QueryComponent {
  final String id;
  final String version;

  /// The direction the payload flows in, or null for both.
  final PacketFlow? flow;

  /// Whether the other side may lack the channel.
  final bool optional;

  QueryComponent({
    required String id,
    required this.version,
    this.flow,
    this.optional = false,
  }) : id = normalizeIdentifier(id);

  @override
  bool operator ==(Object other) =>
      other is QueryComponent &&
      other.id == id &&
      other.version == version &&
      other.flow == flow &&
      other.optional == optional;

  @override
  int get hashCode => Object.hash(id, version, flow, optional);

  @override
  String toString() =>
      'QueryComponent($id v$version ${flow?.name ?? 'both'}'
      '${optional ? ' optional' : ''})';
}

/// The query payload: sent by the server with an empty map, answered by the
/// client with everything it registered, per protocol (`neoforge:register`).
final class ModdedNetworkQuery {
  final Map<NetworkPhase, List<QueryComponent>> components;

  const ModdedNetworkQuery(this.components);

  /// The server's query: nothing.
  static const ModdedNetworkQuery empty = ModdedNetworkQuery({});

  Uint8List encode() => PacketBuffer.encode((w) {
    final phases = components.keys.toList()
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    w.writeVarInt(phases.length);
    for (final phase in phases) {
      w.writeVarInt(phase.ordinal);
      final list = components[phase]!;
      w.writeVarInt(list.length);
      for (final c in list) {
        _writeId(w, c.id);
        w.writeString(c.version);
        w.writeOptional<PacketFlow>(c.flow, (w, f) => w.writeVarInt(f.ordinal));
        w.writeBool(c.optional);
      }
    }
  });

  static ModdedNetworkQuery decode(List<int> data) =>
      PacketBuffer.decode(data, (r) {
        final result = <NetworkPhase, List<QueryComponent>>{};
        final phases = r.readList((r) {
          final ordinal = r.readVarInt();
          final phase = NetworkPhase.byOrdinal(ordinal);
          if (phase == null) {
            throw PacketException('Unknown connection protocol $ordinal');
          }
          final list = r.readList((r) {
            final id = _readId(r);
            final version = r.readString();
            final flow = r.readOptional<PacketFlow>((r) {
              final o = r.readVarInt();
              final f = PacketFlow.byOrdinal(o);
              if (f == null) throw PacketException('Unknown packet flow $o');
              return f;
            });
            final optional = r.readBool();
            return QueryComponent(
              id: id,
              version: version,
              flow: flow,
              optional: optional,
            );
          }, maxLength: maxPayloadElements);
          return (phase, list);
        }, maxLength: NetworkPhase.values.length);
        for (final (phase, list) in phases) {
          // Maps overwrite duplicate keys.
          result[phase] = list;
        }
        return ModdedNetworkQuery(result);
      });
}

// ---------------------------------------------------------------------------
// neoforge:network  (ModdedNetworkPayload)
// ---------------------------------------------------------------------------

/// The channels the server negotiated, per protocol: id -> chosen version
/// (`NetworkPayloadSetup`).
final class ModdedNetworkSetup {
  final Map<NetworkPhase, Map<String, String>> channels;

  const ModdedNetworkSetup(this.channels);

  static const ModdedNetworkSetup empty = ModdedNetworkSetup({});

  Uint8List encode() => PacketBuffer.encode((w) {
    final phases = channels.keys.toList()
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    w.writeVarInt(phases.length);
    for (final phase in phases) {
      w.writeVarInt(phase.ordinal);
      final map = channels[phase]!;
      w.writeVarInt(map.length);
      for (final entry in map.entries) {
        _writeId(w, entry.key);
        // NetworkChannel(id, chosenVersion): the id is repeated inside.
        _writeId(w, entry.key);
        w.writeString(entry.value);
      }
    }
  });

  static ModdedNetworkSetup decode(List<int> data) =>
      PacketBuffer.decode(data, (r) {
        final result = <NetworkPhase, Map<String, String>>{};
        final count = r.readVarInt();
        if (count < 0 || count > NetworkPhase.values.length) {
          throw PacketException('Bad protocol count $count');
        }
        for (var i = 0; i < count; i++) {
          final ordinal = r.readVarInt();
          final phase = NetworkPhase.byOrdinal(ordinal);
          if (phase == null) {
            throw PacketException('Unknown connection protocol $ordinal');
          }
          final map = <String, String>{};
          final n = r.readVarInt();
          if (n < 0 || n > maxPayloadElements) {
            throw PacketException('Bad channel count $n');
          }
          for (var j = 0; j < n; j++) {
            final key = _readId(r);
            final innerId = _readId(r);
            final version = r.readString();
            if (innerId != key) {
              throw PacketException('Channel $key is described as $innerId');
            }
            map[key] = version;
          }
          result[phase] = map;
        }
        return ModdedNetworkSetup(result);
      });
}

// ---------------------------------------------------------------------------
// neoforge:modded_network_setup_failed
// ---------------------------------------------------------------------------

/// Why the negotiation failed, per channel, for the client's mismatch screen
/// (`ModdedNetworkSetupFailedPayload`). The reasons are text components.
final class ModdedNetworkSetupFailed {
  final Map<String, NbtText> reasons;

  const ModdedNetworkSetupFailed(this.reasons);

  Uint8List encode() => PacketBuffer.encode((w) {
    w.writeVarInt(reasons.length);
    for (final entry in reasons.entries) {
      _writeId(w, entry.key);
      entry.value.write(w);
    }
  });

  static ModdedNetworkSetupFailed decode(List<int> data) =>
      PacketBuffer.decode(data, (r) {
        final n = r.readVarInt();
        if (n < 0 || n > maxPayloadElements) {
          throw PacketException('Bad reason count $n');
        }
        return ModdedNetworkSetupFailed({
          for (var i = 0; i < n; i++) _readId(r): NbtText.read(r),
        });
      });
}

// ---------------------------------------------------------------------------
// c:version and c:register
// ---------------------------------------------------------------------------

/// `c:version`: the common network versions a side supports.
final class CommonVersion {
  final List<int> versions;

  const CommonVersion(this.versions);

  /// What NeoForge sends: `[1]`.
  static const CommonVersion supported = CommonVersion([commonNetworkVersion]);

  Uint8List encode() => PacketBuffer.encode(
    (w) => w.writeList<int>(versions, (w, v) => w.writeVarInt(v)),
  );

  static CommonVersion decode(List<int> data) => PacketBuffer.decode(
    data,
    (r) => CommonVersion(
      r.readList((r) => r.readVarInt(), maxLength: maxPayloadElements),
    ),
  );

  /// Whether NeoForge (which supports only version 1) accepts it: at least
  /// one of the versions must be [commonNetworkVersion].
  bool get isAcceptable => versions.contains(commonNetworkVersion);
}

/// `c:register`: the channels a side can receive in a protocol.
final class CommonRegister {
  final int version;
  final NetworkPhase phase;
  final List<String> channels;

  CommonRegister({
    this.version = commonNetworkVersion,
    required this.phase,
    required Iterable<String> channels,
  }) : channels = [for (final c in channels) normalizeIdentifier(c)];

  Uint8List encode() => PacketBuffer.encode((w) {
    w.writeVarInt(version);
    w.writeString(phase.id);
    w.writeVarInt(channels.length);
    for (final c in channels) {
      _writeId(w, c);
    }
  });

  static CommonRegister decode(List<int> data) => PacketBuffer.decode(data, (
    r,
  ) {
    final version = r.readVarInt();
    final phaseId = r.readString();
    final phase = NetworkPhase.byId(phaseId);
    if (phase == null) {
      // NeoForge's codec maps an unknown id to null and then fails.
      throw PacketException('Unknown connection protocol "$phaseId"');
    }
    final channels = r.readList(_readId, maxLength: maxPayloadElements);
    return CommonRegister(version: version, phase: phase, channels: channels);
  });
}

// ---------------------------------------------------------------------------
// Registry synchronisation
// ---------------------------------------------------------------------------

/// `neoforge:frozen_registry_sync_start`: the registries that follow.
final class FrozenRegistrySyncStart {
  final List<String> registries;

  FrozenRegistrySyncStart(Iterable<String> registries)
    : registries = [for (final r in registries) normalizeIdentifier(r)];

  Uint8List encode() =>
      PacketBuffer.encode((w) => w.writeList<String>(registries, _writeId));

  static FrozenRegistrySyncStart decode(List<int> data) => PacketBuffer.decode(
    data,
    (r) => FrozenRegistrySyncStart(
      r.readList(_readId, maxLength: maxPayloadElements),
    ),
  );
}

/// The entries of one registry, with their numeric ids (`RegistrySnapshot`).
final class RegistrySnapshot {
  /// Registry entries by numeric id.
  final Map<int, String> ids;

  /// Old name -> current name.
  final Map<String, String> aliases;

  /// A snapshot where the id of an entry is its index in [entries].
  RegistrySnapshot.ordered(
    Iterable<String> entries, {
    Map<String, String> aliases = const {},
  }) : ids = {for (final (i, e) in entries.indexed) i: normalizeIdentifier(e)},
       aliases = {
         for (final e in aliases.entries)
           normalizeIdentifier(e.key): normalizeIdentifier(e.value),
       };

  RegistrySnapshot(this.ids, [this.aliases = const {}]);

  /// The entries in id order.
  List<String> get orderedEntries {
    final keys = ids.keys.toList()..sort();
    return [for (final k in keys) ids[k]!];
  }

  /// Whether the ids are exactly 0..n-1.
  bool get isContiguous {
    if (ids.isEmpty) return true;
    final keys = ids.keys.toList()..sort();
    return keys.first == 0 && keys.last == keys.length - 1;
  }

  void write(PacketWriter w) {
    // The client applies the entries in increasing id order, so write them
    // sorted (NeoForge uses a sorted map).
    final keys = ids.keys.toList()..sort();
    w.writeVarInt(keys.length);
    for (final key in keys) {
      w.writeVarInt(key);
      _writeId(w, ids[key]!);
    }
    final names = aliases.keys.toList()..sort();
    w.writeVarInt(names.length);
    for (final name in names) {
      _writeId(w, name);
      _writeId(w, aliases[name]!);
    }
  }

  static RegistrySnapshot read(PacketReader r) {
    final count = r.readVarInt();
    if (count < 0) throw PacketException('Negative entry count $count');
    final ids = <int, String>{};
    for (var i = 0; i < count; i++) {
      final id = r.readVarInt();
      ids[id] = _readId(r);
    }
    final aliasCount = r.readVarInt();
    if (aliasCount < 0) throw PacketException('Negative alias count');
    final aliases = <String, String>{};
    for (var i = 0; i < aliasCount; i++) {
      final from = _readId(r);
      aliases[from] = _readId(r);
    }
    return RegistrySnapshot(ids, aliases);
  }
}

/// `neoforge:frozen_registry`: one registry.
final class FrozenRegistry {
  final String registry;
  final RegistrySnapshot snapshot;

  FrozenRegistry(String registry, this.snapshot)
    : registry = normalizeIdentifier(registry);

  Uint8List encode() => PacketBuffer.encode((w) {
    _writeId(w, registry);
    snapshot.write(w);
  });

  static FrozenRegistry decode(List<int> data) =>
      PacketBuffer.decode(data, (r) {
        final name = _readId(r);
        return FrozenRegistry(name, RegistrySnapshot.read(r));
      });
}

/// `neoforge:frozen_registry_sync_completed` has an empty body in both
/// directions.
final Uint8List emptyPayload = Uint8List(0);

// ---------------------------------------------------------------------------
// Data maps
// ---------------------------------------------------------------------------

/// A data map the server knows (`KnownDataMap`).
final class KnownDataMap {
  final String id;
  final bool mandatory;

  KnownDataMap(String id, {this.mandatory = false})
    : id = normalizeIdentifier(id);

  @override
  bool operator ==(Object other) =>
      other is KnownDataMap && other.id == id && other.mandatory == mandatory;

  @override
  int get hashCode => Object.hash(id, mandatory);

  @override
  String toString() => 'KnownDataMap($id${mandatory ? ', mandatory' : ''})';
}

/// `neoforge:known_registry_data_maps`: the data maps the server has, per
/// registry.
final class KnownRegistryDataMaps {
  final Map<String, List<KnownDataMap>> dataMaps;

  const KnownRegistryDataMaps(this.dataMaps);

  Uint8List encode() => PacketBuffer.encode((w) {
    w.writeVarInt(dataMaps.length);
    for (final entry in dataMaps.entries) {
      _writeId(w, entry.key);
      w.writeList<KnownDataMap>(entry.value, (w, m) {
        _writeId(w, m.id);
        w.writeBool(m.mandatory);
      });
    }
  });

  static KnownRegistryDataMaps decode(List<int> data) =>
      PacketBuffer.decode(data, (r) {
        final n = r.readVarInt();
        if (n < 0 || n > maxPayloadElements) {
          throw PacketException('Bad registry count $n');
        }
        return KnownRegistryDataMaps({
          for (var i = 0; i < n; i++)
            _readId(r): r.readList(
              (r) => KnownDataMap(_readId(r), mandatory: r.readBool()),
              maxLength: maxPayloadElements,
            ),
        });
      });
}

/// `neoforge:known_registry_data_maps_reply`: the data maps the client has,
/// per registry.
final class KnownRegistryDataMapsReply {
  final Map<String, List<String>> dataMaps;

  const KnownRegistryDataMapsReply(this.dataMaps);

  Uint8List encode() => PacketBuffer.encode((w) {
    w.writeVarInt(dataMaps.length);
    for (final entry in dataMaps.entries) {
      _writeId(w, entry.key);
      w.writeList<String>(entry.value, _writeId);
    }
  });

  static KnownRegistryDataMapsReply decode(List<int> data) =>
      PacketBuffer.decode(data, (r) {
        final n = r.readVarInt();
        if (n < 0 || n > maxPayloadElements) {
          throw PacketException('Bad registry count $n');
        }
        return KnownRegistryDataMapsReply({
          for (var i = 0; i < n; i++)
            _readId(r): r.readList(_readId, maxLength: maxPayloadElements),
        });
      });
}

// ---------------------------------------------------------------------------
// Extensible enums and feature flags
// ---------------------------------------------------------------------------

/// `NetworkedEnum.NetworkCheck`.
enum EnumNetworkCheck { clientbound, serverbound, bidirectional }

/// The entries a mod added to a vanilla enum (`ExtensionData`).
final class EnumExtension {
  final int vanillaCount;
  final int totalCount;
  final List<String> entries;

  const EnumExtension(this.vanillaCount, this.totalCount, this.entries);
}

/// One networked extensible enum (`CheckExtensibleEnums.EnumEntry`).
final class EnumEntry {
  /// The Java class name, e.g. `net.minecraft.world.item.Rarity`.
  final String className;
  final EnumNetworkCheck check;

  /// Present if some mod added entries.
  final EnumExtension? extension;

  const EnumEntry(this.className, this.check, [this.extension]);
}

/// `neoforge:extensible_enum_data`.
final class ExtensibleEnumData {
  final List<EnumEntry> entries;

  const ExtensibleEnumData(this.entries);

  Uint8List encode() => PacketBuffer.encode((w) {
    w.writeList<EnumEntry>(entries, (w, e) {
      w.writeString(e.className);
      w.writeString(e.check.name.toUpperCase());
      w.writeOptional<EnumExtension>(e.extension, (w, x) {
        w.writeVarInt(x.vanillaCount);
        w.writeVarInt(x.totalCount);
        w.writeList<String>(x.entries, (w, s) => w.writeString(s));
      });
    });
  });

  static ExtensibleEnumData decode(List<int> data) => PacketBuffer.decode(
    data,
    (r) => ExtensibleEnumData(
      r.readList((r) {
        final className = r.readString();
        final checkName = r.readString();
        final check = EnumNetworkCheck.values
            .where((c) => c.name.toUpperCase() == checkName)
            .firstOrNull;
        if (check == null) {
          throw PacketException('Unknown NetworkCheck "$checkName"');
        }
        final ext = r.readOptional((r) {
          final vanilla = r.readVarInt();
          final total = r.readVarInt();
          final names = r.readList(
            (r) => r.readString(),
            maxLength: maxPayloadElements,
          );
          return EnumExtension(vanilla, total, names);
        });
        return EnumEntry(className, check, ext);
      }, maxLength: maxPayloadElements),
    ),
  );
}

/// `neoforge:feature_flags`: the modded feature flags.
final class FeatureFlagData {
  final List<String> flags;

  FeatureFlagData(Iterable<String> flags)
    : flags = [for (final f in flags) normalizeIdentifier(f)];

  Uint8List encode() =>
      PacketBuffer.encode((w) => w.writeList<String>(flags, _writeId));

  static FeatureFlagData decode(List<int> data) => PacketBuffer.decode(
    data,
    (r) => FeatureFlagData(r.readList(_readId, maxLength: maxPayloadElements)),
  );
}

// ---------------------------------------------------------------------------
// Config sync
// ---------------------------------------------------------------------------

/// `neoforge:config_file`: a synced server config file.
final class ConfigFile {
  final String fileName;
  final Uint8List contents;

  ConfigFile(this.fileName, List<int> contents)
    : contents = Uint8List.fromList(contents);

  Uint8List encode() => PacketBuffer.encode((w) {
    w.writeString(fileName);
    w.writeByteArray(contents);
  });

  static ConfigFile decode(List<int> data) => PacketBuffer.decode(data, (r) {
    final name = r.readString();
    return ConfigFile(name, r.readByteArray());
  });
}
