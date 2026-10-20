// `dev.ryanhcode.sable.api.sublevel.SubLevelTrackingPlugin`: other mods or
// projects may piggyback on the snapshot interpolation system, giving Sable the
// players that need to be informed about the interpolation tick.
//
// Pure: no host imports.

/// A tracking plugin: the players that need interpolation updates, and a hook
/// when tracking data is sent.
abstract interface class SubLevelTrackingPlugin {
  /// Players that need to be informed about the interpolation ticks from the
  /// server and the distances between them, and who should be actively running
  /// interpolation.
  Iterable<String> neededPlayers();

  /// Called when sub-level tracking data is sent.
  void sendTrackingData(int interpolationTick);
}
