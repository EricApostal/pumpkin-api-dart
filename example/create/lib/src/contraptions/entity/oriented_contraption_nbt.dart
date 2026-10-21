// `OrientedContraptionEntity`'s `InitialOrientation` NBT form, pure so the Java
// name round trip runs on the VM (the entity itself imports the host bindings).
//
// Java writes `Direction.name()` and only for a horizontal direction
// (`OrientedContraptionEntity.java:189-192`) and reads it with `readEnum`
// (`.java:161-162`), whose unknown name is the first constant, `down`.
import '../../common/direction.dart';
import '../../conveyance/nbt_names.dart';

/// The `InitialOrientation` value for [direction]: the Java enum name, or `null`
/// for a vertical direction (Java writes the key only when the axis is
/// horizontal).
String? initialOrientationNbtName(Direction direction) =>
    direction.axis.isHorizontal ? directionNbtName(direction) : null;

/// `readEnum(compound, "InitialOrientation", Direction.class)`: the Java name
/// resolves to its constant, an unknown one to the first constant (`down`).
Direction initialOrientationFromNbt(String nbtName) =>
    directionFromNbtName(nbtName);

/// The `InitialOrientation` written into a minecart contraption item
/// (`MinecartContraptionItem.java:302`, also `Direction.name()`).
String minecartInitialOrientationNbtName(Direction direction) =>
    directionNbtName(direction);
