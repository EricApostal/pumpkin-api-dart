// The block entity of the physics assembler.
//
// It owns a [PhysicsAssembler] and forwards the Create lifecycle to it: the
// assembler's state is refreshed from the world on every tick, the lever and the
// alignment run in `tick()`, and the saved data carries the primary flag and the
// last failure.
//
// Host: this file uses `pumpkin_api`.
//
// Java: dev.simulated_team.simulated.content.blocks.physics_assembler.PhysicsAssemblerBlockEntity
// create's internals are not in its public barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:create/src/common/host_bridge.dart';
import 'package:create/src/core/block_entity.dart';
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../util/assembly/sim_assembly_exception.dart';
import 'physics_assembler.dart';

/// `PhysicsAssemblerBlockEntity`.
final class PhysicsAssemblerBlockEntity extends CreateBlockEntity {
  /// The block entity type key.
  static const String type = 'simulated:physics_assembler';

  /// The block key.
  static const String block = 'simulated:physics_assembler';

  PhysicsAssemblerBlockEntity(super.worldId, super.pos);

  late final PhysicsAssembler assembler = PhysicsAssembler(
    worldId: worldId,
    pos: pos.toPos(),
    state: state,
  );

  /// The state the entity last saw.
  BState state = BState(block);

  @override
  void tick() {
    final w = world;
    if (w != null && !removed) {
      state = HostBlockGetter.stateOfId(w.getBlockStateId(pos: pos));
      assembler.state = state;
    }
    assembler.tick();
    super.tick();
  }

  @override
  void initialize() {
    assembler.initialize();
    super.initialize();
  }

  @override
  void onRemoved() {
    assembler.removed();
    super.onRemoved();
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (clientPacket) return;
    final exception = tag.getCompound('LastException')?.getString('Component');
    assembler.read({
      'IsPrimary': tag.getBool('IsPrimary') ?? false,
      'LastException': ?exception,
      if (tag.getString('SubLevel') != null) 'SubLevel': tag.getString('SubLevel'),
    });
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    final data = assembler.write();
    tag.putBool('IsPrimary', data['IsPrimary'] == true);
    final exception = data['LastException'];
    // `AssemblyException.write`: `LastException {Component}` - the message's component
    // JSON, which is what the client reads and the goggles overlay shows.
    if (exception is String) {
      tag.putCompound('LastException', NbtCompound()..putString('Component', exception));
    }
    final subLevel = data['SubLevel'];
    if (subLevel is String) tag.putString('SubLevel', subLevel);
    if (clientPacket) tag.putFloat('Angle', assembler.clientAngle());
  }

  /// `assembleOrDisassemble()`.
  ///
  /// Completes when the assembly did: the block move runs in the Sable
  /// component, so this is a round trip rather than a call.
  Future<void> assembleOrDisassemble() async {
    await assembler.assembleOrDisassemble();
    sendData();
  }

  /// `setClientHoldLeverInPlace(holding)`.
  void setClientHoldLeverInPlace(bool holding) => assembler.setClientHoldLeverInPlace(holding);

  /// `updateControlledByPlayer(angle)`.
  void updateControlledByPlayer(double angle) => assembler.updateControlledByPlayer(angle);

  /// `stopControllingPlayer()`.
  bool stopControllingPlayer() => assembler.stopControllingPlayer();

  /// `getClientAngle(partialTicks)`.
  double getClientAngle([double partialTicks = 1]) => assembler.clientAngle(partialTicks);

  /// `isPrimaryAssembler()`.
  bool get isPrimaryAssembler => assembler.logic.primaryAssembler;

  /// `getLastAssemblyException()`.
  SimAssemblyException? get lastAssemblyException => assembler.logic.lastException;
}
