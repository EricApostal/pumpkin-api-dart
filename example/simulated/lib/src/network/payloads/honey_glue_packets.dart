// The honey glue payloads: spawning a volume, resizing it, and the clientbound
// sync.
//
// The two hand-written codecs (`StreamCodec.of`) write the AABB as six raw
// doubles in min/max order; `honey_glue_sync` then appends the entity id and an
// optional uuid, exactly as `HoneyGlueSyncBoundsPacket.writeToBuf` does.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.network.packets.honey_glue.*
// create's barrel does not export `Aabb` yet.
// ignore_for_file: implementation_imports
import 'package:create/src/common/bounds.dart' show Aabb;
import 'package:create/src/common/pos.dart' show Pos;


import '../sim_packet.dart';
import '../sim_wire.dart';

/// `simulated:honey_glue_spawn` — the two block corners the player dragged.
final class HoneyGlueSpawnPacket implements SimPacket {
  static const String type = 'simulated:honey_glue_spawn';

  final Pos from;
  final Pos to;

  const HoneyGlueSpawnPacket(this.from, this.to);

  @override
  String get id => type;

  static final SimCodec<HoneyGlueSpawnPacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) => w
      ..writeBlockPos(p.from)
      ..writeBlockPos(p.to),
    (r) => HoneyGlueSpawnPacket(r.readBlockPos(), r.readBlockPos()),
  );

  /// `AABB.encapsulatingFullBlocks(from, to)`: the box covering both blocks,
  /// whichever corner the player started from.
  Aabb get bounds => Aabb(
    from.$1 < to.$1 ? from.$1.toDouble() : to.$1.toDouble(),
    from.$2 < to.$2 ? from.$2.toDouble() : to.$2.toDouble(),
    from.$3 < to.$3 ? from.$3.toDouble() : to.$3.toDouble(),
    (from.$1 > to.$1 ? from.$1 : to.$1) + 1.0,
    (from.$2 > to.$2 ? from.$2 : to.$2) + 1.0,
    (from.$3 > to.$3 ? from.$3 : to.$3) + 1.0,
  );
}

/// `simulated:honey_glue_change_bounds` — the player resized a volume.
final class HoneyGlueChangeBoundsPacket implements SimPacket {
  static const String type = 'simulated:honey_glue_change_bounds';

  final Aabb bounds;

  /// The volume's uuid (the entity is looked up by it).
  final String honeyGlue;

  const HoneyGlueChangeBoundsPacket(this.bounds, this.honeyGlue);

  @override
  String get id => type;

  static final SimCodec<HoneyGlueChangeBoundsPacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) => w
      ..writeDouble(p.bounds.minX)
      ..writeDouble(p.bounds.minY)
      ..writeDouble(p.bounds.minZ)
      ..writeDouble(p.bounds.maxX)
      ..writeDouble(p.bounds.maxY)
      ..writeDouble(p.bounds.maxZ)
      ..writeUuid(p.honeyGlue),
    (r) => HoneyGlueChangeBoundsPacket(
      Aabb(r.readDouble(), r.readDouble(), r.readDouble(), r.readDouble(), r.readDouble(), r.readDouble()),
      r.readUuid(),
    ),
  );
}

/// `simulated:honey_glue_sync` — the new bounds of a volume, pushed to the
/// clients watching it.
final class HoneyGlueSyncBoundsPacket implements SimPacket {
  static const String type = 'simulated:honey_glue_sync';

  final Aabb bounds;

  /// The entity id the client already knows.
  final int honeyGlueId;

  /// The uuid of the player that changed the volume, when there is one; the
  /// client ignores an update that came from itself.
  final String? uuid;

  const HoneyGlueSyncBoundsPacket(this.bounds, this.honeyGlueId, [this.uuid]);

  @override
  String get id => type;

  static final SimCodec<HoneyGlueSyncBoundsPacket> codec = SimCodec(
    type,
    SimPacketDirection.clientbound,
    (w, p) {
      SimWire.writeAabb(w, p.bounds);
      w.writeInt(p.honeyGlueId);
      w.writeOptional(p.uuid, (w, v) => w.writeUuid(v));
    },
    (r) {
      final bounds = SimWire.readAabb(r);
      final id = r.readInt();
      return HoneyGlueSyncBoundsPacket(bounds, id, r.readOptional((r) => r.readUuid()));
    },
  );
}
