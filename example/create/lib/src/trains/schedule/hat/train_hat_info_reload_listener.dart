// `TrainHatInfoReloadListener` (pure): the table of hat placements by entity type, filled from the
// `train_hat_info/<entity>.json` files of a reload.
import 'dart:convert';

import 'train_hat_info.dart';

abstract final class TrainHatInfoReloadListener {
  static final Map<String, TrainHatInfo> _entityInfoMap = {};

  /// `HAT_INFO_DIRECTORY`.
  static const String hatInfoDirectory = 'train_hat_info';

  static final TrainHatInfo _default = TrainHatInfo.of('', 0, (0.0, 0.0, 0.0), 1.0);

  /// `registerOffsetOverrides(manager)`: [files] maps a resource path (`minecraft:train_hat_info/pig.json`
  /// or `train_hat_info/pig.json`) to its JSON text; [entityTypeExists] tells whether the entity
  /// type exists. Returns the errors (the Java version logs them).
  static List<String> registerOffsetOverrides(
    Map<String, String> files,
    bool Function(String entityType) entityTypeExists,
  ) {
    _entityInfoMap.clear();
    final errors = <String>[];
    for (final e in files.entries) {
      final colon = e.key.indexOf(':');
      final namespace = colon < 0 ? 'minecraft' : e.key.substring(0, colon);
      final path = colon < 0 ? e.key : e.key.substring(colon + 1);
      final split = path.split('/');
      final entityName = '$namespace:${split.last.replaceAll('.json', '')}';
      if (!entityTypeExists(entityName)) {
        errors.add('Failed to load train hat info for entity $entityName as it does not exist.');
        continue;
      }
      try {
        final json = jsonDecode(e.value);
        if (json is! Map<String, Object?>) throw const FormatException('not an object');
        _entityInfoMap[entityName] = TrainHatInfo.fromJson(json);
      } on FormatException catch (ex) {
        errors.add('Failed to read train hat info for entity $entityName! ${ex.message}');
      }
    }
    return errors;
  }

  /// The number of loaded configurations.
  static int get size => _entityInfoMap.length;

  /// `getHatInfoFor(entity)`: [entityType] is the registry key; [snowGolemHasPumpkin] is the
  /// manual override for snow golems wearing a pumpkin.
  static TrainHatInfo getHatInfoFor(String entityType, {bool snowGolemHasPumpkin = false}) {
    if (entityType == 'minecraft:snow_golem' && snowGolemHasPumpkin) {
      return TrainHatInfo.of('', 0, (0.0, -3.0, 0.0), 1.18);
    }
    return _entityInfoMap[entityType] ?? _default;
  }
}
