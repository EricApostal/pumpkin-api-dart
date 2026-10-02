import 'bindings.g.dart';

/// Builds a [DisplayTransformation] starting from the identity.
///
/// ```dart
/// final transform = (TransformationBuilder()
///       ..translate(0, 1, 0)
///       ..uniformScale(2))
///     .build();
/// ```
final class TransformationBuilder {
  Vector3f _translation = const Vector3f(x: 0, y: 0, z: 0);
  Vector3f _scale = const Vector3f(x: 1, y: 1, z: 1);
  Quaternionf _left = const Quaternionf(x: 0, y: 0, z: 0, w: 1);
  Quaternionf _right = const Quaternionf(x: 0, y: 0, z: 0, w: 1);

  /// Starts at the identity transformation.
  TransformationBuilder();

  /// Starts from an existing [transformation].
  TransformationBuilder.from(DisplayTransformation transformation)
    : _translation = transformation.translation,
      _scale = transformation.scale,
      _left = transformation.leftRotation,
      _right = transformation.rightRotation;

  /// Sets the translation.
  void translate(double x, double y, double z) =>
      _translation = Vector3f(x: x, y: y, z: z);

  /// Sets the scale per axis.
  void scale(double x, double y, double z) =>
      _scale = Vector3f(x: x, y: y, z: z);

  /// Sets the same scale on all axes.
  void uniformScale(double scale) => this.scale(scale, scale, scale);

  /// Sets the left rotation quaternion.
  void leftRotation(double x, double y, double z, double w) =>
      _left = Quaternionf(x: x, y: y, z: z, w: w);

  /// Sets the right rotation quaternion.
  void rightRotation(double x, double y, double z, double w) =>
      _right = Quaternionf(x: x, y: y, z: z, w: w);

  /// The transformation described so far.
  DisplayTransformation build() => DisplayTransformation(
    translation: _translation,
    scale: _scale,
    leftRotation: _left,
    rightRotation: _right,
  );
}

/// Casts of a generic [Entity] to display and interaction entities. Each
/// returns null if the entity is of another kind. The result holds a new
/// handle that is released at the end of the current host callback.
extension EntityDisplayViews on Entity {
  /// This entity as a display entity, or null.
  DisplayEntity? asDisplay() => DisplayEntity.fromEntity(entity: this);

  /// This entity as a block display, or null.
  BlockDisplayEntity? asBlockDisplay() =>
      BlockDisplayEntity.fromEntity(entity: this);

  /// This entity as an item display, or null.
  ItemDisplayEntity? asItemDisplay() =>
      ItemDisplayEntity.fromEntity(entity: this);

  /// This entity as a text display, or null.
  TextDisplayEntity? asTextDisplay() =>
      TextDisplayEntity.fromEntity(entity: this);

  /// This entity as an interaction entity, or null.
  InteractionEntity? asInteraction() =>
      InteractionEntity.fromEntity(entity: this);
}

/// Shortcuts for the transformation of a display entity. The entity's other
/// settings (`billboard`, `viewRange`, `shadowRadius`, ...) are properties of
/// [DisplayEntity] itself.
extension DisplayEntityTransformation on DisplayEntity {
  /// Sets only the translation, keeping the rest of the transformation.
  void setTranslation(double x, double y, double z) =>
      transformation = transformation.copyWith(
        translation: Vector3f(x: x, y: y, z: z),
      );

  /// Sets only the scale, keeping the rest of the transformation.
  void setScale(double x, double y, double z) =>
      transformation = transformation.copyWith(
        scale: Vector3f(x: x, y: y, z: z),
      );
}

extension TextDisplayText on TextDisplayEntity {
  /// Sets the text from a plain string.
  set plainText(String text) => setText(text: TextComponent.text(plain: text));
}
