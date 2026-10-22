// The balloon save data: `aeronautics_unloaded_balloons`.
//
// Java: `content/blocks/hot_air/balloon/map/BalloonLevelSavedData`. The list it writes holds the
// unloaded balloons *and* every live one, and the constructor reads it back into the balloon map's
// unloaded list, so a balloon's gas survives a world reload: the block entity that fills it takes
// the saved gas back when its structure is built again
// (`BlockEntityLiftingGasProvider.tryCreateBalloon`).
//
// Host: this file uses `pumpkin_api`.
import 'package:create/create.dart';
import 'package:pumpkin_api/pumpkin_api.dart';

import '../aeronautics_hooks.dart';
import 'balloon_map.dart';

/// `aeronautics_unloaded_balloons`: the gas of the balloons whose last heater unloaded, and of
/// every live one.
final class BalloonSave {
  final List<SavedBalloon> balloons = [];

  /// Brings [balloons] up to date right before the data is written.
  ///
  /// Java builds the list inside `BalloonLevelSavedData.save`, which runs on the level's save; the
  /// port writes the saved data of a world every `saveIntervalTicks`, so the list is rebuilt there
  /// instead of on every tick.
  void Function()? refresh;

  BalloonSave();

  Map<String, dynamic> toMap() {
    refresh?.call();
    return {
      'balloons': [for (final balloon in balloons) balloon.toMap()],
    };
  }

  static BalloonSave fromMap(Map<String, dynamic> map) {
    final save = BalloonSave();
    final entries = (map['balloons'] as List?) ?? const [];
    for (final entry in entries) {
      save.balloons.add(SavedBalloon.fromMap((entry as Map).cast<String, Object?>()));
    }
    return save;
  }
}

/// The saved data of the balloons that unloaded.
final SavedDataType<BalloonSave> balloonSaveType = SavedDataType<BalloonSave>(
  'aeronautics_unloaded_balloons',
  create: BalloonSave.new,
  fromMap: BalloonSave.fromMap,
  toMap: (value) => value.toMap(),
);

/// The loaded data of one world: `BalloonLevelSavedData.get(level)` plus the read-back of its
/// constructor.
abstract final class AeroBalloonSave {
  /// The worlds whose saved balloons were read into their map.
  static final Set<String> _loaded = {};

  /// Reads the saved balloons of [world] once, and keeps the save's list in step with the map.
  ///
  /// Called on every server tick of every world, like Java's `BalloonLevelSavedData.get`, which
  /// `BalloonMap`'s callers hit each tick.
  static void pump(CreateContext ctx, World world) {
    final runtime = AeronauticsHooks.of(world);
    final map = runtime.balloons;
    final save = ctx.savedData.get(world, balloonSaveType);

    if (_loaded.add(runtime.balloonWorld.id)) {
      // `BalloonLevelSavedData.create`: the saved list goes back into the map, where a heater's
      // rebuilt balloon takes the gas from it.
      if (save.balloons.isNotEmpty) map.loadUnloaded(save.balloons.toList());
    }

    save.refresh = () {
      // `BalloonLevelSavedData.save`: the unloaded balloons first, then every live one.
      save.balloons
        ..clear()
        ..addAll(map.savedBalloons());
    };
  }

  /// Forgets the worlds that were read (plugin unload).
  static void clear() => _loaded.clear();
}
