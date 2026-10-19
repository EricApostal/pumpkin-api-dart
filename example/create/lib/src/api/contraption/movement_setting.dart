// `ContraptionMovementSetting`'s provider and registry (pure). The enum itself is part of the
// contraptions module (`contraptions/core/structure_info.dart`); this file is the public API
// surface: blocks (or their modules) can implement [MovementSettingProvider], or register a
// supplier for a block key. `ContraptionSettings` already has the config driven defaults; this
// registry is the extension point for other modules.
import '../../contraptions/core/structure_info.dart';
import '../block_state.dart';

export '../../contraptions/core/structure_info.dart'
    show ContraptionMovementSetting;

/// `ContraptionMovementSetting.MovementSettingProvider`: implemented by a block that decides its
/// own setting; queried before the registry, like Java.
abstract interface class MovementSettingProvider {
  ContraptionMovementSetting get contraptionMovementSetting;
}

/// `ContraptionMovementSetting.REGISTRY` and its static helpers.
abstract final class ContraptionMovementSettings {
  static final Map<String, MovementSettingProvider> _providers = {};
  static final Map<String, ContraptionMovementSetting Function()> _registry =
      {};

  /// Registers [provider] for [blockKey] (`MovementSettingProvider`).
  static void registerProvider(
    String blockKey,
    MovementSettingProvider provider,
  ) => _providers[blockKey] = provider;

  /// `REGISTRY.register(block, supplier)`: the setting may change at runtime (config options).
  static void register(
    String blockKey,
    ContraptionMovementSetting Function() setting,
  ) => _registry[blockKey] = setting;

  /// `ContraptionMovementSetting.get(block)`: the provider first, then the registry, else `null`.
  static ContraptionMovementSetting? get(String blockKey) {
    final provider = _providers[blockKey];
    if (provider != null) return provider.contraptionMovementSetting;
    return _registry[blockKey]?.call();
  }

  /// `ContraptionMovementSetting.get(state)`.
  static ContraptionMovementSetting? of(BState state) => get(state.key);

  /// `ContraptionMovementSetting.anyAre(blocks, setting)`.
  static bool anyAre(
    Iterable<String> blockKeys,
    ContraptionMovementSetting setting,
  ) => blockKeys.any((blockKey) => get(blockKey) == setting);

  /// `ContraptionMovementSetting.isNoPickup(blocks)`.
  static bool isNoPickup(Iterable<String> blockKeys) =>
      anyAre(blockKeys, ContraptionMovementSetting.noPickup);

  /// Removes every registration (tests and reloads).
  static void clear() {
    _providers.clear();
    _registry.clear();
  }
}
