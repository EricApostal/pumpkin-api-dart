// The hot air burner: a block entity that outputs hot air while it has a
// redstone signal, and joins the balloon its ray finds above it.
//
// Java: `content/blocks/hot_air/hot_air_burner/{HotAirBurnerBlock,HotAirBurnerBlockEntity}`.
//
// The burner is a plain block entity with a scroll value for the maximum output;
// the gas model itself lives in `BlockEntityLiftingGasProvider` (pure), so the
// block entity only supplies the signal, the amount and the raycast.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:create/create.dart';
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/kinetics/behaviours.dart' show ScrollValueBehaviour;
import 'package:pumpkin_api/pumpkin_api.dart';
import '../../../config/aero_config.dart';
import '../../../host/world_balloon_world.dart';
import '../../../hot_air/balloon.dart';
import '../../../hot_air/balloon_world.dart';
import '../../../hot_air/lifting_gas.dart';
import '../../../hot_air/lifting_gas_provider.dart';
import '../../../hot_air/server_balloon.dart';

/// The block key.
const String hotAirBurnerKey = 'aeronautics:hot_air_burner';

/// The two variants of the burner.
enum HotAirBurnerVariant {
  normal('normal'),
  soulFire('soul_fire');

  const HotAirBurnerVariant(this.serializedName);

  final String serializedName;

  static HotAirBurnerVariant byName(String? name) =>
      name == soulFire.serializedName ? soulFire : normal;
}

/// `HotAirBurnerBlockEntity`.
final class HotAirBurnerBlockEntity extends CreateBlockEntity with BlockEntityLiftingGasProvider {
  HotAirBurnerBlockEntity(super.worldId, super.pos) {
    lazyTickRate = 20;
  }

  Balloon? _balloon;
  Pos? _castPosition;
  bool _powered = false;
  int _signalStrength = 0;
  int _ticksSinceSync = 0;
  ClientBalloonInfo? _clientBalloonInfo;
  double _hotAirAmount = 0;

  /// The scroll value the player sets (`hotAirAmountBehaviour`).
  ScrollValueBehaviour? get hotAirAmountBehaviour => getBehaviour<ScrollValueBehaviour>();

  /// The signal strength the burner sees.
  int get signalStrength => _signalStrength;

  /// Whether the burner is powered.
  bool get powered => _powered;

  /// The maximum output of one burner.
  int get maxCapacity => AeroConfig.server.blocks.hotAirBurnerMaxHotAir;

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
  LiftingGasType get liftingGasType => const DefaultLiftingGas();

  @override
  double get gasOutput => ((hotAirAmountBehaviour?.value ?? _hotAirAmount) * _signalStrength) / 15.0;

  @override
  bool get canOutputGas => _signalStrength > 0 && !removed;

  @override
  bool get isChunkUnloaded => world == null;

  /// `getClientPredictedVolume`: the fill level between updates.
  double get clientPredictedVolume =>
      _clientBalloonInfo == null ? 0 : BlockEntityLiftingGasProvider.getPredictedVolume(_clientBalloonInfo!, _ticksSinceSync);

  @override
  ClientBalloonInfo? get clientBalloonInfo => _clientBalloonInfo;

  @override
  void onLoad() {
    _hotAirAmount = maxCapacity.toDouble();
    super.onLoad();
    unawaited(_refreshSignal());
    if (canOutputGas) tickBalloonLogic();
  }

  /// `updateSignal`: re-reads the redstone signal.
  Future<void> _refreshSignal() async {
    final w = world;
    if (w == null) return;
    final best = await w.getBestNeighborSignal(pos: pos);
    if (best == _signalStrength) return;
    _signalStrength = best;
    _powered = best > 0;
    sendData();
  }

  /// `doRaycast`: the burner looks straight up for the inside of a balloon.
  @override
  void doRaycast() {
    final range = AeroConfig.server.blocks.hotAirBurnerMaxRange;
    final worldView = balloonWorld;

    // The first airtight block above the burner closes the balloon; the cast
    // position is the air block just below it.
    for (var dy = 1; dy <= range; dy++) {
      final above = (blockPos.$1, blockPos.$2 + dy, blockPos.$3);
      if (worldView.isAirtight(worldView.stateAtPos(above))) {
        _castPosition = (above.$1, above.$2 - 1, above.$3);
        return;
      }
    }
    _castPosition = null;
  }

  @override
  void tick() {
    super.tick();
    _ticksSinceSync++;
    unawaited(_refreshSignal());
  }

  @override
  void lazyTick() {
    super.lazyTick();
    if (canOutputGas) tickBalloonLogic();
  }

  @override
  void onRemoved() {
    removeFromBalloon();
    super.onRemoved();
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putBool('IsPowered', _powered);
    tag.putInt('SignalStrength', _signalStrength);
    tag.putDouble('HotAirAmount', _hotAirAmount);
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
    _powered = tag.getBool('IsPowered') ?? false;
    _signalStrength = tag.getInt('SignalStrength') ?? 0;
    _hotAirAmount = tag.getDouble('HotAirAmount') ?? maxCapacity.toDouble();
    if (clientPacket) {
      _ticksSinceSync = 0;
      _clientBalloonInfo = ClientBalloonInfo.fromTag({
        for (final key in const ['Volume', 'Filled', 'Target', 'Delta', 'Lift', 'CenterX', 'CenterY', 'CenterZ'])
          key: tag.getDouble(key) ?? tag.getInt(key) ?? 0,
      });
    }
  }
}

/// `HotAirBurnerBlock`.
CreateBlock buildHotAirBurnerBlock() => CreateBlock(
  key: hotAirBurnerKey,
  properties: [
    CreateProps.horizontalFacing,
    BlockProperty.enumeration('variant', [
      HotAirBurnerVariant.normal.serializedName,
      HotAirBurnerVariant.soulFire.serializedName,
    ]),
    CreateProps.lit,
  ],
  defaultState: {'facing': 'north'},
  hardness: 3,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'copper',
  canOcclude: false,
  luminance: 7,
  blockEntityType: hotAirBurnerKey,
);
