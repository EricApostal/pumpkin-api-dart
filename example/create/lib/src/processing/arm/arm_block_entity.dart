// `ArmBlockEntity`: the mechanical arm. It stores a list of interaction points (blocks it can take
// items from or give items to), selects one per cycle and moves its held item between them.
//
// Ported from `content/kinetics/mechanicalArm/ArmBlockEntity.java`. The arm's angles and the
// dancing animation are client only; the server keeps the selection state, the held item and the
// movement progress. The interaction points are configured by a Create client through
// `create:place_arm` (see `arm_part.dart`).
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/value_settings.dart';
import '../../common/common.dart' hide pos;
import '../../common/host_bridge.dart';
import '../../contraptions/core/nbt_map.dart';
import '../support/kinetics_bridge.dart';
import '../common/stack.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import 'arm_interaction_point.dart';
import 'arm_model.dart';
import 'arm_point_types.dart';

/// `ArmBlockEntity`.
final class ArmBlockEntity extends KineticBlockEntity
    implements ValueSettingsHost, ValueSettingsTarget {
  ArmBlockEntity(super.worldId, super.pos) {
    lazyTickRate = 10;
  }

  /// The points the arm takes items from (`Mode.TAKE`).
  final List<ArmInteractionPoint> inputs = [];

  /// The points the arm gives items to (`Mode.DEPOSIT`).
  final List<ArmInteractionPoint> outputs = [];

  /// The raw `InteractionPoints` list; the points are rebuilt from it when it changes.
  List<NbtMap>? interactionPointTag;

  bool _updateInteractionPoints = true;

  /// `heldItem`.
  PStack heldItem = PStack.empty;

  /// `phase`.
  ArmPhase phase = ArmPhase.searchInputs;

  /// `goggles`.
  bool goggles = false;

  /// `redstoneLocked`.
  bool redstoneLocked = false;

  /// `chasedPointIndex`.
  int chasedPointIndex = -1;

  /// `chasedPointProgress`.
  double chasedPointProgress = 0;

  int lastInputIndex = -1;
  int lastOutputIndex = -1;

  /// `selectionMode`.
  ArmSelectionMode selectionMode = ArmSelectionMode.roundRobin;

  bool _busy = false;
  bool _redstonePolling = false;

  ProcessingRuntime get _rt => ProcessingRuntime.instance;

  ArmWorld get armWorld => ArmWorld.of(world, worldId);

  /// `ArmBlockEntity.getRange`.
  int get range =>
      _rt.configs?.server.logistics.mechanicalArmRange.value ?? defaultArmRange;

  // -- Value settings (`create:value_settings`) ------------------------------------------------

  @override
  List<ValueSettingsTarget> get valueSettingsTargets => [this];

  @override
  int get netId => 0;

  @override
  bool get acceptsValueSettings => true;

  @override
  (int, int) get valueSettings => (0, selectionMode.index);

  @override
  void setValueSettings(
    Player? player,
    int row,
    int value, {
    required bool ctrlDown,
  }) {
    selectionMode = ArmSelectionMode.fromOrdinal(value);
    markDirty();
    sendData();
  }

  // -- Ticking --------------------------------------------------------------------------------

  @override
  void tick() {
    super.tick();
    _initInteractionPoints();
    final targetReached = _tickMovementProgress();

    if (chasedPointProgress < 1) {
      if (phase == ArmPhase.moveToInput) {
        _targetedPoint()?.keepAlive();
      }
      return;
    }

    _run(() async {
      if (phase == ArmPhase.moveToInput) {
        await collectItem();
      } else if (phase == ArmPhase.moveToOutput) {
        await depositItem();
      } else if (phase == ArmPhase.searchInputs || phase == ArmPhase.dancing) {
        await searchForItem();
      }
      if (targetReached) lazyTick();
    });
  }

  @override
  void lazyTick() {
    super.lazyTick();
    if (chasedPointProgress < .5) return;
    if (phase == ArmPhase.searchInputs || phase == ArmPhase.dancing) {
      checkForMusic();
    }
    if (phase == ArmPhase.searchOutputs) _run(searchForDestination);
  }

  @override
  void onRemoved() {
    final held = heldItem;
    final world = this.world;
    if (held.isNotEmpty && world != null) {
      unawaited(_drop(world, held));
    }
    heldItem = PStack.empty;
    super.onRemoved();
  }

  Future<void> _drop(World world, PStack stack) async {
    final item = await HostStacks.write(stack);
    if (item == null) return;
    try {
      await world.dropItem(pos.toPos().center, item);
    } finally {
      item.dispose();
    }
  }

  bool _tickMovementProgress() {
    final reachedBefore = chasedPointProgress >= 1;
    chasedPointProgress += math.min(256.0, speed.abs()) / 1024;
    if (chasedPointProgress > 1) chasedPointProgress = 1;
    return !reachedBefore && chasedPointProgress >= 1;
  }

  void _run(Future<void> Function() body) => unawaited(_guard(body));

  Future<void> _guard(Future<void> Function() body) async {
    if (_busy) return;
    _busy = true;
    try {
      await body();
    } catch (e, s) {
      _rt.log.error(
        'The mechanical arm at $pos failed',
        error: e,
        stackTrace: s,
      );
    } finally {
      _busy = false;
    }
  }

  // -- Interaction points ---------------------------------------------------------------------

  /// `initInteractionPoints`.
  void _initInteractionPoints() {
    final tag = interactionPointTag;
    if (!_updateInteractionPoints || tag == null) return;
    if (!_isAreaLoaded(pos.toPos(), range + 1)) return;

    inputs.clear();
    outputs.clear();
    final level = armWorld;
    for (final entry in tag) {
      final point = ArmInteractionPoint.deserialize(
        entry,
        level,
        pos.toPos(),
        armPointTypeOf,
      );
      if (point == null) continue;
      if (point.mode == ArmPointMode.deposit) {
        outputs.add(point);
      } else {
        inputs.add(point);
      }
    }

    _updateInteractionPoints = false;
    sendData();
    markDirty();
  }

  bool _isAreaLoaded(Pos center, int r) {
    final world = this.world;
    if (world == null) return false;
    return world.isAreaLoaded(
      min: BlockPos(x: center.$1 - r, y: center.$2 - r, z: center.$3 - r),
      max: BlockPos(x: center.$1 + r, y: center.$2 + r, z: center.$3 + r),
    );
  }

  /// `getTargetedInteractionPoint`.
  ArmInteractionPoint? _targetedPoint() {
    if (chasedPointIndex == -1) return null;
    if (phase == ArmPhase.moveToInput && chasedPointIndex < inputs.length) {
      return inputs[chasedPointIndex];
    }
    if (phase == ArmPhase.moveToOutput && chasedPointIndex < outputs.length) {
      return outputs[chasedPointIndex];
    }
    return null;
  }

  /// `searchForItem`.
  Future<void> searchForItem() async {
    if (redstoneLocked) return;

    var found = false;
    final start = armScanStart(selectionMode, lastInputIndex);
    final scanRange = armScanRange(
      selectionMode,
      lastInputIndex,
      inputs.length,
    );
    for (var i = start; i < scanRange; i++) {
      final point = inputs[i];
      if (!point.isValid) continue;
      final slots = point.slotCount(this);
      for (var j = 0; j < slots; j++) {
        if (await _distributableAmount(point, j) == 0) continue;
        _selectIndex(true, i);
        found = true;
        break;
      }
      if (found) break;
    }

    if (!found && selectionMode == ArmSelectionMode.roundRobin) {
      lastInputIndex = -1;
    }
    if (lastInputIndex == inputs.length - 1) lastInputIndex = -1;
  }

  /// `searchForDestination`.
  Future<void> searchForDestination() async {
    final held = heldItem;
    var found = false;
    final start = armScanStart(selectionMode, lastOutputIndex);
    final scanRange = armScanRange(
      selectionMode,
      lastOutputIndex,
      outputs.length,
    );
    for (var i = start; i < scanRange; i++) {
      final point = outputs[i];
      if (!point.isValid) continue;
      final remainder = await point.insert(this, held, true);
      if (remainder == held) continue;
      _selectIndex(false, i);
      found = true;
      break;
    }

    if (!found && selectionMode == ArmSelectionMode.roundRobin) {
      lastOutputIndex = -1;
    }
    if (lastOutputIndex == outputs.length - 1) lastOutputIndex = -1;
  }

  /// `selectIndex`.
  void _selectIndex(bool input, int index) {
    phase = input ? ArmPhase.moveToInput : ArmPhase.moveToOutput;
    chasedPointIndex = index;
    chasedPointProgress = 0;
    if (input) {
      lastInputIndex = index;
    } else {
      lastOutputIndex = index;
    }
    sendData();
    markDirty();
  }

  /// `getDistributableAmount`.
  Future<int> _distributableAmount(ArmInteractionPoint point, int slot) async {
    final stack = await point.extract(this, slot, 64, true);
    final remainder = await _simulateInsertion(stack);
    if (stack.sameItem(remainder)) return stack.count - remainder.count;
    return stack.count;
  }

  Future<PStack> _simulateInsertion(PStack stack) async {
    var rest = stack;
    for (final point in outputs) {
      if (point.isValid) rest = await point.insert(this, rest, true);
      if (rest.isEmpty) break;
    }
    return rest;
  }

  /// `depositItem`.
  Future<void> depositItem() async {
    final point = _targetedPoint();
    if (point != null && point.isValid) {
      heldItem = await point.insert(this, heldItem, false);
    }

    phase = heldItem.isEmpty ? ArmPhase.searchInputs : ArmPhase.searchOutputs;
    chasedPointProgress = 0;
    chasedPointIndex = -1;
    sendData();
    markDirty();
  }

  /// `collectItem`.
  Future<void> collectItem() async {
    final point = _targetedPoint();
    if (point != null && point.isValid) {
      final slots = point.slotCount(this);
      for (var i = 0; i < slots; i++) {
        final amount = await _distributableAmount(point, i);
        if (amount == 0) continue;

        final previous = heldItem;
        heldItem = await point.extract(this, i, amount, false);
        phase = ArmPhase.searchOutputs;
        chasedPointProgress = 0;
        chasedPointIndex = -1;
        sendData();
        markDirty();

        if (!heldItem.sameItem(previous)) {
          final world = this.world;
          world?.playSound(
            sound: Sound.entityItemPickup,
            category: SoundCategory.blocks,
            pos: pos.toPos().center,
            volume: .125,
            pitch: .5 + _rt.random.nextDouble() * .25,
          );
        }
        return;
      }
    }

    phase = ArmPhase.searchInputs;
    chasedPointProgress = 0;
    chasedPointIndex = -1;
    sendData();
    markDirty();
  }

  /// `checkForMusic`: a jukebox with a disc makes the arm dance.
  void checkForMusic() {
    final hasMusic = _musicAmong(inputs) || _musicAmong(outputs);
    if (hasMusic != (phase == ArmPhase.dancing)) {
      phase = hasMusic ? ArmPhase.dancing : ArmPhase.searchInputs;
      markDirty();
      sendData();
    }
  }

  bool _musicAmong(List<ArmInteractionPoint> points) {
    for (final point in points) {
      if (point is! JukeboxPoint) continue;
      point.updateCachedState();
      if (point.cachedState.flag('has_record')) return true;
    }
    return false;
  }

  /// `redstoneUpdate`.
  void redstoneUpdate() {
    if (_redstonePolling) return;
    final world = this.world;
    if (world == null) return;
    _redstonePolling = true;
    unawaited(() async {
      try {
        final powered = await world.hasNeighborSignal(pos: pos);
        if (powered == redstoneLocked) return;
        redstoneLocked = powered;
        sendData();
        if (!redstoneLocked) await searchForItem();
      } on Object {
        // the world is going away
      } finally {
        _redstonePolling = false;
      }
    }());
  }

  /// `clearContent`.
  void clearContent() => heldItem = PStack.empty;

  /// `ArmPlacementPacket.handle`: replaces the interaction points and rebuilds them.
  void setInteractionPoints(List<NbtMap> tag) {
    interactionPointTag = tag;
    _updateInteractionPoints = true;
    markDirty();
    sendData();
  }

  // -- Persistence ----------------------------------------------------------------------------

  /// `writeInteractionPoints`.
  void _writeInteractionPoints(NbtCompound tag) {
    final raw = interactionPointTag;
    if (_updateInteractionPoints && raw != null) {
      tag.putList('InteractionPoints', [
        for (final entry in raw) _pointCompound(entry),
      ]);
      return;
    }
    tag.putList('InteractionPoints', [
      for (final point in inputs) _pointCompound(point.serialize(pos.toPos())),
      for (final point in outputs) _pointCompound(point.serialize(pos.toPos())),
    ]);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    _writeInteractionPoints(tag);
    tag.putString('Phase', phase.javaName);
    tag.putBool('Powered', redstoneLocked);
    tag.putBool('Goggles', goggles);
    tag.putInt('SelectionMode', selectionMode.index);
    tag.putCompound('HeldItem', StackNbt.write(heldItem));
    tag.putInt('TargetPointIndex', chasedPointIndex);
    tag.putFloat('MovementProgress', chasedPointProgress);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    final hadPoints = interactionPointTag?.length;
    super.read(tag, clientPacket: clientPacket);
    heldItem = StackNbt.read(tag.getCompound('HeldItem'));
    phase = ArmPhase.fromJavaName(tag.getString('Phase'));
    chasedPointIndex = tag.getInt('TargetPointIndex') ?? 0;
    chasedPointProgress = tag.getDouble('MovementProgress') ?? 0;
    redstoneLocked = tag.getBool('Powered') ?? false;
    goggles = tag.getBool('Goggles') ?? false;
    selectionMode = ArmSelectionMode.fromOrdinal(
      tag.getInt('SelectionMode') ?? 0,
    );

    final points = tag.getList('InteractionPoints');
    if (points != null) {
      interactionPointTag = [
        for (final e in points)
          if (e is NbtCompound) _pointMap(e),
      ];
    }
    if (hadPoints == null || hadPoints != interactionPointTag?.length) {
      _updateInteractionPoints = true;
    }
  }

  /// A saved interaction point as the pure map the point logic reads.
  static NbtMap _pointMap(NbtCompound compound) => NbtMap()
    ..putString('Type', compound.getString('Type') ?? '')
    ..putIntArray('Pos', compound.getIntArray('Pos') ?? const [0, 0, 0])
    ..putString('Mode', compound.getString('Mode') ?? 'DEPOSIT');

  /// An interaction point as the host compound the client reads.
  static NbtCompound _pointCompound(NbtMap map) => NbtCompound()
    ..putString('Type', map.getString('Type'))
    ..putIntArray('Pos', map.getIntArray('Pos'))
    ..putString('Mode', map.getString('Mode'));

  @override
  String toString() => 'MechanicalArm${super.toString()}';
}
