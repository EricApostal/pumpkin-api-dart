// The network encodings of the Create recipe serializers (pure): the bytes that follow the
// serializer id in `neoforge:recipe_content`, so that a real Create client (JEI, Ponder, the
// recipe book) sees the recipes. Verified against the 26.3 sources of Minecraft / NeoForge /
// Create:
//
//   ProcessingRecipeParams   := ingredients  list(Ingredient.CONTENTS)      (VarInt n, ...)
//                               fluidIngr.   list(SizedFluidIngredient)
//                               results      list(ProcessingOutput)
//                               fluidResults list(FluidStack)
//                               VarInt processingDuration, VarInt heat ordinal
//   ItemApplication          := ProcessingRecipeParams, bool keepHeldItem
//   Ingredient.CONTENTS      := HolderSet<Item>: VarInt 0 + id (tag) or VarInt n+1 + n VarInt ids
//   SizedFluidIngredient     := VarInt fluid-ingredient-type id (`neoforge:simple` = 0),
//                               HolderSet<Fluid>, VarInt amount
//   ProcessingOutput         := VarInt item id, Int count, component patch, Float chance
//   FluidStack               := VarInt amount, VarInt fluid id, component patch
//   MechanicalCrafting       := bool showNotification, VarInt category, String group,
//                               VarInt width, VarInt height, list(Optional<Ingredient>),
//                               ItemStackTemplate(VarInt id, VarInt count, patch), bool mirrored
//   SequencedAssembly        := Ingredient, list(Recipe: VarInt serializer id + params),
//                               list(ProcessingOutput) pool, ProcessingOutput transitional,
//                               VarInt loops
//
// Recipes whose content cannot be written exactly (data components in a result, component
// fluid ingredients, an item the id table does not know) yield `null`: they are used by the
// machines but not synced.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import 'ingredient.dart';
import 'output.dart';
import 'recipe.dart';
import 'recipe_type.dart';
import 'sequenced.dart';

/// Registry ids the encoders need.
final class RecipeNetworkIds {
  /// The registry id of an item (`null`: unknown).
  final int? Function(String itemKey) item;

  /// The registry id of a fluid.
  final int? Function(String fluidKey) fluid;

  /// The registry id of a recipe serializer (`create:pressing`).
  final int? Function(String serializerKey) serializer;

  /// The registry id of `neoforge:simple` in `neoforge:fluid_ingredient_type` (first registered).
  final int simpleFluidIngredientType;

  const RecipeNetworkIds({
    required this.item,
    required this.fluid,
    required this.serializer,
    this.simpleFluidIngredientType = 0,
  });
}

/// Whether the client has a tag: [Tags.itemExists] and [Tags.fluidExists] in the plugin.
typedef _TagExists = ({bool Function(String tag) item, bool Function(String tag) fluid});

final class _CannotEncode implements Exception {
  final String why;
  const _CannotEncode(this.why);
}

/// Encodes recipes for the clients. [encode] returns `null` for a recipe that cannot be
/// represented exactly.
final class RecipeNetworkEncoder {
  final RecipeNetworkIds ids;

  /// Whether a tag the client would have to resolve exists, see [Tags].
  final _TagExists tags;

  const RecipeNetworkEncoder(this.ids, this.tags);

  /// The bytes after the serializer id for [recipe] (a [ProcessingRecipe],
  /// [MechanicalCraftingRecipe] or [SequencedAssemblyRecipe]), or `null`.
  Uint8List? encode(Object recipe) {
    try {
      return PacketBuffer.encode((w) => _write(w, recipe));
    } on _CannotEncode {
      return null;
    }
  }

  void _write(PacketWriter w, Object recipe) {
    switch (recipe) {
      case ProcessingRecipe():
        _params(w, recipe);
        if (recipe.type == CreateRecipeType.deploying || recipe.type == CreateRecipeType.itemApplication) {
          w.writeBool(recipe.keepHeldItem);
        }
      case MechanicalCraftingRecipe():
        _mechanical(w, recipe);
      case SequencedAssemblyRecipe():
        _sequenced(w, recipe);
      default:
        throw _CannotEncode('unknown recipe ${recipe.runtimeType}');
    }
  }

  void _params(PacketWriter w, ProcessingRecipe r) {
    w.writeVarInt(r.ingredients.length);
    for (final i in r.ingredients) {
      _ingredient(w, i);
    }
    w.writeVarInt(r.fluidIngredients.length);
    for (final f in r.fluidIngredients) {
      _fluidIngredient(w, f);
    }
    w.writeVarInt(r.results.length);
    for (final o in r.results) {
      _output(w, o);
    }
    w.writeVarInt(r.fluidResults.length);
    for (final f in r.fluidResults) {
      final id = ids.fluid(f.key) ?? (throw _CannotEncode('fluid ${f.key}'));
      // `FluidStackTemplate.STREAM_CODEC` is `(fluid, amount, components)`: the id first, then the
      // amount. The other way round makes the client read the amount as a fluid id
      // (`byIdOrThrow`: "No value with id 250").
      w.writeVarInt(id);
      w.writeVarInt(f.amount);
      w.writeVarInt(0); // patch: nothing added
      w.writeVarInt(0); // patch: nothing removed
    }
    w.writeVarInt(r.processingDuration);
    w.writeVarInt(r.requiredHeat.index);
  }

