// The `SynchedEntityData` entries of `AbstractContraptionEntity` and its subclasses.
//
// Java assigns every index by the static initialisation order of the class chain
// (`SynchedEntityData.defineId`): `Entity` uses 0..7 (`DATA_SHARED_FLAGS_ID` .. `DATA_TICKS_FROZEN`,
// `crates/pumpkin-data/src/generated/tracked_data.rs`), `AbstractContraptionEntity` adds `STALLED`
// (8) and `CONTROLLED_BY` (9) (`AbstractContraptionEntity.java:86-92`), `OrientedContraptionEntity`
// adds `COUPLING` (10) and `INITIAL_ORIENTATION` (11) (`OrientedContraptionEntity.java:67-69`), and
// `CarriageContraptionEntity` adds `CARRIAGE_DATA` (12), `TRACK_GRAPH` (13) and `SCHEDULED` (14)
// (`CarriageContraptionEntity.java:107-113`).
//
// A plugin entity sends an entry with `Entity.setSyncedEntry`, which is `entityData.set(index,
// value)` on the wire: the serializer id (a VarInt), then the value. The host sends it to the
// players tracking the entity; the entry is also saved with the entity, so a client that starts
// tracking later gets it.
//
// Reading on the Java client: `isStalled()` drives the bearing/pulley/piston interpolation and
// `GantryContraptionEntity.tick`, `getCouplingId()` the coupled-cart motion of a train,
// `CONTROLLED_BY` the train controls, and `SCHEDULED`/`TRACK_GRAPH` the carriage's schedule and
// track graph (`CarriageContraptionEntity.updateTrackGraph`).
import 'package:pumpkin_api/pumpkin_api_core.dart' show PacketWriter;

import '../../content/entity_data_serializers.dart' show EntityDataSerializerIds;

/// The entries of a contraption entity.
abstract final class ContraptionSyncedData {
  /// `AbstractContraptionEntity.STALLED`.
  static const int stalledIndex = 8;

  /// `AbstractContraptionEntity.CONTROLLED_BY`.
  static const int controlledByIndex = 9;

  /// `OrientedContraptionEntity.COUPLING`.
  static const int couplingIndex = 10;

  /// `CarriageContraptionEntity.TRACK_GRAPH`.
  static const int trackGraphIndex = 13;

  /// `CarriageContraptionEntity.SCHEDULED`.
  static const int scheduledIndex = 14;

  /// The key of `AllEntityDataSerializers.OPTIONAL_UUID`, the serializer `CONTROLLED_BY`,
  /// `COUPLING` and `TRACK_GRAPH` are defined with (26.x removed the vanilla one, so Create
  /// registers its replacement).
  static const String optionalUuidKey = 'create:optional_uuid';

  /// `EntityDataSerializers.BOOLEAN`: the eighth vanilla serializer
  /// (`crates/pumpkin-data/src/entity_data_serializer_registry.rs`, `VANILLA_ENTITY_DATA_SERIALIZERS`).
  static const int booleanSerializer = 8;

  /// The id the host gave `create:optional_uuid`, `null` while the serializers are not registered.
  static int? get optionalUuidSerializer =>
      EntityDataSerializerIds.of(optionalUuidKey);

  /// `entityData.set(STALLED/SCHEDULED, value)`: the serializer id, then the byte.
  static List<int> booleanEntry(bool value) => [
    booleanSerializer,
    value ? 1 : 0,
  ];

  /// `entityData.set(COUPLING/CONTROLLED_BY/TRACK_GRAPH, Optional.ofNullable(id))`:
  /// `ByteBufCodecs.optional(UUIDUtil.STREAM_CODEC)` — a boolean, then the uuid as two longs.
  ///
  /// `null` while the serializer is not registered, so the caller skips the entry instead of
  /// sending an id the client cannot resolve.
  static List<int>? optionalUuidEntry(String? id) {
    final serializer = optionalUuidSerializer;
    if (serializer == null) return null;
    final w = PacketWriter()..writeVarInt(serializer);
    w.writeOptional(id, (w, v) => w.writeUuid(v));
    return w.toBytes();
  }
}