// The balloon a heater fills: the provider side of the balloon model.
//
// Java: `content/blocks/hot_air/BlockEntityLiftingGasProvider`.
//
// A heater (hot air burner, steam vent) casts a ray up to find the inside of an
// enclosure, then joins the balloon that already covers that position or
// builds a new one. The mixin keeps that logic out of the block entities, so it
// runs on the VM in tests.
//
// Pure: no host imports.
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;

import '../config/aero_config.dart';
import 'balloon.dart';
import 'balloon_map.dart';
import 'balloon_world.dart';
import 'lifting_gas.dart';
import 'server_balloon.dart';

/// `BlockEntityLiftingGasProvider`: a block entity that can fill a balloon.
mixin BlockEntityLiftingGasProvider {
  /// The world of the block entity (`getLevel()`).
  BalloonWorld get balloonWorld;

  /// The position of the block entity.
  Pos get blockPos;

  /// The balloon this heater fills, if any.
  Balloon? get balloon;
  set balloon(Balloon? value);

  /// The position the raycast hit, or `null`.
  Pos? get castPosition;

  /// Casts the ray that looks for a balloon.
  void doRaycast();

  /// The gas output per tick at the current signal.
  double get gasOutput;

  /// The gas this heater outputs.
  LiftingGasType get liftingGasType;

  /// Whether the heater currently outputs gas.
  bool get canOutputGas;

  /// Whether the chunk of this block entity is unloaded.
  bool get isChunkUnloaded;

  /// `tickBalloonLogic`: re-casts the ray and (re)joins or creates a balloon.
///
/// Playback worlds that cannot award advancements use this; the host side of the mixin calls
/// [tickBalloonLogicAndAward] instead.
  void tickBalloonLogic() {
    doRaycast();

    if (balloon == null) tryJoinBalloon();
    if (balloon == null) tryCreateBalloon();
  }

  /// `tickBalloonLogic` with the `HEAD_IN_THE_CLOUDS` award of
/// `BlockEntityLiftingGasProvider.tickBalloonLogic` (`BlockEntityLiftingGasProvider.java:261`):
/// whenever the heater's balloon holds more than one block of hot air, the players near the heater
/// are awarded (`SimulatedAdvancement.awardToNearby`, radius 10).
///
/// The award leaves the tick rate to the caller (`onLoad`, `lazyTick`) — Java runs this gate inside
/// the mixin default, not behind an extra throttle.
  void tickBalloonLogicAndAward(void Function() award) {
    tickBalloonLogic();
    final current = balloon;
    if (current is ServerBalloon && current.totalFilledVolume > 1) {
      award();
    }
  }

  /// Joins the balloon whose volume contains the cast position.
  void tryJoinBalloon() {
    if (balloon != null) return;

    final castPos = castPosition;
    if (castPos == null) return;

    final existing = BalloonMap.of(balloonWorld).balloonAt(castPos);
    if (existing != null) {
      existing.addHeater(this);
      balloon = existing;
    }
  }

  /// Builds a balloon from the cast position, or leaves this heater without one.
  void tryCreateBalloon() {
    if (balloon != null) return;

    final castPos = castPosition;
    if (castPos == null) return;

    final map = BalloonMap.of(balloonWorld);
    final created = BalloonMap.attemptBuildBalloon(this, castPos);
    if (created == null) return;

    // A balloon that was unloaded where this one is being created keeps its gas.
    final graph = created.layerGraph;
    for (final unloaded in map.unloadedBalloons.toList()) {
      if (graph.hasBlockAt(unloaded.controllerPos)) {
        if (created is ServerBalloon) created.loadFrom(unloaded);
        map.markDirty();
        map.unloadedBalloons.remove(unloaded);
        break;
      }
    }

    balloon = created;
    map.addBalloon(created);
  }

  /// Detaches from the balloon; the last heater leaving an unloaded chunk takes
  /// the balloon with it.
  void removeFromBalloon() {
    final current = balloon;
    if (current is! ServerBalloon) return;

    current.removeHeater(this);
    if (isChunkUnloaded && current.heaters.isEmpty) {
      BalloonMap.of(balloonWorld).unloadBalloon(current);
    }

    balloon = null;
  }

  /// The air pressure at the balloon's gas centre (the goggles' lift readout).
  double get balloonAirPressure {
    final center = clientBalloonInfo!.gasCenter;
    return BalloonMap.airPressureAt(balloonWorld, center.$1, center.$2, center.$3);
  }

  /// The balloon data the client predicts from, or `null` on the server.
  ClientBalloonInfo? get clientBalloonInfo => null;

  /// `getPredictedVolume`: the fill level the client shows between updates.
  static double getPredictedVolume(ClientBalloonInfo info, int ticksSinceSync) {
    var volume = info.filled + info.change * ticksSinceSync;

    // The server fills the balloon with a discrete exponential decay; the
    // client recreates it so the bar moves smoothly.
    if ((info.filled - info.target - info.change).abs() > 0.01) {
      final ratio = (info.filled - info.target) / (info.filled - info.target - info.change);
      volume = _pow(ratio, ticksSinceSync) * (info.filled - info.target) + info.target;
    }

    return volume;
  }

  static double _pow(double base, int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }

  /// The default gas output cap of a burner, from the config.
  static int get burnerMaxHotAir => AeroConfig.server.blocks.hotAirBurnerMaxHotAir;
}

/// `ClientBalloonInfo`: the fill numbers the server sends to the client.
final class ClientBalloonInfo {
  /// `clientBalloonVolume`: the capacity of the balloon.
  final int volume;
  final double filled;
  final double target;
  final double lift;
  final double change;

  /// The gas centre, in the balloon's own space.
  final (double, double, double) gasCenter;

  const ClientBalloonInfo(
    this.volume,
    this.filled,
    this.target,
    this.lift,
    this.change,
    this.gasCenter,
  );

  static const ClientBalloonInfo empty = ClientBalloonInfo(0, 0, 0, 0, 0, (0, 0, 0));

  /// `writeToNBT`: the tags the update packet carries.
  static Map<String, Object?> toTag(ServerBalloon? balloon) {
    if (balloon == null) return const {};
    final center = balloon.center;
    return {
      'Volume': balloon.capacity,
      'Filled': balloon.totalFilledVolume,
      'Target': balloon.totalTargetVolume,
      'Delta': balloon.totalVolumeChange,
      'Lift': balloon.totalLift,
      'CenterX': center.x,
      'CenterY': center.y,
      'CenterZ': center.z,
    };
  }

  /// `readFromNBT`.
  static ClientBalloonInfo fromTag(Map<String, Object?> tag) => ClientBalloonInfo(
    (tag['Volume'] as num?)?.toInt() ?? 0,
    (tag['Filled'] as num?)?.toDouble() ?? 0,
    (tag['Target'] as num?)?.toDouble() ?? 0,
    (tag['Lift'] as num?)?.toDouble() ?? 0,
    (tag['Delta'] as num?)?.toDouble() ?? 0,
    (
      (tag['CenterX'] as num?)?.toDouble() ?? 0,
      (tag['CenterY'] as num?)?.toDouble() ?? 0,
      (tag['CenterZ'] as num?)?.toDouble() ?? 0,
    ),
  );
}
