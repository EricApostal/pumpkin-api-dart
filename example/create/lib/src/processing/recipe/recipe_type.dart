// The recipe types of the processing machines (`AllRecipeTypes`): key, limits and flags
// (pure). Order = the registration order of `AllRecipeTypes`.

/// A `create:*` recipe type.
enum CreateRecipeType {
  conversion('conversion', maxItemInputs: 1, maxItemOutputs: 1),
  crushing('crushing', maxItemInputs: 1, maxItemOutputs: 7, canSpecifyDuration: true),
  cutting('cutting', maxItemInputs: 1, maxItemOutputs: 4, canSpecifyDuration: true, assembly: true),
  milling('milling', maxItemInputs: 1, maxItemOutputs: 4, canSpecifyDuration: true),
  basin('basin', maxItemInputs: 64, maxItemOutputs: 4, maxFluidInputs: 2, maxFluidOutputs: 2, canRequireHeat: true, canSpecifyDuration: true),
  mixing('mixing', maxItemInputs: 64, maxItemOutputs: 4, maxFluidInputs: 2, maxFluidOutputs: 2, canRequireHeat: true, canSpecifyDuration: true),
  compacting('compacting', maxItemInputs: 64, maxItemOutputs: 4, maxFluidInputs: 2, maxFluidOutputs: 2, canRequireHeat: true, canSpecifyDuration: true),
  pressing('pressing', maxItemInputs: 1, maxItemOutputs: 2, assembly: true),
  sandpaperPolishing('sandpaper_polishing', maxItemInputs: 1, maxItemOutputs: 1),
  splashing('splashing', maxItemInputs: 1, maxItemOutputs: 12),
  haunting('haunting', maxItemInputs: 1, maxItemOutputs: 12),
  deploying('deploying', maxItemInputs: 2, maxItemOutputs: 4, assembly: true),
  filling('filling', maxItemInputs: 1, maxItemOutputs: 1, maxFluidInputs: 1, assembly: true),
  emptying('emptying', maxItemInputs: 1, maxItemOutputs: 1, maxFluidOutputs: 1),
  itemApplication('item_application', maxItemInputs: 2, maxItemOutputs: 4),
  mechanicalCrafting('mechanical_crafting', processing: false),
  sequencedAssembly('sequenced_assembly', processing: false);

  /// The path in the `create` namespace.
  final String path;
  final int maxItemInputs;
  final int maxItemOutputs;
  final int maxFluidInputs;
  final int maxFluidOutputs;
  final bool canRequireHeat;
  final bool canSpecifyDuration;

  /// Whether recipes of this type may be steps of a sequenced assembly (`IAssemblyRecipe`).
  final bool assembly;

  /// A `ProcessingRecipe` (parameter based) as opposed to the two special types.
  final bool processing;

  const CreateRecipeType(
    this.path, {
    this.maxItemInputs = 0,
    this.maxItemOutputs = 0,
    this.maxFluidInputs = 0,
    this.maxFluidOutputs = 0,
    this.canRequireHeat = false,
    this.canSpecifyDuration = false,
    this.assembly = false,
    this.processing = true,
  });

  /// `create:<path>`.
  String get key => 'create:$path';

  static CreateRecipeType? byKey(String key) {
    for (final t in values) {
      if (t.key == key) return t;
    }
    return null;
  }

  /// The types that are registered with the host recipe manager: everything but `conversion`
  /// (a JEI-only type) is a real recipe type in the registry, but only types that have recipes
  /// at all matter to clients; `AllRecipeTypes` registers all of them.
  static const List<CreateRecipeType> registered = values;
}
