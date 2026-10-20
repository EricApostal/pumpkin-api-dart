// The serverbound payloads the kinetics module handles: the stressometer's
// observation, the sequenced gearshift's configuration and Create's value settings
// board. The channels are declared by the protocol module; this binds handlers to
// its `PayloadBus` (fields by the manifest names).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/payloads.dart';
import '../api/value_settings.dart';
import 'block_entities.dart';
import 'runtime.dart';
import 'sequence.dart';

/// Binds the handlers to [bus]. Safe to call once.
void bindKineticPackets(PayloadBus bus) {
  bus.onServerbound('create:observer_stressometer', (player, f) {
    final be = _blockEntityFor(player, f['pos'] as (int, int, int));
    if (be is StressGaugeBlockEntity) be.onObserved();
  });

  bus.onServerbound('create:configure_sequencer', (player, f) {
    final be = _blockEntityFor(player, f['pos'] as (int, int, int));
    if (be is! SequencedGearshiftBlockEntity) return;
    final list = f['instructions'] as List<Object?>;
    final instructions = <Instruction>[];
    for (final e in list) {
      final m = e as Map<String, Object?>;
      final type = (m['instruction'] as int).clamp(0, SequencerInstructions.values.length - 1);
      final mod = (m['speedModifier'] as int).clamp(0, InstructionSpeedModifiers.values.length - 1);
      instructions.add(
        Instruction(SequencerInstructions.values[type], m['value'] as int, InstructionSpeedModifiers.values[mod]),
      );
    }
    be.run(-1);
    be.instructions = instructions;
    be.sendData();
  });

  bus.onServerbound('create:value_settings', (player, f) {
    final be = _blockEntityFor(player, f['pos'] as (int, int, int));
    if (be is! ValueSettingsHost) return;
    // A short interaction (the click that never opened the board) reaches a target whose box
    // has no value row as well: `FilteringBehaviour` has no amount row on most blocks.
    final short = f['interactHand'] != null;
    final targets = be.valueSettingsTargets
        .where((t) => short ? t is ShortInteractTarget : t.acceptsValueSettings)
        .toList();
    if (targets.isEmpty) return;
    // The netId is a global counter of behaviour types in Create; with one
    // candidate the index is not needed.
    final index = f['behaviourIndex'] as int;
    final target = targets.length == 1
        ? targets.single
        : targets.firstWhere((t) => t.netId == index, orElse: () => targets.first);
    if (short) {
      // A short interaction: the click that did not open the board.
      if (target is ShortInteractTarget) (target as ShortInteractTarget).onShortInteract(player);
      return;
    }
    target.setValueSettings(player, f['row'] as int, f['value'] as int, ctrlDown: f['ctrlDown'] as bool);
  });
}

/// `BlockEntityConfigurationPacket.handle`: the block entity at [pos] when the
/// player may configure it (not spectating, in adventure mode, or too far away).
Object? _blockEntityFor(Player player, (int, int, int) pos) {
  if (!KineticsRuntime.isLoaded) return null;
  final rt = KineticsRuntime.instance;
  if (player.isSpectator || player.isAdventure) return null;
  final world = player.asEntity().getWorld();
  final bp = BlockPos(x: pos.$1, y: pos.$2, z: pos.$3);
  if (!world.isLoaded(pos: bp)) return null;
  final (px, py, pz) = player.getPosition();
  final dx = px - (pos.$1 + .5);
  final dy = py - (pos.$2 + .5);
  final dz = pz - (pos.$3 + .5);
  // isWithinBlockInteractionRange(pos, 20)
  if (dx * dx + dy * dy + dz * dz > 20.0 * 20.0 + 9) return null;
  final worldId = rt.worlds.touch(world);
  return rt.store.at(worldId, bp);
}
