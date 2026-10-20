// `dev.ryanhcode.sable.sublevel.storage.SubLevelRemovalReason`.
//
// Pure: no host imports.

/// The reason a sub-level was removed from a `SubLevelContainer`.
enum SubLevelRemovalReason {
  /// The sub-level was unloaded; occupancy data is kept.
  unloaded,

  /// The sub-level was removed from the container; occupancy data is cleared.
  removed;

  /// `UNLOADED` / `REMOVED` in Java spelling.
  static SubLevelRemovalReason fromName(String name) =>
      name.toUpperCase() == 'REMOVED' ? removed : unloaded;
}
