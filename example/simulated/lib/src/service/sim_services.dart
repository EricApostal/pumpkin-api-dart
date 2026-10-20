// The services of the Java mod, with the `ServiceLoader` abstraction removed.
//
// Java has fourteen service interfaces and one implementation per loader. A
// Pumpkin plugin has one implementation, so the meaningful parts are plain
// functions over an installed [SimServices] object; the client-only, datagen
// and loader-specific ones (`SimMenuService`, `SimBlockStateService`,
// `SimEntityDataSerialization`, `SimTabService`, `SimInventoryService`,
// `SimFluidService`) have no server counterpart in the port and are not here.
//
// Pure: no host imports.
// create/sable internals are not exported from their barrels yet.
// ignore_for_file: implementation_imports

import 'package:create/src/api/block_state.dart' show BState;

/// What the plugin provides to the services that need the host.
abstract class SimServiceHost {
  const SimServiceHost();

  /// `SimPlatformService.isLoaded`: whether a mod is present. A plugin only
  /// knows about plugins the host loaded.
  bool isLoaded(String modId);

  /// `SimEntityService.getPlayerReach`.
  double playerReach(String playerId) => 5.0;

  /// `SimEntityService.isFake`: fake players (deployers) never own a UI.
  bool isFakePlayer(String playerId) => false;

  /// `SimItemService.getBurnTime`: the fuel value of an item, in ticks.
  int burnTime(String itemKey) => 0;

  /// `SimItemService.getSuperheatedBurnTime`.
  int superheatedBurnTime(String itemKey) => burnTime(itemKey) * 2;

  /// `SimEntityService.getCustomData`: the mod's per-player data.
  Map<String, Object?> customPlayerData(String playerId) => const {};
}

/// A host that knows nothing: every mod is absent and every lookup is empty.
final class EmptySimServiceHost extends SimServiceHost {
  const EmptySimServiceHost();

  @override
  bool isLoaded(String modId) => false;
}

/// The services of Simulated.
final class SimServices {
  SimServices([this.host = const EmptySimServiceHost()]);

  /// The installed services.
  static SimServices instance = SimServices();

  final SimServiceHost host;

  /// `SimAssemblyService.canStickTo`: whether two states stick together.
  ///
  /// NeoForge delegates to `BlockState.canStickTo`, whose vanilla rule is that
  /// slime and honey blocks stick to everything but each other.
  bool canStickTo(BState a, BState b) {
    if (_isSticky(a) && _isSticky(b)) return a.key == b.key;
    return _isSticky(a) || _isSticky(b);
  }

  /// `SimItemService.getDyeColor`: the dye colour of an item key, or `null`.
  static String? dyeColorOf(String itemKey) {
    const dyes = {
      'minecraft:white_dye': 'white',
      'minecraft:orange_dye': 'orange',
      'minecraft:magenta_dye': 'magenta',
      'minecraft:light_blue_dye': 'light_blue',
      'minecraft:yellow_dye': 'yellow',
      'minecraft:lime_dye': 'lime',
      'minecraft:pink_dye': 'pink',
      'minecraft:gray_dye': 'gray',
      'minecraft:light_gray_dye': 'light_gray',
      'minecraft:cyan_dye': 'cyan',
      'minecraft:purple_dye': 'purple',
      'minecraft:blue_dye': 'blue',
      'minecraft:brown_dye': 'brown',
      'minecraft:green_dye': 'green',
      'minecraft:red_dye': 'red',
      'minecraft:black_dye': 'black',
    };
    return dyes[itemKey];
  }

  static bool _isSticky(BState state) =>
      state.key == 'minecraft:slime_block' || state.key == 'minecraft:honey_block';
}
