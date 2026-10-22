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
import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/kinetics/behaviours.dart' show ScrollValueBehaviour;
import 'package:create/src/kinetics/geometry.dart' show KState;
import 'package:create/src/kinetics/runtime.dart' show KineticsRuntime;
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart' show Vector3d;
import '../../../config/aero_config.dart';
import '../../../host/world_balloon_world.dart';
import '../../../propeller/geometry.dart' show segmentBlocked;
import '../../../hot_air/balloon.dart';
import '../../../hot_air/balloon_world.dart';
import '../../../hot_air/lifting_gas.dart';
import '../../../hot_air/lifting_gas_provider.dart';
import '../../../hot_air/server_balloon.dart';

/// The block key.
const String hotAirBurnerKey = 'aeronautics:adjustable_burner';

/// The two variants of the burner.
///
/// `HotAirBurnerBlock.Variant` (`HotAirBurnerBlock.java:168-171`): `FIRE` is
/// spelled `fire`, `SOUL_FIRE` is spelled `soulful`. The serialized names are
/// enum values of the `variant` state property, so they are part of the state
/// ids a client numbers.
enum HotAirBurnerVariant {
  fire('fire'),
  soulFire('soulful');

  const HotAirBurnerVariant(this.serializedName);

  final String serializedName;

  static HotAirBurnerVariant byName(String? name) =>
      name == soulFire.serializedName ? soulFire : fire;

  /// `Variant.getConversionFromItem` (`HotAirBurnerBlock.java:179-183`): an item
  /// of the `aeronautics:burner_fire` tag (today just `minecraft:coal_block`)
  /// makes the burner burn [fire]; a vanilla soul fire base block
  /// (`minecraft:soul_fire_base_blocks`) makes it burn [soulFire]. `null` when
  /// the item converts nothing.
  static HotAirBurnerVariant? getConversionFromItem(bool burnerFire, bool soulFireBase) {
    if (burnerFire) return fire;
    if (soulFireBase) return soulFire;
    return null;
  }

  /// `Variant.sound` (`HotAirBurnerBlock.java:169-170`): the place sound the
  /// burner plays when an item converts it.
  Sound get placeSound => switch (this) {
    fire => Sound.blockNetherrackPlace,
    soulFire => Sound.blockSoulSandPlace,
  };
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
  ///
  /// `BlockEntityLiftingGasProvider.getRaycastedPosition` clips up to the
  /// configured range and accepts the hit only when the block it hit is
  /// airtight; the cast position is then the block on the near side of that
  /// hit, which is the air inside the envelope.
  ///
  /// HOST GAP: the API has no shape raycast, so the clip is the shared voxel
  /// walk (`segmentBlocked` in `propeller/geometry.dart`) over the vertical
  /// segment — the same walk the propeller uses, switched to the host raycast
  /// when one exists.
  @override
  void doRaycast() {
    final range = AeroConfig.server.blocks.hotAirBurnerMaxRange;
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

    // `clip.getDirection()` for an upward ray is the hit's bottom face, so the
    // position on the near side is one block below.
    _castPosition = (hitPos.$1, hitPos.$2 - 1, hitPos.$3);
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
  // `HotAirBurnerBlock extends Block` and adds `POWERED, VARIANT` only
  // (`HotAirBurnerBlock.java:51-52,103-105`): four states, 2 x 2. The port had
  // `facing` and `lit` as well -- sixteen states -- and every state id after the
  // block, from `aeronautics:steam_vent` on, was twelve ids off. `lit` was the
  // Java's `POWERED`, and there is no facing: the block faces nowhere.
  //
  // The variants are `FIRE("fire")` and `SOUL_FIRE("soulful")`
  // (`HotAirBurnerBlock.java:168-171`), not `normal`/`soul_fire`.
  properties: [
    CreateProps.powered,
    BlockProperty.enumeration('variant', [
      HotAirBurnerVariant.fire.serializedName,
      HotAirBurnerVariant.soulFire.serializedName,
    ]),
  ],
  // `registerDefaultState` of a plain `Block`: `POWERED = false`, and the first
  // value of `VARIANT` (`fire`).
  defaultState: {'powered': 'false', 'variant': 'fire'},
  // `SharedProperties::stone` with `sound(SoundType.NETHERITE_BLOCK)`
  // (`AeroBlocks.java:188-190`), which is 1.5 / 6, not 3, and netherite.
  hardness: 1.5,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'netherite_block',
  canOcclude: false,
  // `getLightPower` is `POWERED ? 15 : 0` (`HotAirBurnerBlock.java:58-60`) and
  // the host has one light level for the whole block, so the registered level is
  // the default state's, like the blaze burner of Create. The Java's own client
  // lights a powered burner from its copy of the class.
  luminance: 0,
  blockEntityType: hotAirBurnerKey,
  // `useItemOn` (`HotAirBurnerBlock.java:111-124`): an item that converts the
  // variant sets the state and plays the variant's sound; anything else (and a
  // matching current variant) falls through to
  // `InteractionResult.TRY_WITH_EMPTY_HAND`.
  behavior: BlockBehavior(
    onUseWithItem: (server, e) async {
      final key = await e.item.getRegistryKey();
      final conversion = HotAirBurnerVariant.getConversionFromItem(
        Tags.item(key, 'aeronautics:burner_fire'),
        Tags.item(key, 'minecraft:soul_fire_base_blocks'),
      );
      if (conversion == null) return BlockUseResult.tryEmptyHand;

      final current = HostBlockGetter.stateOfId(e.targetWorld.getBlockStateId(pos: e.pos));
      if (current['variant'] == conversion.serializedName) return BlockUseResult.tryEmptyHand;

      final id = KineticsRuntime.instance.states.idOf(
        KState(current.key, {...current.props, 'variant': conversion.serializedName}),
      );
      if (id != null) {
        unawaited(
          e.targetWorld.setBlockState(pos: e.pos, state: id, updateFlags: BlockUpdateFlags.normal),
        );
        // Java's `playLocalSound` reaches players within earshot; the host's
        // `World.playSound` broadcasts to the world. Same sound, wider reach.
        e.targetWorld.playSound(
          sound: conversion.placeSound,
          category: SoundCategory.blocks,
          pos: e.pos.center,
          volume: 1,
          pitch: 1,
        );
      }
      return BlockUseResult.success;
    },
  ),
);
