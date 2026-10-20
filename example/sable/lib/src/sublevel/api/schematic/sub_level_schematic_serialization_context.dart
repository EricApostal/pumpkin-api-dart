// `dev.ryanhcode.sable.api.schematic.SubLevelSchematicSerializationContext`: the
// context a sub-level is serialized with when it goes through a schematic.
//
// Java keeps the current context in a `FastThreadLocal`; the Dart plugin is
// single-threaded, so a static field does the same job.
//
// Pure: no host imports.
//
// create's positions are not exported from its public barrel yet, so they are
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;

import '../../model/sub_level.dart';
import '../../math/bounding_box.dart';
import '../../math/vector.dart';

/// A block-position transform (`it.unimi.dsi.fastutil.Function<BlockPos, BlockPos>`).
typedef PosTransform = Pos Function(Pos pos);

/// A global context for sub-levels being serialized to/from schematics.
final class SubLevelSchematicSerializationContext {
  static SubLevelSchematicSerializationContext? _current;

  final Map<String, SchematicMapping> _mappings = {};
  PosTransform? _placeTransform;
  PosTransform? _setupTransform;
  final SchematicContextType type;
  final BoundingBox3i boundingBox;

  SubLevelSchematicSerializationContext(this.type, this.boundingBox);

  /// The current context, or `null`.
  static SubLevelSchematicSerializationContext? getCurrentContext() => _current;

  /// Sets the current context.
  static void setCurrentContext(SubLevelSchematicSerializationContext? context) =>
      _current = context;

  /// Runs [action] with this context installed, restoring the previous one.
  T runWith<T>(T Function() action) {
    final previous = _current;
    _current = this;
    try {
      return action();
    } finally {
      _current = previous;
    }
  }

  /// The kind of serialization.
  SchematicContextType getType() => type;

  /// The bounds being serialized.
  BoundingBox3i getBoundingBox() => boundingBox;

  /// The transform applied when a sub-level is placed.
  PosTransform? getPlaceTransform() => _placeTransform;

  /// The transform applied when a sub-level is set up.
  PosTransform? getSetupTransform() => _setupTransform;

  /// Sets the place transform.
  void setPlaceTransform(PosTransform? transform) => _placeTransform = transform;

  /// Sets the setup transform.
  void setSetupTransform(PosTransform? transform) => _setupTransform = transform;

  /// The mapping of [subLevel], or `null`.
  SchematicMapping? getMapping(SubLevel subLevel) => _mappings[subLevel.uniqueId];

  /// The mapping of [uuid], or `null`.
  SchematicMapping? getMappingById(String uuid) => _mappings[uuid];

  /// All mappings, by sub-level UUID.
  Map<String, SchematicMapping> getMappings() => _mappings;
}

/// How a sub-level maps into the schematic.
final class SchematicMapping {
  final Vector3d newCorner;
  final Quaterniond newOrientation;
  final String newUUID;
  final PosTransform transform;

  SchematicMapping(this.newCorner, this.newOrientation, this.newUUID, this.transform);
}

/// `SubLevelSchematicSerializationContext.Type`.
enum SchematicContextType { place, save }
