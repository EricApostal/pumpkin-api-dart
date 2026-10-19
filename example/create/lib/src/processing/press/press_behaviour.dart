// `PressingBehaviour` and `BeltPressingCallbacks`: the mechanical press's processing cycle,
// shared by items on belts / depots (`BeltProcessingBehaviour`), dropped items and the basin
// below it.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/host_bridge.dart';
import '../../common/pos.dart' hide pos;
import '../basin/basin_block.dart';
import '../common/stack.dart';
import '../processing_runtime.dart';
import '../transport/transport_behaviours.dart';

/// `PressingBehaviour.Mode`.
enum PressingMode { world, belt, basin }

/// `PressingBehaviour.PressingBehaviourSpecifics`: what the press itself provides.
abstract interface class PressingBehaviourSpecifics {
  /// `tryProcessInBasin(simulate)`.
  bool tryProcessInBasin({required bool simulate});

  /// `tryProcessOnBelt(input, outputList, simulate)`; [outputList] is `null` for a probe.
  bool tryProcessOnBelt(
    TransportedItemStack input,
    List<PStack>? outputList, {
    required bool simulate,
  });

  /// `tryProcessInWorld(itemEntity, simulate)`.
  bool tryProcessInWorld(EntitySnapshot item, {required bool simulate});

  /// `tryProcessInWorld(itemEntity, false)`, asynchronously (the host stack is a resource).
  Future<void> applyInWorld(EntitySnapshot item);

  /// `canProcessInBulk()`.
  bool get canProcessInBulk;

  /// `onPressingCompleted()`.
  void onPressingCompleted();

  /// `getParticleAmount()`.
  int get particleAmount;

  /// `getKineticSpeed()`.
  double get kineticSpeed;
}

/// `PressingBehaviour`.
final class PressingBehaviour extends BeltProcessingBehaviour {
  /// `CYCLE`: ticks of one pressing animation.
  static const int cycle = 240;

  /// `ENTITY_SCAN`: ticks between scans for items on the ground.
  static const int entityScan = 10;

  final PressingBehaviourSpecifics specifics;

  int prevRunningTicks = 0;
  int runningTicks = 0;
  bool running = false;
  bool finished = false;
  PressingMode mode = PressingMode.world;

  int _entityScanCooldown = entityScan;

  PressingBehaviour(this.specifics) {
    whenItemEnters(_onItemReceived);
    whileItemHeld(_whenItemHeld);
  }

  bool get inWorld => mode == PressingMode.world;
  bool get onBasin => mode == PressingMode.basin;

  /// `start(mode)`.
  void start(PressingMode mode) {
    this.mode = mode;
    running = true;
    prevRunningTicks = 0;
    runningTicks = 0;
    owner.sendData();
  }

  /// `getRunningTickSpeed`.
  int get _runningTickSpeed {
    final speed = specifics.kineticSpeed;
    if (speed == 0) return 0;
    final t = (speed.abs() / 512).clamp(0.0, 1.0);
    return (1 + (60 - 1) * t).toInt();
  }

  @override
  void tick() {
    super.tick();
    final w = owner.world;
    final p = owner.pos.toPos();

    if (!running || w == null) {
      if (w == null) return;
      if (specifics.kineticSpeed == 0) return;
      if (_entityScanCooldown > 0) _entityScanCooldown--;
      if (_entityScanCooldown > 0) return;
      _entityScanCooldown = entityScan;

      // A belt or a basin two blocks down handles the items itself.
      final below2 = owner.store.at(owner.worldId, p.belowBy(2).toBlockPos());
      if (below2?.getBehaviour<TransportedItemStackHandlerBehaviour>() != null)
        return;
      if (BasinBlock.isBasin(owner.store, owner.worldId, p.belowBy(2))) return;

      for (final snapshot in w.getEntitiesInBox(
        min: (
          p.below.$1.toDouble(),
          p.below.$2.toDouble(),
          p.below.$3.toDouble(),
        ),
        max: (p.below.$1 + 1.0, p.below.$2 + 1.0, p.below.$3 + 1.0),
        filter: const EntityFilterItems(),
      )) {
        if (!specifics.tryProcessInWorld(snapshot, simulate: true)) continue;
        start(PressingMode.world);
        return;
      }
      return;
    }

    if (runningTicks == cycle ~/ 2 && specifics.kineticSpeed != 0) {
      if (inWorld) _applyInWorld();
      if (onBasin) _applyOnBasin();
      owner.sendData();
    }

    if (runningTicks > cycle) {
      finished = true;
      running = false;
      specifics.onPressingCompleted();
      owner.sendData();
      return;
    }

    prevRunningTicks = runningTicks;
    runningTicks += _runningTickSpeed;
    if (prevRunningTicks < cycle ~/ 2 && runningTicks >= cycle ~/ 2)
      runningTicks = cycle ~/ 2;
  }

