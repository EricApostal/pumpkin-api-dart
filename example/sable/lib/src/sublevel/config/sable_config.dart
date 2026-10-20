// `dev.ryanhcode.sable.SableConfig`, as a plain Dart settings class.
//
// The Java mod uses NeoForge's `ModConfigSpec`; the port has no loader config
// system, so these are ordinary fields with the same defaults and documented
// ranges. They are read from the plugin's JSON config (see
// `create`'s `CreateConfig`) by the plugin entry point.
//
// Pure: no host imports.

/// The server-side settings of Sable.
final class SableConfig {
  /// Whether sub-levels can split when parts are separated.
  bool subLevelSplitting;

  /// Sub-level splitting heatmap steps that take place per tick.
  int subLevelSplittingHeatmapSteps;

  /// The distance at which sub-levels are networked to players.
  double subLevelTrackingRange;

  /// Keeps sub-levels with intersecting players from unloading at all.
  bool subLevelsWithPlayersCannotUnload;

  /// The minimum y coordinate sub-levels can exist at.
  double subLevelRemoveMin;

  /// The maximum y coordinate sub-levels can exist at.
  double subLevelRemoveMax;

  /// The fraction of velocity retained when a sub-level is loaded in.
  double velocityRetainedOnLoad;

  /// The strength multiplier applied to sub-level punching impulses.
  double subLevelPunchStrengthMultiplier;

  /// The strength multiplier of the vertical component of downward punches.
  double subLevelPunchDownwardStrengthMultiplier;

  /// The cooldown in ticks between sub-level punches.
  int subLevelPunchCooldownTicks;

  /// Whether the whole UDP networking pipeline is disabled.
  bool disableUdpPipeline;

  /// Whether Sable should attempt to authenticate clients for UDP movement.
  bool attemptUdpNetworking;

  /// Whether Sable logs when it saves sub-levels for a dimension.
  bool subLevelSavingLogMessage;

  /// Whether Sable logs verbosely about serialization and the holding chunk map.
  bool verboseSerializationLogging;

  SableConfig({
    this.subLevelSplitting = true,
    this.subLevelSplittingHeatmapSteps = 200,
    this.subLevelTrackingRange = 320.0,
    this.subLevelsWithPlayersCannotUnload = true,
    this.subLevelRemoveMin = -10000.0,
    this.subLevelRemoveMax = 100000.0,
    this.velocityRetainedOnLoad = 0.9,
    this.subLevelPunchStrengthMultiplier = 2.1,
    this.subLevelPunchDownwardStrengthMultiplier = 0.175,
    this.subLevelPunchCooldownTicks = 3,
    this.disableUdpPipeline = false,
    this.attemptUdpNetworking = true,
    this.subLevelSavingLogMessage = true,
    this.verboseSerializationLogging = false,
  });

  /// Reads the settings from a JSON object, keeping the defaults for missing
  /// keys and clamping the ranges the Java config declares.
  factory SableConfig.fromMap(Map<String, Object?> map) {
    double number(String key, double fallback) {
      final value = map[key];
      return value is num ? value.toDouble() : fallback;
    }

    int integer(String key, int fallback) {
      final value = map[key];
      return value is num ? value.toInt() : fallback;
    }

    bool flag(String key, bool fallback) {
      final value = map[key];
      return value is bool ? value : fallback;
    }

    return SableConfig(
      subLevelSplitting: flag('sub_level_splitting', true),
      subLevelSplittingHeatmapSteps: integer('sub_level_splitting_heatmap_steps', 200).clamp(1, 0x7FFFFFFF),
      subLevelTrackingRange: number('sub_level_tracking_range', 320.0).clamp(1.0, double.maxFinite),
      subLevelsWithPlayersCannotUnload: flag('sub_levels_with_players_cannot_unload', true),
      subLevelRemoveMin: number('sub_level_remove_min', -10000.0),
      subLevelRemoveMax: number('sub_level_remove_max', 100000.0),
      velocityRetainedOnLoad: number('sub_level_velocity_retained_on_load', 0.9).clamp(0.0, 1.0),
      subLevelPunchStrengthMultiplier: number('sub_level_punch_strength_multiplier', 2.1).clamp(0.0, double.maxFinite),
      subLevelPunchDownwardStrengthMultiplier:
          number('sub_level_punch_downward_strength_multiplier', 0.175).clamp(0.0, double.maxFinite),
      subLevelPunchCooldownTicks: integer('sub_level_punch_cooldown_ticks', 3).clamp(0, 0x7FFFFFFF),
      disableUdpPipeline: flag('disable_udp_pipeline', false),
      attemptUdpNetworking: flag('attempt_udp_networking', true),
      subLevelSavingLogMessage: flag('sub_level_saving_log_message', true),
      verboseSerializationLogging: flag('verbose_serialization_logging', false),
    );
  }

  /// The settings as a JSON object (all keys, so the file documents itself).
  Map<String, Object?> toMap() => {
    'sub_level_splitting': subLevelSplitting,
    'sub_level_splitting_heatmap_steps': subLevelSplittingHeatmapSteps,
    'sub_level_tracking_range': subLevelTrackingRange,
    'sub_levels_with_players_cannot_unload': subLevelsWithPlayersCannotUnload,
    'sub_level_remove_min': subLevelRemoveMin,
    'sub_level_remove_max': subLevelRemoveMax,
    'sub_level_velocity_retained_on_load': velocityRetainedOnLoad,
    'sub_level_punch_strength_multiplier': subLevelPunchStrengthMultiplier,
    'sub_level_punch_downward_strength_multiplier': subLevelPunchDownwardStrengthMultiplier,
    'sub_level_punch_cooldown_ticks': subLevelPunchCooldownTicks,
    'disable_udp_pipeline': disableUdpPipeline,
    'attempt_udp_networking': attemptUdpNetworking,
    'sub_level_saving_log_message': subLevelSavingLogMessage,
    'verbose_serialization_logging': verboseSerializationLogging,
  };
}
