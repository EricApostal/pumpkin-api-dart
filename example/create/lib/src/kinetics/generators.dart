// The generators: creative motor, hand crank, valve handles, water wheels,
// powered shaft (steam engine output) and the steam engine itself.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/value_settings.dart';
import 'behaviours.dart';
import 'fluid_flow.dart';
import 'geometry.dart';
import 'kinetic_block_entity.dart';
import 'sequence.dart';
import 'settings.dart';

// -- Creative motor -----------------------------------------------------------------

/// `CreativeMotorBlockEntity`.
class CreativeMotorBlockEntity extends GeneratingKineticBlockEntity implements ValueSettingsHost {
  static const int defaultSpeed = 16;
  static const int maxSpeed = 256;

  late final ScrollValueBehaviour generatedSpeedValue;

  CreativeMotorBlockEntity(super.worldId, super.pos) {
    generatedSpeedValue = addBehaviour(
      KineticScrollValueBehaviour()
        ..between(-maxSpeed, maxSpeed)
        ..value = defaultSpeed
        ..withCallback((_) => updateGeneratedRotation()),
    );
  }

  @override
  List<ValueSettingsTarget> get valueSettingsTargets => [generatedSpeedValue];

  @override
  void onKineticInitialize() {
    if (!hasSource || generatedSpeed > theoreticalSpeed) updateGeneratedRotation();
  }

  @override
  double get generatedSpeed {
    final state = blockState;
    if (!state.isCreate('creative_motor')) return 0;
    return convertToDirection(generatedSpeedValue.getValue().toDouble(), state.dirOf('facing') ?? Dir.north);
  }
}

// -- Hand crank -----------------------------------------------------------------------

/// `HandCrankBlockEntity`.
class HandCrankBlockEntity extends GeneratingKineticBlockEntity {
  int inUse = 0;
  bool backwards = false;

  HandCrankBlockEntity(super.worldId, super.pos);

  /// `HandCrankBlock.getRotationSpeed()`.
  int get rotationSpeed => 32;

  /// `turn(back)`: a player turned the crank.
  void turn(bool back) {
    var update = false;

    if (generatedSpeed == 0 || back != backwards) update = true;

    inUse = 10;
    backwards = back;
    if (update) updateGeneratedRotation();
  }

  @override
  double get generatedSpeed {
    final state = blockState;
    if (!state.has('facing')) return 0;
    final speed = (inUse == 0 ? 0 : (clockwise ? -1 : 1)) * rotationSpeed;
    return convertToDirection(speed.toDouble(), state.dirOf('facing') ?? Dir.up);
  }

  bool get clockwise => backwards;

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putInt('InUse', inUse);
    tag.putBool('Backwards', backwards);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    inUse = tag.getInt('InUse') ?? 0;
    backwards = tag.getBool('Backwards') ?? false;
    super.read(tag, clientPacket: clientPacket);
  }

  @override
  void tick() {
    super.tick();

    if (inUse > 0) {
      inUse--;

      if (inUse == 0) {
        sequenceContext = null;
        updateGeneratedRotation();
      }
    }
  }

  @override
  String get stressConfigKey {
    final s = blockState;
    return s.isCreate('hand_crank') ? s.block : 'create:copper_valve_handle';
  }
}

/// `ValveHandleBlockEntity`: turns a fixed angle per use.
class ValveHandleBlockEntity extends HandCrankBlockEntity implements ValueSettingsHost {
  late final ScrollValueBehaviour angleInput;
  int cooldown = 0;
  int startAngle = 0;
  int targetAngle = 0;
  int totalUseTicks = 0;

  ValveHandleBlockEntity(super.worldId, super.pos) {
    angleInput = addBehaviour(
      ValveHandleScrollValueBehaviour()
        ..between(-180, 180)
        ..onlyActiveWhen(() => inUse == 0),
    );
    angleInput.value = 45;
  }

  @override
  List<ValueSettingsTarget> get valueSettingsTargets => [angleInput];

