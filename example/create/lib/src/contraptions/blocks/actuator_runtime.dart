// The shared state of the actuator content: the live config values (`ContraptionSettings`), the
// block entity store, the worlds and the logger. Set once in `loadActuatorContent`; block entities
// read it through [ActuatorRuntime.instance] (the store constructs them without a module context).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../../core/block_entity.dart';
import '../../core/worlds.dart';
import '../../kinetics/api.dart' show KineticsRuntime;
import '../../kinetics/geometry.dart' show Dir, KState;
import '../../infrastructure/config/create_configs.dart';
import '../core/structure_info.dart';

/// `ContraptionSettings` over the infrastructure module's live config, so `/create config` changes
/// apply at once (Java reads `AllConfigs.server()` every time).
final class ConfigsContraptionSettings implements ContraptionSettings {
  final CreateConfigs configs;

  const ConfigsContraptionSettings(this.configs);

  CKinetics get _k => configs.server.kinetics;

  @override
  int get maxBlocksMoved => _k.maxBlocksMoved.value;
  @override
  int get maxChassisRange => _k.maxChassisRange.value;
  @override
  int get maxPistonPoles => _k.maxPistonPoles.value;
  @override
  int get maxRopeLength => _k.maxRopeLength.value;
  @override
  int get minimumWindmillSails => _k.minimumWindmillSails.value;
  @override
  int get windmillSailsPerRPM => _k.windmillSailsPerRPM.value;
  @override
  int get fluidTankCapacity => 8;
  @override
  bool get survivalContraptionPickup => _k.survivalContraptionPickup.value;
  @override
  bool get moveItemsToStorage => _k.moveItemsToStorage.value;
  @override
  bool get minecartContraptionInContainers =>
      _k.minecartContraptionInContainers.value;
  @override
  bool get stabiliseStableContraptions => _k.stabiliseStableContraptions.value;
  @override
  bool get noDropWhenContraptionReplaceBlocks =>
      _k.noDropWhenContraptionReplaceBlocks.value;
  @override
  bool get seatHostileMobs => true;
  @override
  bool get trainsCauseDamage => true;

  /// `ContraptionMovementSetting` of the config-driven blocks.
  @override
  ContraptionMovementSetting? movementSettingOf(String blockKey) {
    final raw = switch (blockKey) {
      'minecraft:spawner' => _k.spawnerMovement.value,
      'minecraft:budding_amethyst' => _k.amethystMovement.value,
      'minecraft:obsidian' ||
      'minecraft:crying_obsidian' => _k.obsidianMovement.value,
      'minecraft:reinforced_deepslate' => _k.reinforcedDeepslateMovement.value,
      _ => null,
    };
    return raw == null ? null : ContraptionMovementSetting.fromConfig(raw);
  }
}

/// The module-wide state the block entities and contraptions read.
final class ActuatorRuntime {
  static ActuatorRuntime? _instance;

  /// The runtime; throws when the contraptions module is not loaded.
  static ActuatorRuntime get instance =>
      _instance ?? (throw StateError('The contraptions module is not loaded'));

  static ActuatorRuntime? get maybe => _instance;

  final ContraptionSettings settings;
  final BlockEntityStore store;
  final Worlds worlds;
  final Logger log;

  /// The live configs, `null` when the infrastructure module is disabled.
  final CreateConfigs? configs;

  ActuatorRuntime({
    required this.settings,
    required this.store,
    required this.worlds,
    required this.log,
    this.configs,
  }) {
    _instance = this;
  }

  /// `AllConfigs.server().kinetics.contraptions.maxCartCouplingLength`.
  int get maxCartCouplingLength =>
      configs?.server.kinetics.maxCartCouplingLength.value ?? 32;

  /// `AllConfigs.server().kinetics.contraptions.syncPlayerPickupHitboxWithContraptionHitbox`.
  bool get syncPlayerPickupHitbox =>
      configs
          ?.server
          .kinetics
          .syncPlayerPickupHitboxWithContraptionHitbox
          .value ??
      false;

  void dispose() {
    if (identical(_instance, this)) _instance = null;
  }
}

/// `DirectionalAxisKineticBlock.prefersConnectionTo(level, pos, side, true)`: the block at
/// [neighbour] has a shaft sticking out toward the position [side] looks from. The placement of
/// the piston, the gantry carriage and the pulley use it to pick their rotation axis.
bool prefersShaftConnection(BlockGetter level, Pos neighbour, Direction side) {
  if (!KineticsRuntime.isLoaded) return false;
  final state = level.stateAt(neighbour);
  final kState = KState(state.key, state.props);
  final def = KineticsRuntime.instance.blocks.defFor(kState);
  final dir = Dir.fromName(side.serializedName);
  if (def == null || dir == null) return false;
  return def.hasShaftTowards(kState, dir.opposite);
}
