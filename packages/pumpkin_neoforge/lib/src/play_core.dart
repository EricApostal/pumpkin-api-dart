// The binding-free part of the play-phase helpers: the constants, the options
// and the attribute id logic. See play.dart for what sends them.
import 'protocol.dart';
import 'spec.dart';
import 'vanilla.dart';

/// The channel of the recipe content payload (`neoforge:recipe_content`,
/// clientbound, play).
const String recipeContentChannel = 'neoforge:recipe_content';

/// An empty `neoforge:recipe_content`: no recipe types (`VarInt 0`) and no
/// recipes (`VarInt 0`). It makes the client fire NeoForge's
/// `RecipesReceivedEvent`, with nothing in it, which a NeoForge server does
/// once the recipes are synced; mods that wait for the event rely on it.
const List<int> emptyRecipeContent = [0, 0];

/// The modifier id NeoForge's server uses for a worn glider
/// (`neoforge:glider_component_flight`, `ADD_VALUE` 1).
const String gliderModifierId = 'neoforge:glider_component_flight';

/// The attribute that decides whether a NeoForge client may start gliding.
const String glidingFlightAttribute = 'neoforge:gliding_flight';

/// How [NeoForgeServer.installPlay] keeps `neoforge:gliding_flight` right.
///
/// A client that treats the connection as NeoForge starts an elytra glide only
/// when this attribute is greater than 0; vanilla looks at the worn items
/// instead. A NeoForge server derives the attribute from the worn item (a
/// modifier on items with the `glider` component); this helper does the same
/// for the chest slot: while one of [gliderItems] is worn it sends the
/// attribute with the modifier, otherwise without.
final class GlidingFlightOptions {
  /// The items that count as a glider when worn in the chest slot
  /// (registry keys).
  final Set<String> gliderItems;

  /// The attribute's registry id *on the client*. By default it is derived
  /// from the spec: the position in its `minecraft:attribute` registry if the
  /// spec syncs one (it must then contain NeoForge's own attributes, see
  /// [neoForgeOwnAttributes]), otherwise the number of vanilla attributes
  /// followed by NeoForge's own, which is where a client numbers them.
  final int? attributeId;

  /// How often the worn item is checked (a check per flagged player).
  final Duration interval;

  const GlidingFlightOptions({
    this.gliderItems = const {'minecraft:elytra'},
    this.attributeId,
    this.interval = const Duration(milliseconds: 500),
  });
}

/// The attribute id [options] and [spec] give `neoforge:gliding_flight`, or
/// null if it cannot be determined (the spec syncs the attribute registry
/// without it).
int? glidingFlightAttributeId(
  NeoForgeServerSpec spec, [
  GlidingFlightOptions options = const GlidingFlightOptions(),
]) {
  final explicit = options.attributeId;
  if (explicit != null) return explicit;
  for (final registry in spec.registries) {
    if (registry.key == 'minecraft:attribute') {
      final index = registry.entries.indexOf(glidingFlightAttribute);
      return index < 0 ? null : index;
    }
  }
  final vanilla = VanillaRegistries.entries('minecraft:attribute');
  if (vanilla == null) return null;
  return vanilla.length + neoForgeOwnAttributes.indexOf(glidingFlightAttribute);
}

