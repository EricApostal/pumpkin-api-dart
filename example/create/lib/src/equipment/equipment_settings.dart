// The `CEquipment` values of Create's server config. They live in the `infrastructure`
// module's [CreateConfigs] (shared with `/create config` and the synced config file); this
// view reads them live and falls back to the manifest defaults when that service is absent.
import '../infrastructure/config/create_configs.dart';

final class EquipmentSettings {
  final CreateConfigs? Function() _configs;

  const EquipmentSettings(this._configs);

  /// A settings object with the manifest defaults only (tests, missing service).
  const EquipmentSettings.defaults() : _configs = _none;

  static CreateConfigs? _none() => null;

  CEquipment? get _c => _configs()?.server.equipment;

  /// The Maximum Distance to an active mirror for the symmetry wand to trigger.
  int get maxSymmetryWandRange => _c?.maxSymmetryWandRange.value ?? 50;

  /// The Maximum Distance a Block placed by Create's placement assist will have to its interaction point.
  int get placementAssistRange => _c?.placementAssistRange.value ?? 12;

  /// The Maximum Distance at which a Toolbox can interact with Players' Inventories.
  int get toolboxRange => _c?.toolboxRange.value ?? 10;

  /// The Maximum volume of Air that can be stored in a backtank = Seconds of underwater breathing.
  int get airInBacktank => _c?.airInBacktank.value ?? 900;

  /// The volume of Air added by each level of the backtanks Capacity Enchantment.
  int get enchantedBacktankCapacity => _c?.enchantedBacktankCapacity.value ?? 300;

  /// Amount of free Extendo Grip actions provided by one filled Copper Backtank (0: unbreakable).
  int get maxExtendoGripActions => _c?.maxExtendoGripActions.value ?? 1000;

  /// Amount of free Potato Cannon shots provided by one filled Copper Backtank (0: unbreakable).
  int get maxPotatoCannonShots => _c?.maxPotatoCannonShots.value ?? 200;
}
