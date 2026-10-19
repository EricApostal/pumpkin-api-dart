/// `AllSoundEvents` for all modules: play a Create sound by its name. Provided by the `content`
/// module as a service (`ctx.services.require<CreateSounds>()`).
library;

import 'package:pumpkin_api/pumpkin_api.dart';

/// Plays the sound events of `AllSoundEvents`.
abstract interface class CreateSounds {
  /// `SoundEntry.play(level, null, pos, volume, pitch)` for the entry [name] (`mixing`, `depot_slide`,
  /// ...). Wrapped entries play each of their registered events with the configured volume and
  /// pitch multiplied in, like Java.
  void play(World world, (double, double, double) pos, String name, {double volume = 1, double pitch = 1});

  /// `playOnServer(world, blockPos)`.
  void playAtBlock(World world, (int, int, int) pos, String name, {double volume = 1, double pitch = 1});

  /// Whether the entry exists.
  bool has(String name);
}
