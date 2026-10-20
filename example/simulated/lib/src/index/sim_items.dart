// The items of Simulated.
//
// Host: this file uses `pumpkin_api` for the registration type.
//
// Java: dev.simulated_team.simulated.index.SimItems
// ignore_for_file: implementation_imports
import 'package:pumpkin_api/pumpkin_api.dart' show ItemRegistration;

/// The item keys.
abstract final class SimItemKeys {
  static const String spring = 'simulated:spring';
  static const String honeyGlue = 'simulated:honey_glue';
  static const String contraptionDiagram = 'simulated:contraption_diagram';
}

/// The items of the mod, in registration order.
List<ItemRegistration> simItems() => const [
  ItemRegistration(key: SimItemKeys.contraptionDiagram),
  ItemRegistration(key: SimItemKeys.spring),
  ItemRegistration(key: SimItemKeys.honeyGlue),
];
