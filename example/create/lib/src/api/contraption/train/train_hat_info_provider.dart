// `TrainHatInfoProvider` (pure): the data provider of the conductor hat offsets. Java's class is
// a datagen provider (`DataProvider`); this port keeps the same table building and produces the
// JSON documents by entity type, which the `TrainHatInfoReloadListener` reads back.
//
// Subclasses implement [createOffsets] and call [makeInfoFor] for every entity type they want to
// override. `run()` clears the table first, like Java, so the provider can be run repeatedly.
import '../../../common/vec_helper.dart' show Vec3;
import '../../../trains/schedule/hat/train_hat_info.dart';
import '../../../trains/schedule/hat/train_hat_info_reload_listener.dart';

/// `TrainHatInfoProvider`.
abstract class TrainHatInfoProvider {
  /// `trainHatOffsets`: entity type key (`minecraft:pig`) to its hat placement.
  final Map<String, TrainHatInfo> trainHatOffsets = {};

  TrainHatInfoProvider();

  /// `createOffsets`: fill [trainHatOffsets] with [makeInfoFor].
  void createOffsets();

  /// `makeInfoFor(type, offset, part, cubeIndex, scale)`. Java has five overloads; Dart uses
  /// optional named parameters for the defaults (`part` "", `cubeIndex` 0, `scale` 1).
  void makeInfoFor(
    String entityType,
    Vec3 offset, {
    String part = '',
    int cubeIndex = 0,
    double scale = 1.0,
  }) {
    trainHatOffsets[entityType] = TrainHatInfo.of(
      part,
      cubeIndex,
      offset,
      scale,
    );
  }

  /// `run`: rebuilds the table and returns the JSON documents by entity type.
  ///
  /// The keys are entity type ids (`minecraft:pig`); use [pathOf] for the resource path.
  Map<String, Map<String, Object?>> run() {
    trainHatOffsets.clear();
    createOffsets();
    return {
      for (final entry in trainHatOffsets.entries)
        entry.key: {
          'model_part': entry.value.part,
          'cube_index': entry.value.cubeIndex,
          'offset': entry.value.offsetList,
          'scale': entry.value.scale,
        },
    };
  }

  /// `getName`.
  String get name => 'Create Train Hat Information';

  /// The resource path of [entityType] (`train_hat_info/minecraft/pig.json`), the layout of the
  /// reload listener's directory.
  static String pathOf(String entityType) {
    final colon = entityType.indexOf(':');
    final namespace = colon < 0 ? 'minecraft' : entityType.substring(0, colon);
    final path = colon < 0 ? entityType : entityType.substring(colon + 1);
    return '${TrainHatInfoReloadListener.hatInfoDirectory}/$namespace/$path.json';
  }
}
