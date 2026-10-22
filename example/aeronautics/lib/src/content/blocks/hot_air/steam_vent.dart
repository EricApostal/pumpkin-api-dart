// The steam vent: a boiler accessory that turns steam engine heat into hot air.
//
// Java: `content/blocks/hot_air/steam_vent/{SteamVentBlock,SteamVentBlockEntity}`.
//
// A vent may only sit on a fluid tank (`SteamEngineBlock.canAttach(level, pos,
// DOWN)`). Its output is `steam_amount * boiler_efficiency * signal / 15`, and the
// signal is not its own: every vent of one tank shares the strongest redstone
// signal any of them sees. That sharing is the [SteamVentLogic.signalSync] walk,
// and it is pure.
//
// Pure part: no host imports. The block entity is at the bottom of the file.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:create/create.dart';
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/fluids/fluid_tank.dart' show FluidTankBlockEntity;
import 'package:create/src/kinetics/behaviours.dart' show ScrollValueBehaviour;
import 'package:create/src/kinetics/geometry.dart' show KState;
import 'package:create/src/kinetics/runtime.dart' show KineticsRuntime;
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart' show Vector3d;

import '../../../aeronautics_hooks.dart';

import '../../../config/aero_config.dart';
import '../../../hot_air/balloon.dart';
import '../../../hot_air/balloon_world.dart';
import '../../../hot_air/lifting_gas.dart';
import '../../../hot_air/lifting_gas_provider.dart';
import '../../../hot_air/server_balloon.dart';
import '../../../host/world_balloon_world.dart';
import '../../../propeller/geometry.dart' show segmentBlocked;

/// The block and block entity key (`aeronautics:steam_vent`).
const String steamVentKey = 'aeronautics:steam_vent';

/// `SteamVentBlock.Variant`: the sheet metal the vent is made of.
enum SteamVentVariant {
  gold('gold'),
  iron('iron');

  const SteamVentVariant(this.serializedName);

  final String serializedName;

  /// `Variant.getConversionFromItem`: a gold or iron sheet converts the vent.
  static SteamVentVariant? fromItemTags(bool goldSheet, bool ironSheet) {
    if (goldSheet) return gold;
    if (ironSheet) return iron;
    return null;
  }

  static SteamVentVariant byName(String? name) =>
      name == iron.serializedName ? iron : gold;
}

/// `SteamVentBlockEntity`'s server state, without the host.
final class SteamVentLogic {
  /// `signalStrength`: the shared signal the vents of one tank settled on.
  int signalStrength = 0;

  /// `rawSignalStrength`: this vent's own redstone signal.
  int rawSignalStrength = 0;

  /// `efficiency`: the boiler's engine efficiency, 0 to 1.
  double efficiency = 0;

  /// `maxCapacity`: the top of the scroll value, from the config.
  int maxCapacity = 5000;

  /// The scroll value the player set (`steamAmountBehaviour`).
  int steamAmount = 5000;

  /// `getGasOutput`: `steamAmount * efficiency * (signal / 15)`.
  double get gasOutput => steamAmount * efficiency * (signalStrength / 15.0);

  /// `canOutputGas`: a heated boiler and a signal.
  bool get canOutputGas => efficiency > 0 && signalStrength > 0;

  /// `inTankBounds`: whether [pos] is inside the tank column of [controller].
  static bool inTankBounds(Pos pos, Pos controllerPos, int width) {
    final minX = controllerPos.$1;
    final minZ = controllerPos.$3;
    return pos.$1 >= minX && pos.$1 < minX + width && pos.$3 >= minZ && pos.$3 < minZ + width;
  }