  @override
  bool get clockwise => (angleInput.getValue() < 0) ^ backwards;

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putInt('TotalUseTicks', totalUseTicks);
    tag.putInt('StartAngle', startAngle);
    tag.putInt('TargetAngle', targetAngle);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    totalUseTicks = tag.getInt('TotalUseTicks') ?? 0;
    startAngle = tag.getInt('StartAngle') ?? 0;
    targetAngle = tag.getInt('TargetAngle') ?? 0;
  }

  @override
  void tick() {
    super.tick();
    if (inUse == 0 && cooldown > 0) cooldown--;
  }

  /// `activate(sneak)`: starts a turn; returns whether it did.
  bool activate(bool sneak) {
    if (theoreticalSpeed != 0) return false;
    if (inUse > 0 || cooldown > 0) return false;

    // Always overshoot, the target will stop early.
    final value = angleInput.getValue();
    final target = value.abs();
    final speed = rotationSpeed;
    final degreesPerTick = convertToAngular(speed.toDouble());
    inUse = (target / degreesPerTick).ceil() + 2;

    startAngle = 0; // independentAngle is only animated on the client
    targetAngle = (((startAngle + (target > 135 ? 180 : 90) * value.sign) / 90).round()) * 90;
    totalUseTicks = inUse;
    backwards = sneak;

    sequenceContext = SequenceContext.fromGearshift(SequencerInstructions.turnAngle, speed.toDouble(), target);
    updateGeneratedRotation();
    cooldown = 4;

    return true;
  }
}

// -- Water wheels -----------------------------------------------------------------------

/// A [FluidWorldView] over a host world, caching reads for one evaluation.
final class HostFluidView implements FluidWorldView {
  final World world;
  final Map<int, FluidInfo> _fluids = {};
  final Map<int, BlockState> _states = {};

  HostFluidView(this.world);

  int _key(int x, int y, int z) => (x & 0x3FFFFFF) << 38 | (z & 0x3FFFFFF) << 12 | (y & 0xFFF);

  @override
  FluidInfo fluidAt(int x, int y, int z) => _fluids.putIfAbsent(_key(x, y, z), () {
    final f = world.fluidAt(BlockPos(x: x, y: y, z: z));
    if (f == null) return FluidInfo.empty;
    return FluidInfo(f.fluid, f.level, isSource: f.isSource, isFalling: f.isFalling);
  });

  BlockState _state(int x, int y, int z) =>
      _states.putIfAbsent(_key(x, y, z), () => world.getBlockState(pos: BlockPos(x: x, y: y, z: z)));

  @override
  bool blocksMotion(int x, int y, int z) {
    final s = _state(x, y, z);
    return s.isSolid && s.blockName != 'minecraft:cobweb' && s.blockName != 'minecraft:bamboo_sapling';
  }

  @override
  bool isFaceSturdy(int x, int y, int z, Dir face) {
    final s = _state(x, y, z);
    return switch (face) {
      Dir.down => s.downSideSolid,
      Dir.up => s.upSideSolid,
      Dir.north => s.northSideSolid,
      Dir.south => s.southSideSolid,
      Dir.west => s.westSideSolid,
      Dir.east => s.eastSideSolid,
    };
  }

  @override
  String blockAt(int x, int y, int z) => _state(x, y, z).blockName;

  @override
  bool bubbleColumnDragDown(int x, int y, int z) {
    final info = BlockRegistry.stateInfo(_state(x, y, z).id);
    if (info == null) return false;
    for (final (k, v) in info.properties) {
      if (k == 'drag') return v == 'true';
    }
    return false;
  }
}

/// `WaterWheelBlockEntity`.
class WaterWheelBlockEntity extends GeneratingKineticBlockEntity {
  int flowScore = 0;
  KState material = const KState('minecraft:spruce_planks');

  WaterWheelBlockEntity(super.worldId, super.pos) {
    lazyTickRate = 60;
  }

  /// 1 for the small wheel, 2 for the large one.
  int get size => 1;

  KAxis get axis => runtime.blocks.defFor(blockState)?.rotationAxis(blockState) ?? KAxis.x;

  @override
  void lazyTick() {
    super.lazyTick();
    // Water can change flow direction without notifying neighbours.
    determineAndApplyFlowScore();
  }

  /// `determineAndApplyFlowScore()`.
  void determineAndApplyFlowScore() {
    final w = world;
    if (w == null) return;
    final result = waterWheelFlowScore(HostFluidView(w), pos.x, pos.y, pos.z, axis, size);
    if (result.score != 0) onWheelTurns(lava: result.lava);
    setFlowScoreAndUpdate(result.score);
  }

  /// Hook for the water / lava wheel advancements.
  static void Function(WaterWheelBlockEntity wheel, {required bool lava})? onWheelTurnsHook;

  void onWheelTurns({required bool lava}) => onWheelTurnsHook?.call(this, lava: lava);

  void setFlowScoreAndUpdate(int score) {
    if (flowScore == score) return;
    flowScore = score;
    updateGeneratedRotation();
    markChanged();
  }

