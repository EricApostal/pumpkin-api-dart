// The assembly payloads: the assembler's lever and the block-entity observer.
//
// Field order is the Java `StreamCodec.composite` order and is what the client
// reads; `test/payload_codec_test.dart` pins it byte for byte.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.network.packets.AssemblePacket
//       …packets.BlockEntityObservedPacket
//       …packets.physics_assembler.PhysicsAssemblerFailedPacket
//       …packets.physics_assembler.PhysicsAssemblerFlickAndHoldLeverPacket
// create's internals are pure but not exported from the barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;


import '../sim_packet.dart';

/// `simulated:assemble` — the player right-clicked an assembler.
final class AssemblePacket implements SimPacket {
  static const String type = 'simulated:assemble';

  /// The assembler the player clicked.
  final Pos pos;

  const AssemblePacket(this.pos);

  @override
  String get id => type;

  static final SimCodec<AssemblePacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) => w.writeBlockPos(p.pos),
    (r) => AssemblePacket(r.readBlockPos()),
  );
}

/// `simulated:be_observed` — the client started looking at a block entity, so
/// the server may start syncing it.
///
/// Java builds the codec with `BlockPos.STREAM_CODEC.map(...)`, which is the
/// same single packed long.
final class BlockEntityObservedPacket implements SimPacket {
  static const String type = 'simulated:be_observed';

  final Pos pos;

  const BlockEntityObservedPacket(this.pos);

  @override
  String get id => type;

  static final SimCodec<BlockEntityObservedPacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) => w.writeBlockPos(p.pos),
    (r) => BlockEntityObservedPacket(r.readBlockPos()),
  );
}

/// `simulated:assembler_failed` — the assembly was refused; the client plays the
/// lever and the sound.
final class PhysicsAssemblerFailedPacket implements SimPacket {
  static const String type = 'simulated:assembler_failed';

  final Pos pos;

  const PhysicsAssemblerFailedPacket(this.pos);

  @override
  String get id => type;

  static final SimCodec<PhysicsAssemblerFailedPacket> codec = SimCodec(
    type,
    SimPacketDirection.clientbound,
    (w, p) => w.writeBlockPos(p.pos),
    (r) => PhysicsAssemblerFailedPacket(r.readBlockPos()),
  );
}

/// `simulated:flick_assembler_lever` — the lever animation, plus whether it
/// stays down.
final class PhysicsAssemblerFlickAndHoldLeverPacket implements SimPacket {
  static const String type = 'simulated:flick_assembler_lever';

  final Pos pos;
  final bool flicked;

  const PhysicsAssemblerFlickAndHoldLeverPacket(this.pos, this.flicked);

  @override
  String get id => type;

  static final SimCodec<PhysicsAssemblerFlickAndHoldLeverPacket> codec = SimCodec(
    type,
    SimPacketDirection.clientbound,
    (w, p) => w
      ..writeBlockPos(p.pos)
      ..writeBool(p.flicked),
    (r) => PhysicsAssemblerFlickAndHoldLeverPacket(r.readBlockPos(), r.readBool()),
  );
}