  void _applyOnBasin() {
    if (specifics.tryProcessInBasin(simulate: false)) owner.sendData();
  }

  void _applyInWorld() {
    final w = owner.world;
    if (w == null) return;
    final p = owner.pos.toPos();
    final bulk = specifics.canProcessInBulk;

    for (final snapshot in w.getEntitiesInBox(
      min: (
        p.below.$1.toDouble(),
        p.below.$2.toDouble(),
        p.below.$3.toDouble(),
      ),
      max: (p.below.$1 + 1.0, p.below.$2 + 1.0, p.below.$3 + 1.0),
      filter: const EntityFilterItems(),
    )) {
      _entityScanCooldown = 0;
      if (specifics.tryProcessInWorld(snapshot, simulate: false)) {
        // The stack of an item entity is a host resource: the application is asynchronous.
        unawaited(specifics.applyInWorld(snapshot));
        owner.sendData();
      }
      if (!bulk) break;
    }
  }

  /// `BeltPressingCallbacks.onItemReceived`.
  ProcessingResult _onItemReceived(
    TransportedItemStack transported,
    TransportedItemStackHandler inventory,
  ) {
    if (specifics.kineticSpeed == 0) return ProcessingResult.pass;
    if (running) return ProcessingResult.hold;
    if (!specifics.tryProcessOnBelt(transported, null, simulate: true))
      return ProcessingResult.pass;
    start(PressingMode.belt);
    return ProcessingResult.hold;
  }

  /// `BeltPressingCallbacks.whenItemHeld`.
  ProcessingResult _whenItemHeld(
    TransportedItemStack transported,
    TransportedItemStackHandler inventory,
  ) {
    if (specifics.kineticSpeed == 0) return ProcessingResult.pass;
    if (!running) return ProcessingResult.pass;
    if (runningTicks != cycle ~/ 2) return ProcessingResult.hold;

    final results = <PStack>[];
    if (!specifics.tryProcessOnBelt(transported, results, simulate: false))
      return ProcessingResult.pass;

    final bulk = specifics.canProcessInBulk || transported.stack.count == 1;
    transported.processedBy = null;
    transported.processingTime = 0;

    final collect = [
      for (final stack in results)
        transported.copy()
          ..stack = stack
          ..locked = true
          ..angle = transported.angle == 180
              ? 180
              : owner.store.worlds.byId(owner.worldId) == null
              ? transported.angle
              : _randomAngle(),
    ];

    if (bulk) {
      if (collect.isEmpty) {
        inventory.handleProcessingOnItem(
          transported,
          TransportedResult.removeItem(),
        );
      } else {
        inventory.handleProcessingOnItem(
          transported,
          TransportedResult.convertToAll(collect),
        );
      }
    } else {
      final left = transported.copy()..stack = transported.stack.shrink(1);
      if (collect.isEmpty) {
        inventory.handleProcessingOnItem(
          transported,
          TransportedResult.convertTo(left),
        );
      } else {
        inventory.handleProcessingOnItem(
          transported,
          TransportedResult.convertToAndLeaveHeld(collect, left),
        );
      }
    }

    owner.sendData();
    return ProcessingResult.hold;
  }

  static int _randomAngle() => ProcessingRuntime.instance.random.nextInt(360);

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putBool('Running', running);
    tag.putInt('Mode', mode.index);
    tag.putBool('Finished', finished);
    tag.putInt('Ticks', runningTicks);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    running = tag.getBool('Running') ?? false;
    final modeIndex = (tag.getInt('Mode') ?? 0).clamp(
      0,
      PressingMode.values.length - 1,
    );
    mode = PressingMode.values[modeIndex];
    finished = tag.getBool('Finished') ?? false;
    prevRunningTicks = runningTicks = tag.getInt('Ticks') ?? 0;
    super.read(tag, clientPacket: clientPacket);
  }
}