  void _output(PacketWriter w, ProcessingOutput o) {
    if (o.components.isNotEmpty) throw const _CannotEncode('result with components');
    w.writeVarInt(ids.item(o.item) ?? (throw _CannotEncode('item ${o.item}')));
    w.writeInt(o.count);
    w.writeVarInt(0);
    w.writeVarInt(0);
    w.writeFloat(o.chance);
  }

  /// `Ingredient.CONTENTS_STREAM_CODEC`: a lone tag as a tag reference, anything else as the
  /// list of its items (custom ingredients are synced as their item list too).
  ///
  /// A tag reference is a `-1` marker and the tag name, which the client resolves in the tags the
  /// server sent; a tag it does not have makes it drop the payload (`orElseThrow`), so such an
  /// ingredient cannot be encoded at all.
  void _ingredient(PacketWriter w, Ingredient i) {
    final entries = i.entries;
    if (i is! BlockTagIngredient && entries.length == 1 && entries.first.tag != null) {
      final tag = entries.first.tag!;
      if (!tags.item(tag)) {
        throw _CannotEncode('the client has no item tag $tag');
      }
      w.writeVarInt(0);
      w.writeString(tag, maxLength: 32767);
      return;
    }
    final items = <int>[];
    for (final e in entries) {
      final item = e.item;
      if (item == null) throw const _CannotEncode('tag inside a compound ingredient');
      final id = ids.item(item) ?? (throw _CannotEncode('item $item'));
      if (!items.contains(id)) items.add(id);
    }
    w.writeVarInt(items.length + 1);
    items.forEach(w.writeVarInt);
  }

  void _optionalIngredient(PacketWriter w, Ingredient? i) {
    if (i == null) {
      w.writeVarInt(1); // an empty direct set
    } else {
      _ingredient(w, i);
    }
  }

  void _fluidIngredient(PacketWriter w, FluidIngredient f) {
    if (f.components.isNotEmpty) throw const _CannotEncode('fluid ingredient with components');
    w.writeVarInt(ids.simpleFluidIngredientType);
    if (f.tag != null) {
      if (!tags.fluid(f.tag!)) {
        throw _CannotEncode('the client has no fluid tag ${f.tag}');
      }
      w.writeVarInt(0);
      w.writeString(f.tag!, maxLength: 32767);
    } else {
      w.writeVarInt(f.fluids.length + 1);
      for (final k in f.fluids) {
        w.writeVarInt(ids.fluid(k) ?? (throw _CannotEncode('fluid $k')));
      }
    }
    w.writeVarInt(f.amount);
  }

  void _mechanical(PacketWriter w, MechanicalCraftingRecipe r) {
    const categories = ['building', 'redstone', 'equipment', 'misc'];
    w.writeBool(true); // CommonInfo: Create always builds it with showNotification = true
    final cat = categories.indexOf(r.category ?? 'misc');
    w.writeVarInt(cat < 0 ? 3 : cat);
    w.writeString(r.group ?? '');
    w.writeVarInt(r.width);
    w.writeVarInt(r.height);
    final cells = r.cells;
    w.writeVarInt(cells.length);
    for (final c in cells) {
      _optionalIngredient(w, c);
    }
    if (r.result.components.isNotEmpty) throw const _CannotEncode('result with components');
    w.writeVarInt(ids.item(r.result.item) ?? (throw _CannotEncode('item ${r.result.item}')));
    w.writeVarInt(r.result.count);
    w.writeVarInt(0);
    w.writeVarInt(0);
    w.writeBool(r.acceptMirrored);
  }

  void _sequenced(PacketWriter w, SequencedAssemblyRecipe r) {
    _ingredient(w, r.ingredient);
    w.writeVarInt(r.sequence.length);
    for (final step in r.sequence) {
      final serializer = ids.serializer(step.recipe.type.key) ?? (throw _CannotEncode('serializer ${step.recipe.type.key}'));
      w.writeVarInt(serializer);
      _write(w, step.recipe);
    }
    w.writeVarInt(r.resultPool.length);
    for (final o in r.resultPool) {
      _output(w, o);
    }
    _output(w, r.transitionalItem);
    w.writeVarInt(r.loops);
  }
}