  /// `applyMaterialIfValid(stack)`: a plank type in `create:water_wheel_planks`
  /// retextures the wheel. [itemKey] is the held item; returns whether it applied.
  bool applyMaterialIfValid(String itemKey) {
    final candidate = KState(itemKey.contains(':') ? itemKey : 'minecraft:$itemKey');
    if (candidate == material) return false;
    if (!Tags.block(candidate.block, 'create:water_wheel_planks')) return false;
    final id = runtime.states.idOf(candidate);
    if (id == null) return false;
    material = runtime.states.decode(id);
    markChanged();
    sendData();
    return true;
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    flowScore = tag.getInt('FlowScore') ?? 0;

    final m = tag.getCompound('Material');
    if (m == null) return;
    final name = m.getString('Name') ?? 'minecraft:air';
    final props = <String, String>{};
    final p = m.getCompound('Properties');
    if (p != null) {
      for (final k in p.keys) {
        final v = p.getString(k);
        if (v != null) props[k] = v;
      }
    }
    material = name == 'minecraft:air' ? const KState('minecraft:spruce_planks') : KState(name, props);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putInt('FlowScore', flowScore);
    final m = NbtCompound()..putString('Name', material.block);
    if (material.props.isNotEmpty) {
      final p = NbtCompound();
      for (final e in material.props.entries) {
        p.putString(e.key, e.value);
      }
      m.putCompound('Properties', p);
    }
    tag.putCompound('Material', m);
  }

  @override
  double get generatedSpeed => (flowScore.clamp(-1, 1) * 8 ~/ size).toDouble();
}

/// `LargeWaterWheelBlockEntity`.
class LargeWaterWheelBlockEntity extends WaterWheelBlockEntity {
  LargeWaterWheelBlockEntity(super.worldId, super.pos);

  @override
  int get size => 2;
}

// -- Steam engine -------------------------------------------------------------------------

/// `PoweredShaftBlockEntity`: the shaft a steam engine drives.
class PoweredShaftBlockEntity extends GeneratingKineticBlockEntity {
  KPos? enginePos;
  double engineEfficiency = 0;
  int movementDirection = 1;
  int initialTicks = 3;

  /// The block key of the engine (its stress capacity is used).
  String? capacityKey;

  PoweredShaftBlockEntity(super.worldId, super.pos);

  @override
  void tick() {
    super.tick();
    if (initialTicks > 0) initialTicks--;
  }

  /// `update(sourcePos, direction, efficiency)`.
  void update(KPos sourcePos, int direction, double efficiency, {String? engineBlock}) {
    final key = kpos - sourcePos;
    enginePos = key;
    final prev = engineEfficiency;
    engineEfficiency = efficiency;
    final prevDirection = movementDirection;
    if ((efficiency - prev).abs() < 1e-5 && prevDirection == direction) return;

    capacityKey = engineBlock ?? level.stateAt(sourcePos).block;
    movementDirection = direction;
    updateGeneratedRotation();
  }

  /// `remove(sourcePos)`: the engine is gone.
  void removeEngine(KPos sourcePos) {
    if (!isPoweredBy(sourcePos)) return;

    enginePos = null;
    engineEfficiency = 0;
    movementDirection = 0;
    capacityKey = null;
    updateGeneratedRotation();
  }

  bool canBePoweredBy(KPos globalPos) => initialTicks == 0 && (enginePos == null || isPoweredBy(globalPos));

  bool isPoweredBy(KPos globalPos) => (kpos - globalPos) == enginePos;

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putInt('Direction', movementDirection);
    if (initialTicks > 0) tag.putInt('Warmup', initialTicks);
    final ep = enginePos;
    final ck = capacityKey;
    if (ep != null && ck != null) {
      tag.putIntArray('EnginePos', [ep.x, ep.y, ep.z]);
      tag.putFloat('EnginePower', engineEfficiency);
      tag.putString('EngineType', ck);
    }
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    movementDirection = tag.getInt('Direction') ?? 0;
    initialTicks = tag.getInt('Warmup') ?? 0;
    enginePos = null;
    engineEfficiency = 0;

    final ep = tag.getIntArray('EnginePos');
    if (ep != null && ep.length >= 3) {
      enginePos = KPos(ep[0], ep[1], ep[2]);
      engineEfficiency = tag.getDouble('EnginePower') ?? 0;
      capacityKey = tag.getString('EngineType');
    }
  }

  @override
  double get generatedSpeed => combinedCapacity > 0 ? movementDirection * 16.0 * speedModifier : 0;

  double get combinedCapacity {
    final key = capacityKey;
    return key == null ? 0 : engineEfficiency * runtime.stress.capacity(key);
  }

  int get speedModifier => (1 + (engineEfficiency >= 1 ? 3 : (engineEfficiency * 4).floor().clamp(0, 2))).toInt();

  @override
  double calculateAddedStressCapacity() {
    final capacity = combinedCapacity / speedModifier;
    lastCapacityProvided = capacity;
    return capacity;
  }
}