  /// `searchSignalSync`: the strongest raw signal of the vents reachable from
  /// [from] through the tank, walking horizontally.
  ///
  /// [ventAt] answers the raw signal of a vent at a position (`null` when there is
  /// no vent), and [inBounds] answers [`inTankBounds`] for the tank.
  static int searchSignalSync({
    required Pos from,
    required int ownRawSignal,
    required int? Function(Pos pos) ventRawSignalAt,
    required bool Function(Pos pos) inBounds,
  }) {
    var maxRaw = ownRawSignal;
    final visited = <Pos>{from};
    final queue = <Pos>[from];

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final dir in const [(1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1)]) {
        final next = (current.$1 + dir.$1, current.$2 + dir.$2, current.$3 + dir.$3);
        if (!inBounds(next) || !visited.add(next)) continue;
        final raw = ventRawSignalAt(next);
        if (raw == null) continue;
        if (raw > maxRaw) maxRaw = raw;
        queue.add(next);
      }
    }
    return maxRaw;
  }

  /// `tick`'s efficiency read: `Mth.clamp(engineEfficiency, 0, 1)`.
  static double efficiencyOf(double engineEfficiency) =>
      engineEfficiency < 0 ? 0 : (engineEfficiency > 1 ? 1 : engineEfficiency);

  /// `updateSignal`: whether the shared signal changed (the caller then syncs).
  bool updateSignal(int signal) {
    if (signal == signalStrength) return false;
    signalStrength = signal;
    return true;
  }

  /// `updateRawSignal`: whether this vent's own signal changed.
  bool updateRawSignal(int signal) {
    if (signal == rawSignalStrength) return false;
    rawSignalStrength = signal;
    return true;
  }

  Map<String, Object?> toMap() => {
    'SignalStrength': signalStrength,
    'RawSignalStrength': rawSignalStrength,
    'SteamAmount': steamAmount,
  };

  void readMap(Map<String, Object?> map) {
    signalStrength = (map['SignalStrength'] as num?)?.toInt() ?? 0;
    rawSignalStrength = (map['RawSignalStrength'] as num?)?.toInt() ?? 0;
    steamAmount = (map['SteamAmount'] as num?)?.toInt() ?? maxCapacity;
  }
}

/// `SteamVentBlockEntity`.
final class SteamVentBlockEntity extends CreateBlockEntity with BlockEntityLiftingGasProvider {
  SteamVentBlockEntity(super.worldId, super.pos) {
    lazyTickRate = 20;
  }

  /// The pure state.
  final SteamVentLogic logic = SteamVentLogic();

  Balloon? _balloon;
  Pos? _castPosition;
  ClientBalloonInfo? _clientBalloonInfo;
  int _ticksSinceSync = 0;

  /// The tank this vent stands on, cached (`source`).
  FluidTankBlockEntity? _source;

  /// The scroll value the player sets (`steamAmountBehaviour`).
  ScrollValueBehaviour? get steamAmountBehaviour => getBehaviour<ScrollValueBehaviour>();

  /// The state of the block as plain data (`getBlockState()`).
  BState get bState {
    final w = world;
    if (w == null) return BState.air;
    return HostBlockGetter.stateOfId(w.getBlockStateId(pos: pos));
  }

  /// `getClientPredictedVolume`: the fill level between updates.
  double get clientPredictedVolume => _clientBalloonInfo == null
      ? 0
      : BlockEntityLiftingGasProvider.getPredictedVolume(_clientBalloonInfo!, _ticksSinceSync);

  @override
  Balloon? get balloon => _balloon;

  @override
  set balloon(Balloon? value) => _balloon = value;

  @override
  Pos? get castPosition => _castPosition;

  @override
  BalloonWorld get balloonWorld => balloonWorldOf(world!);

  @override
  Pos get blockPos => (pos.x, pos.y, pos.z);

  @override
  LiftingGasType get liftingGasType => const SteamLiftingGas();

  @override
  double get gasOutput => logic.gasOutput;

  @override
  bool get canOutputGas => logic.canOutputGas && !removed;

  @override
  bool get isChunkUnloaded => world == null;

