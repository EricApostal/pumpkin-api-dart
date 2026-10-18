# Recipe types, recipe queries and tag queries

## Recipes (`recipe.wit`)

Wrappers: `recipe_queries.dart` (`CustomRecipeBuilder`, `RecipeQueries`) next to
the shaped, shapeless and cooking builders of `recipes.dart`.

```dart
final manager = server.getRecipeManager();
manager.defineRecipeType('my_plugin:pressing');          // permission registry.recipes
(CustomRecipeBuilder('my_plugin:iron_sheet')
  ..ingredient('iron_ingot', count: 2)
  ..result('my_plugin:iron_sheet')
  ..fluidIngredient('minecraft:water', 100))
    .register(manager, 'my_plugin:pressing');

final recipes = manager.findRecipes(recipeType: 'my_plugin:pressing');   // List<RecipeInfo>
final byId = manager.getRecipeById(id: 'minecraft:stick');
final crafted = manager.matchCrafting([['oak_planks'], ['oak_planks']]);   // CraftingResult?
final smelted = manager.matchCooking('minecraft:iron_ore', CookingType.blasting);
```

### Syncing to NeoForge clients

Declare the recipe types the client mod syncs (`neoforge:recipe_content`) and give
each recipe its network encoding:

```dart
context.declareSyncedRecipeTypes(['minecraft:crafting', 'create:pressing']); // before players connect
(CustomRecipeBuilder('my_plugin:sheet')
  ..ingredient('iron_ingot')
  ..result('my_plugin:iron_sheet')
  ..networkData = streamCodecBytes)                  // serializer codec bytes, at most 32 KiB
    .register(manager, 'create:pressing');
```

Vanilla types are sent from the server's recipes; other types only with
`networkData`; without it a recipe is not synced. Other types are added to the
`recipe_type` and `recipe_serializer` registries of the handshake. Needs
`Permissions.neoforge`.

Queries are read only and cover vanilla, datapack, registered and plugin type
recipes. Plugin type recipes are plugin side data: not sent to clients, kept
across datapack reloads, never removed. Vanilla furnaces and crafting tables use
the vanilla recipes; a cooking recipe a plugin added is reported by queries only.

## Tags (`world.wit`)

```dart
Tags.block('oak_log', 'minecraft:logs');        // '#' and minecraft: optional
Tags.item('my_plugin:wrench', 'my_plugin:wrenches');
Tags.blockState(stateId, 'logs');
Tags.fluid('water', 'water');
Tags.entityType('zombie', 'undead');
```

They see vanilla tags, datapack tags and tags registered by plugins
(`register-block-tag`, `register-item-tag`); unknown keys and tags give `false`.
