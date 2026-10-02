import 'bindings.g.dart';

/// Constructors for [AttributeModifier]s.
abstract final class AttributeModifiers {
  /// A modifier that adds [amount] to the attribute's value.
  static AttributeModifier add(String id, double amount) => AttributeModifier(
    id: id,
    amount: amount,
    operation: ModifierOperation.add,
  );

  /// A modifier that adds `base * amount` (applied before multiply-total).
  static AttributeModifier multiplyBase(String id, double amount) =>
      AttributeModifier(
        id: id,
        amount: amount,
        operation: ModifierOperation.multiplyBase,
      );

  /// A modifier that multiplies the running total by `1 + amount`.
  static AttributeModifier multiplyTotal(String id, double amount) =>
      AttributeModifier(
        id: id,
        amount: amount,
        operation: ModifierOperation.multiplyTotal,
      );
}

/// One [Attribute] of a [LivingEntity], with properties instead of
/// get/set method pairs.
///
/// ```dart
/// final speed = entity.attribute(Attribute.movementSpeed);
/// speed.base *= 2;
/// speed.addModifier(AttributeModifiers.add('my_plugin:boost', 0.05));
/// ```
///
/// A view is only valid as long as the [LivingEntity] it came from.
final class AttributeView {
  final LivingEntity _entity;

  /// The attribute this view reads and writes.
  final Attribute attribute;

  AttributeView._(this._entity, this.attribute);

  /// The effective value, with all modifiers applied.
  double get value => _entity.getAttributeValue(attr: attribute);

  /// The base value, without modifiers.
  double get base => _entity.getAttributeBase(attr: attribute);

  set base(double value) =>
      _entity.setAttributeBase(attr: attribute, value: value);

  /// The modifiers currently applied.
  List<AttributeModifier> get modifiers =>
      _entity.getAttributeModifiers(attr: attribute);

  /// Applies [modifier]. A modifier with an existing id replaces it.
  void addModifier(AttributeModifier modifier) =>
      _entity.addAttributeModifier(attr: attribute, modifier: modifier);

  /// Removes the modifier with the given [id].
  void removeModifier(String id) =>
      _entity.removeAttributeModifier(attr: attribute, id: id);

  /// Resets the base value and removes all modifiers.
  void reset() => _entity.resetAttribute(attr: attribute);
}

/// Attribute access for living entities.
extension LivingEntityAttributes on LivingEntity {
  /// A view of this entity's [attribute].
  AttributeView attribute(Attribute attribute) =>
      AttributeView._(this, attribute);
}

/// Attribute modifiers on items.
extension ItemStackAttributes on ItemStack {
  /// Adds a modifier of [attribute] that applies while the item is in [slot].
  void addAttribute(
    Attribute attribute,
    AttributeModifier modifier,
    AttributeModifierSlot slot,
  ) => addAttributeModifier(
    modifier: ItemAttributeModifier(
      attribute: attribute,
      modifier: modifier,
      slot: slot,
    ),
  );
}