  @override
  ClientBalloonInfo? get clientBalloonInfo => _clientBalloonInfo;

  @override
  void onLoad() {
    logic.maxCapacity = AeroConfig.server.blocks.steamVentMaxHotAir;
    final behaviour = addBehaviour(ScrollValueBehaviour());
    behaviour
      ..between(50, logic.maxCapacity)
      ..value = logic.maxCapacity;
    logic.steamAmount = logic.maxCapacity;
    super.onLoad();
    _cacheTank();
    if (canOutputGas) tickBalloonLogic();
  }

  @override
  void initialize() {
    super.initialize();
    if (canOutputGas) tickBalloonLogic();
  }

  @override
  void tick() {
    super.tick();
    _ticksSinceSync++;

    final controller = _source?.controllerBe;
    logic.efficiency = controller == null
        ? 0
        : SteamVentLogic.efficiencyOf(controller.boiler.getEngineEfficiency(controller.totalTankSize));

    final scroll = steamAmountBehaviour;
    if (scroll != null) logic.steamAmount = scroll.value;
  }

  @override
  void lazyTick() {
    super.lazyTick();
    _cacheTank();
    if (canOutputGas) tickBalloonLogic();
  }

  @override
  void onRemoved() {
    removeFromBalloon();
    super.onRemoved();
  }

  /// `getAndCacheTank`: the tank directly below, re-read when it went away.
  void _cacheTank() {
    final cached = _source;
    if (cached != null && !cached.removed) return;
    final below = store.at(worldId, BlockPos(x: pos.x, y: pos.y - 1, z: pos.z));
    _source = below is FluidTankBlockEntity ? below : null;
  }

  /// `updateRawSignal`: re-reads this vent's own signal, sets `POWERED` and
  /// re-shares the signal with the rest of the tank.
  Future<bool> updateRawSignal() async {
    final w = world;
    if (w == null) return false;
    final strength = await w.getBestNeighborSignal(pos: pos);
    final changed = logic.updateRawSignal(strength);

    if (changed) {
      final current = bState;
      final powered = strength > 0;
      if (current.flag('powered') != powered) {
        final id = KineticsRuntime.instance.states.idOf(
          KState(current.key, {...current.props, 'powered': '$powered'}),
        );
        if (id != null) {
          unawaited(w.setBlockState(pos: pos, state: id, updateFlags: BlockUpdateFlags.normal));
        }
      }
      signalSync();
    }
    return changed;
  }

  /// `signalSync`: every vent of the tank takes the strongest raw signal.
  void signalSync() {
    final controller = _source?.controllerBe;
    if (controller == null) return;

    final controllerPos = controller.controllerPos;
    final width = controller.width;
    final maxRaw = SteamVentLogic.searchSignalSync(
      from: blockPos,
      ownRawSignal: logic.rawSignalStrength,
      inBounds: (p) => SteamVentLogic.inTankBounds(p, controllerPos, width),
      ventRawSignalAt: (p) {
        final be = store.at(worldId, BlockPos(x: p.$1, y: p.$2, z: p.$3));
        return be is SteamVentBlockEntity ? be.logic.rawSignalStrength : null;
      },
    );

    _applySignalToTank(controller, maxRaw);
  }

