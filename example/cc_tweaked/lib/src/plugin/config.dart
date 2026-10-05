// The plugin's `config.json`, editable by the server owner.
import 'dart:convert';

import '../machine/computer.dart';

/// Settings read from `config.json` in the plugin's data folder. Missing keys
/// use the defaults below; the file is written back with all keys the first
/// time the plugin runs.
final class PluginConfig {
  /// The CC: Tweaked jar to take `rom/` and `bios.lua` from, a file name in
  /// the data folder. Empty: use any `.jar` in the folder that is one.
  final String jar;

  /// Per tick, how long one computer may run Lua, in milliseconds.
  final double sliceMs;

  /// Per tick, how long all computers together may run Lua, in milliseconds.
  final double tickBudgetMs;

  /// How long a program may run without yielding before it is told to stop,
  /// in seconds. CC: 7.
  final double timeoutSeconds;

  /// How much longer it gets before the computer is shut down. CC: 1.5.
  final double abortGraceSeconds;

  /// A computer's disk quota in bytes. CC: 1 000 000.
  final int diskQuota;

  final int maxOpenFiles;
  final int terminalWidth;
  final int terminalHeight;

  /// How many computers one player may own (0: unlimited).
  final int maxComputersPerPlayer;

  /// `name=value,...` settings every computer starts with (CC:
  /// `default_computer_settings`).
  final String defaultSettings;

  /// Whether to install the NeoForge handshake and registry sync for the
  /// real CC: Tweaked client mod. It only works on a host that sends the
  /// NeoForge query before the brand; see docs/host-requirements.md.
  final bool neoForge;

  const PluginConfig({
    this.jar = '',
    this.sliceMs = 3,
    this.tickBudgetMs = 12,
    this.timeoutSeconds = 7,
    this.abortGraceSeconds = 1.5,
    this.diskQuota = 1000000,
    this.maxOpenFiles = 128,
    this.terminalWidth = 51,
    this.terminalHeight = 19,
    this.maxComputersPerPlayer = 5,
    this.defaultSettings = '',
    this.neoForge = false,
  });

  factory PluginConfig.fromJson(Object? json) {
    if (json is! Map<String, Object?>) return const PluginConfig();
    const defaults = PluginConfig();
    String text(String key, String fallback) {
      final value = json[key];
      return value is String ? value : fallback;
    }

    double number(String key, double fallback, double min, double max) {
      final value = json[key];
      if (value is! num) return fallback;
      return value.toDouble().clamp(min, max);
    }

    int whole(String key, int fallback, int min, int max) {
      final value = json[key];
      if (value is! num) return fallback;
      return value.toInt().clamp(min, max);
    }

    final neoForge = json['neoforge'];
    return PluginConfig(
      jar: text('jar', defaults.jar),
      sliceMs: number('slice_ms', defaults.sliceMs, 0.5, 50),
      tickBudgetMs: number('tick_budget_ms', defaults.tickBudgetMs, 1, 45),
      timeoutSeconds: number('timeout_seconds', defaults.timeoutSeconds, 1, 120),
      abortGraceSeconds: number('abort_grace_seconds', defaults.abortGraceSeconds, 0.1, 60),
      diskQuota: whole('disk_quota', defaults.diskQuota, 10000, 1 << 30),
      maxOpenFiles: whole('maximum_open_files', defaults.maxOpenFiles, 0, 1 << 20),
      terminalWidth: whole('terminal_width', defaults.terminalWidth, 1, 255),
      terminalHeight: whole('terminal_height', defaults.terminalHeight, 1, 255),
      maxComputersPerPlayer: whole('max_computers_per_player', defaults.maxComputersPerPlayer, 0, 100000),
      defaultSettings: text('default_computer_settings', defaults.defaultSettings),
      neoForge: neoForge is bool ? neoForge : defaults.neoForge,
    );
  }

  Map<String, Object?> toJson() => {
    'jar': jar,
    'slice_ms': sliceMs,
    'tick_budget_ms': tickBudgetMs,
    'timeout_seconds': timeoutSeconds,
    'abort_grace_seconds': abortGraceSeconds,
    'disk_quota': diskQuota,
    'maximum_open_files': maxOpenFiles,
    'terminal_width': terminalWidth,
    'terminal_height': terminalHeight,
    'max_computers_per_player': maxComputersPerPlayer,
    'default_computer_settings': defaultSettings,
    'neoforge': neoForge,
  };

  String toJsonText() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// The machine settings these values describe.
  MachineConfig toMachineConfig() => MachineConfig(
    sliceMicros: (sliceMs * 1000).round(),
    tickBudgetMicros: (tickBudgetMs * 1000).round(),
    timeoutMicros: (timeoutSeconds * 1000000).round(),
    abortGraceMicros: (abortGraceSeconds * 1000000).round(),
    diskQuota: diskQuota,
    maxOpenFiles: maxOpenFiles,
    terminalWidth: terminalWidth,
    terminalHeight: terminalHeight,
    defaultSettings: defaultSettings,
  );
}
