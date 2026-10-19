// The live objects of the equipment module that block entities reach for (the entities are
// created by the block entity store, which knows nothing of the module).
import '../armor/armor_host.dart';
import '../armor/backtank_host.dart';
import '../bell/bell_host.dart';
import '../toolbox/toolbox_host.dart';
import 'env.dart';

final class EquipmentRuntime {
  static EquipmentRuntime? _instance;

  static EquipmentRuntime get instance => _instance ?? (throw StateError('equipment module is not loaded'));

  static bool get isLoaded => _instance != null;

  final EquipmentEnv env;
  final BacktankHost backtanks;
  final ArmorHost armor;
  final ToolboxHost toolbox;
  final BellHost bells;

  EquipmentRuntime({required this.env, required this.backtanks, required this.armor, required this.toolbox, required this.bells}) {
    _instance = this;
  }

  void dispose() {
    if (identical(_instance, this)) _instance = null;
  }
}