  /// The half of `signalSync` that writes: Java collects the vents first, then
  /// calls `updateSignal` on each; the walk above already visited exactly those.
  void _applySignalToTank(FluidTankBlockEntity controller, int maxRaw) {
    final controllerPos = controller.controllerPos;
    final width = controller.width;

    final vents = <SteamVentBlockEntity>[this];
    final visited = <Pos>{blockPos};
    final queue = <Pos>[blockPos];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final dir in const [(1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1)]) {
        final next = (current.$1 + dir.$1, current.$2 + dir.$2, current.$3 + dir.$3);
        if (!SteamVentLogic.inTankBounds(next, controllerPos, width) || !visited.add(next)) continue;
        final be = store.at(worldId, BlockPos(x: next.$1, y: next.$2, z: next.$3));
        if (be is! SteamVentBlockEntity) continue;
        vents.add(be);
        queue.add(next);
      }
    }

    for (final vent in vents) {
      if (vent.logic.updateSignal(maxRaw)) vent.sendData();
    }
  }

  /// `doRaycast`: the vent looks straight up for the inside of a balloon.
  @override
  void doRaycast() {
    final range = AeroConfig.server.blocks.steamVentMaxRange;
    final worldView = balloonWorld;

    final start = Vector3d(blockPos.$1 + 0.5, blockPos.$2 + 1.0, blockPos.$3 + 0.5);
    final end = Vector3d(start.x, start.y + range, start.z);

    (int, int, int)? hit;
    segmentBlocked(start, end, (x, y, z) {
      if (worldView.stateAt(x, y, z).isAir) return false;
      hit = (x, y, z);
      return true;
    });

    final hitPos = hit;
    if (hitPos == null || !worldView.isAirtight(worldView.stateAtPos(hitPos))) {
      _castPosition = null;
      return;
    }
    _castPosition = (hitPos.$1, hitPos.$2 - 1, hitPos.$3);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putInt('SignalStrength', logic.signalStrength);
    tag.putInt('RawSignalStrength', logic.rawSignalStrength);
    if (clientPacket) {
      for (final entry in ClientBalloonInfo.toTag(_balloon as ServerBalloon?).entries) {
        final value = entry.value;
        if (value is double) tag.putDouble(entry.key, value);
        if (value is int) tag.putInt(entry.key, value);
      }
    }
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    logic.signalStrength = tag.getInt('SignalStrength') ?? 0;
    logic.rawSignalStrength = tag.getInt('RawSignalStrength') ?? 0;
    if (clientPacket) {
      _ticksSinceSync = 0;
      _clientBalloonInfo = ClientBalloonInfo.fromTag({
        for (final key in const ['Volume', 'Filled', 'Target', 'Delta', 'Lift', 'CenterX', 'CenterY', 'CenterZ'])
          key: tag.getDouble(key) ?? tag.getInt(key) ?? 0,
      });
    }
  }
}

/// `SteamVentBlock`.
CreateBlock buildSteamVentBlock() => CreateBlock(
  key: steamVentKey,
  properties: [
    CreateProps.horizontalFacing,
    BlockProperty.enumeration('variant', [SteamVentVariant.gold.serializedName, SteamVentVariant.iron.serializedName]),
    CreateProps.powered,
    CreateProps.waterlogged,
  ],
  defaultState: {'facing': 'north'},
  hardness: 3,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'copper',
  canOcclude: false,
  blockEntityType: steamVentKey,
  behavior: BlockBehavior(
    onUseWithItem: (server, e) async {
      final key = await e.item.getRegistryKey();
      final variant = SteamVentVariant.fromItemTags(
        Tags.item(key, 'c:plates/gold'),
        Tags.item(key, 'c:plates/iron'),
      );
      if (variant == null) return BlockUseResult.tryEmptyHand;

      final current = HostBlockGetter.stateOfId(e.targetWorld.getBlockStateId(pos: e.pos));
      if (current['variant'] == variant.serializedName) return BlockUseResult.tryEmptyHand;
      final id = KineticsRuntime.instance.states.idOf(
        KState(current.key, {...current.props, 'variant': variant.serializedName}),
      );
      if (id != null) {
        unawaited(e.targetWorld.setBlockState(pos: e.pos, state: id, updateFlags: BlockUpdateFlags.normal));
      }
      return BlockUseResult.success;
    },
    onNeighborUpdate: (server, e) async {
      final be = AeronauticsHooks.store?.at(e.targetWorld.getId(), e.pos);
      if (be is SteamVentBlockEntity) await be.updateRawSignal();
    },
  ),
);
