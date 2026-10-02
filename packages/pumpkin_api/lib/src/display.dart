import 'package:wasm_components/wasm_components.dart' as wc;

import 'bindings.g.dart';

T? _orNull<T>(wc.Option<T> option) =>
    option.hasValue ? option.requireValue() : null;

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
  DisplayEntity? asDisplay() => _orNull(DisplayEntity.fromEntity(entity: this));

  /// This entity as a block display, or null.
  BlockDisplayEntity? asBlockDisplay() =>
      _orNull(BlockDisplayEntity.fromEntity(entity: this));

  /// This entity as an item display, or null.
  ItemDisplayEntity? asItemDisplay() =>
      _orNull(ItemDisplayEntity.fromEntity(entity: this));

  /// This entity as a text display, or null.
  TextDisplayEntity? asTextDisplay() =>
      _orNull(TextDisplayEntity.fromEntity(entity: this));

  /// This entity as an interaction entity, or null.
  InteractionEntity? asInteraction() =>
      _orNull(InteractionEntity.fromEntity(entity: this));
}

/// Properties shared by all display entities.
extension DisplayEntityProps on DisplayEntity {
  /// The transformation applied to the displayed content.
  DisplayTransformation get transformation => getTransformation();

  set transformation(DisplayTransformation value) =>
      setTransformation(transformation: value);

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

  /// Ticks over which transformation changes are interpolated.
  int get interpolationDuration => getInterpolationDuration();
  set interpolationDuration(int value) =>
      setInterpolationDuration(duration: value);

  /// Ticks of delay before interpolation starts.
  int get interpolationStart => getInterpolationStart();
  set interpolationStart(int value) => setInterpolationStart(deltaTicks: value);

  /// Ticks over which teleports are interpolated.
  int get teleportDuration => getTeleportDuration();
  set teleportDuration(int value) => setTeleportDuration(duration: value);

  /// How the display rotates to face the viewer.
  BillboardMode get billboard => getBillboard();
  set billboard(BillboardMode value) => setBillboard(mode: value);

  /// Distance multiplier at which the display is visible.
  double get viewRange => getViewRange();
  set viewRange(double value) => setViewRange(range: value);

  /// Radius of the shadow.
  double get shadowRadius => getShadowRadius();
  set shadowRadius(double value) => setShadowRadius(radius: value);

  /// Strength (opacity) of the shadow.
  double get shadowStrength => getShadowStrength();
  set shadowStrength(double value) => setShadowStrength(strength: value);

  /// Width of the culling bounding box.
  double get displayWidth => getDisplayWidth();
  set displayWidth(double value) => setDisplayWidth(width: value);

  /// Height of the culling bounding box.
  double get displayHeight => getDisplayHeight();
  set displayHeight(double value) => setDisplayHeight(height: value);

  /// Glow outline color override as an RGB int (-1 for none).
  int get glowColorOverride => getGlowColorOverride();
  set glowColorOverride(int value) => setGlowColorOverride(color: value);

  /// Packed brightness override (-1 for none).
  int get brightness => getBrightness();
  set brightness(int value) => setBrightness(brightness: value);
}

/// Properties of block displays.
extension BlockDisplayProps on BlockDisplayEntity {
  /// The displayed block state id.
  int get blockStateId => getBlockStateId();
  set blockStateId(int value) => setBlockStateId(stateId: value);
}

/// Properties of item displays.
extension ItemDisplayProps on ItemDisplayEntity {
  /// The displayed item, or null. Setting consumes the given [ItemStack]
  /// (do not use it afterwards); set null to clear.
  ItemStack? get item => _orNull(getItem());
  set item(ItemStack? value) =>
      setItem(item: value == null ? wc.Option.none : wc.Option.some(value));

  /// How the item is rendered.
  ItemDisplayMode get displayMode => getItemDisplayMode();
  set displayMode(ItemDisplayMode value) => setItemDisplayMode(mode: value);
}

/// Properties of text displays.
extension TextDisplayProps on TextDisplayEntity {
  /// Sets the text from a plain string.
  set plainText(String text) => setText(text: TextComponent.text(plain: text));

  /// Maximum line width before wrapping.
  int get lineWidth => getLineWidth();
  set lineWidth(int value) => setLineWidth(width: value);

  /// Background color as ARGB.
  int get background => getBackground();
  set background(int value) => setBackground(color: value);

  /// Text opacity (0 to 255; values above 127 are signed bytes).
  int get textOpacity => getTextOpacity();
  set textOpacity(int value) => setTextOpacity(opacity: value);

  /// Whether the text casts a shadow.
  bool get shadow => getShadow();
  set shadow(bool value) => setShadow(shadow: value);

  /// Whether the text can be seen through blocks.
  bool get seeThrough => getSeeThrough();
  set seeThrough(bool value) => setSeeThrough(seeThrough: value);

  /// Whether the default background is used.
  bool get defaultBackground => getDefaultBackground();
  set defaultBackground(bool value) =>
      setDefaultBackground(defaultBackground: value);

  /// Text alignment.
  TextAlignment get alignment => getAlignment();
  set alignment(TextAlignment value) => setAlignment(alignment: value);
}

/// Properties of interaction entities.
extension InteractionProps on InteractionEntity {
  /// Width of the hitbox.
  double get width => getWidth();
  set width(double value) => setWidth(width: value);

  /// Height of the hitbox.
  double get height => getHeight();
  set height(double value) => setHeight(height: value);

  /// Whether interactions play the client swing animation.
  bool get response => getResponse();
  set response(bool value) => setResponse(response: value);

  /// UUID of the last attacker, if any.
  Uuid? get lastAttacker => _orNull(getLastAttacker());

  /// UUID of the last interacting entity, if any.
  Uuid? get lastInteraction => _orNull(getLastInteraction());
}
