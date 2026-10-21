// The crafting blueprint: `BlueprintItem` (hanging it), `BlueprintEntity` (a plugin entity that
// keeps its recipe sections), crafting by right-click, the ghost slot menu (`BlueprintMenu`) and
// `BlueprintAssignCompleteRecipePacket`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';
// ignore: implementation_imports
import 'package:pumpkin_api/src/bindings.g.dart' as raw show menus;

import '../../common/ghost_menu_layout.dart';
import '../../common/menu_mirror.dart';
import '../../contraptions/core/entity_type_keys.dart' show reportedEntityTypeKey;
import '../../core/module.dart';
import '../../core/nbt.dart';
import '../../protocol/item_stack.dart';
import '../armor/armor_host.dart' show findEntity;
import '../data/equipment_components.dart';
import '../host/env.dart';
import '../host/inventory_util.dart';
import '../host/stack_codec.dart';
import '../model/dir.dart';
import '../model/vec.dart';
import '../toolbox/toolbox_model.dart';
import 'blueprint_geometry.dart';

const String blueprintEntityKey = 'create:crafting_blueprint';
const String blueprintMenuType = 'create:crafting_blueprint';

/// `BlueprintMenu.addSlots`: the 36 player slots first, then the nine grid slots, the result and
/// the icon (`GhostMenu.blueprint`).
const GhostMenu blueprintLayout = GhostMenu.blueprint;

/// The menu slot of the ghost slot [i] (`36 + i`).
int blueprintGhostSlot(int i) => blueprintLayout.ghostSlot(i);

/// One recipe section of a blueprint: nine ingredient filters, the result and a secondary icon.
final class BlueprintSection {
  final List<TStack> items = List.filled(11, TStack.empty);
}

/// The state of one blueprint entity.
final class BlueprintState {
  Dir direction;
  Dir vertical;
  int size;
  bool inferredIcon = false;
  final Map<int, BlueprintSection> sections = {};

  BlueprintState(this.direction, this.vertical, this.size);

  BlueprintSection section(int i) => sections.putIfAbsent(i, BlueprintSection.new);

  BlueprintGeometry geometry(P3 blockPos) =>
      BlueprintGeometry(direction: direction, verticalOrientation: vertical, size: size, blockPos: blockPos);
}

final class BlueprintHost {
  final EquipmentEnv env;

  BlueprintHost(this.env);

  final Map<int, BlueprintState> _states = {};

  /// uuid -> (entity id, section) of the open menu.
  final Map<String, (int, int)> _openMenus = {};

  void install(CreateContext ctx) {
    ctx.host.intercept(Events.itemUseFirst, _onUseFirst);
    ctx.host.intercept(Events.playerInteractEntity, _onInteractEntity);
    ctx.listen(Events.entityTick, _onEntityTick);
    ctx.listen(Events.entityRemove, (server, e) => _states.remove(e.entityId));
    ctx.listen(Events.entityStartTracking, _onStartTracking);
    ctx.listen(Events.menuSlotChanged, _onMenuSlotChanged);
    ctx.listen(Events.menuClosed, _onMenuClosed);
    env.bus.onServerbound('create:blueprint_complete_recipe', _onCompleteRecipe);
    try {
      ctx.host.tickPluginEntities(blueprintEntityKey, interval: 20);
    } on Object catch (e) {
      env.log.warn('blueprints do not check their support: $e');
    }
  }

  // ---------------------------------------------------------------------------------------
  // State <-> NBT
  // ---------------------------------------------------------------------------------------

  BlueprintState? stateOf(Entity entity) {
    final id = entity.getId();
    final cached = _states[id];
    if (cached != null) return cached;
    final tree = entity.getCustomData(namespace: 'create', key: 'blueprint');
    if (tree == null) return null;
    try {
      final c = NbtCompound.fromTree(tree);
      final dir = Dir.values[(c.getInt('Facing') ?? 3).clamp(0, 5)];
      final vert = Dir.values[(c.getInt('Orientation') ?? 0).clamp(0, 5)];
      final st = BlueprintState(dir, vert, (c.getInt('Size') ?? 1).clamp(1, 3));
      st.inferredIcon = c.getBool('InferredIcon') ?? false;
      for (final e in c.getList('Raw') ?? const <Object>[]) {
        if (e is! NbtCompound) continue;
        final sec = e.getInt('Section') ?? 0;
        final slot = e.getInt('Slot') ?? -1;
        if (slot < 0 || slot > 10) continue;
        st.section(sec).items[slot] = StackCodec.fromNbt(e);
      }
      _states[id] = st;
      return st;
    } on Object catch (e) {
      env.log.warn('blueprint data unreadable: $e');
      return null;
    }
  }

  /// The private persistence form.
  NbtCompound _saveNbt(BlueprintState st) {
    final c = NbtCompound()
      ..putInt('Facing', st.direction.index)
      ..putInt('Orientation', st.vertical.index)
      ..putInt('Size', st.size)
      ..putBool('InferredIcon', st.inferredIcon);
    final raw = <Object>[];
    for (final e in st.sections.entries) {
      for (var i = 0; i < 11; i++) {
        final s = e.value.items[i];
        if (s.isEmpty) continue;
        raw.add(StackCodec.toNbt(s)..putInt('Section', e.key)..putInt('Slot', i));
      }
    }
    c.putList('Raw', raw);
    return c;
  }

  /// `getOrCreateRecipeCompound()` as the client reads it (`Recipes` of the persistent data).
  NbtValue _recipesValue(BlueprintState st) {
    final map = <String, NbtValue>{};
    for (final e in st.sections.entries) {
      final items = <NbtValue>[];
      for (var i = 0; i < 11; i++) {
        final s = e.value.items[i];
        if (s.isEmpty) continue;
        items.add(NbtValue.compound({
          'id': NbtValue.string(s.key),
          'count': NbtValue.int32(s.count),
          'Slot': NbtValue.int32(i),
        }));
      }
      map['${e.key}'] = NbtValue.compound({'Items': NbtValue.list(items), 'Size': const NbtValue.int32(11)});
    }
    map['InferredIcon'] = NbtValue.byte(st.inferredIcon ? 1 : 0);
    return NbtValue.compound(map);
  }

  /// The spawn data (`writeSpawnData`): the facing fields and the persistent data.
  List<int> _spawnData(BlueprintState st) => PacketBuffer.encode((w) {
    NetworkNbt.write(
      w,
      NbtValue.compound({
        'Facing': NbtValue.byte(st.direction.index),
        'Orientation': NbtValue.byte(st.vertical.index),
        'Size': NbtValue.int32(st.size),
      }),
    );
    NetworkNbt.write(w, NbtValue.compound({'Recipes': _recipesValue(st)}));
  });

  void _save(Entity entity, BlueprintState st) {
    _states[entity.getId()] = st;
    try {
      entity.setCustomData(namespace: 'create', key: 'blueprint', value: _saveNbt(st).toTree());
      entity.setSpawnData(_spawnData(st));
    } on Object catch (e) {
      env.log.debug('blueprint save failed: $e');
    }
  }

  /// `syncPersistentDataWithTracking`.
  void _syncToTrackers(Entity entity, BlueprintState st) {
    final pos = entity.getPosition();
    final players = env.bus.playersTracking(entity.getWorld().getId(), (pos.$1.floor(), pos.$2.floor(), pos.$3.floor()));
    env.bus.sendClientboundAll('create:persistent_data', players, {
      'entityId': entity.getId(),
      'readData': NbtValue.compound({'Recipes': _recipesValue(st)}),
    });
  }

  void _onStartTracking(Server server, EntityTrackingEventData e) {
    final st = _states[e.entityId];
    if (st == null) return;
    final player = env.playerByUuid(e.player.asString);
    final entity = findEntity(server, e.entityId);
    if (player == null || entity == null) return;
    env.bus.sendClientbound('create:persistent_data', player, {
      'entityId': e.entityId,
      'readData': NbtValue.compound({'Recipes': _recipesValue(st)}),
    });
  }

  // ---------------------------------------------------------------------------------------
  // Placing
  // ---------------------------------------------------------------------------------------

  Future<ItemUseFirstEventData> _onUseFirst(Server server, ItemUseFirstEventData e) async {
    if (await stackKey(e.stack) != EqItems.craftingBlueprint) return e;
    final player = e.player;
    final face = e.face.dir;
    var pos = e.blockPos.p3.rel(face);
    final world = player.getWorld();
    final horizontal = Dir.fromYRot(player.getYaw());
    final placement = blueprintPlacementFor(face, horizontal);
    BlueprintState? chosen;
    for (final size in BlueprintGeometry.sizesToTry) {
      final st = BlueprintState(placement.direction, placement.vertical, size);
      if (await survives(world, st, pos, null)) {
        chosen = st;
        break;
      }
    }
    if (chosen == null) return e.copyWith(useResult: ItemUseFirstResult.consume);
    if (pos.$2 < world.getMinY()) pos = (pos.$1, world.getMinY(), pos.$3);
    final g = chosen.geometry(pos);
    final entity = await world.spawnPlugin(blueprintEntityKey, g.entityPosition, spawnData: _spawnData(chosen));
    final (yaw, pitch) = g.rotation;
    entity.setRotation(yaw: yaw, pitch: pitch);
    entity.resize(chosen.size.toDouble(), chosen.size.toDouble());
    _save(entity, chosen);
    env.playSound(world, g.entityPosition, 'confirm', volume: 0);
    if (!player.isCreative) await shrinkHeld(player, e.hand, 1);
    return e.copyWith(useResult: ItemUseFirstResult.success);
  }

  static bool _isDiode(String key) =>
      namespacedBlockKey(key) == 'minecraft:repeater' || namespacedBlockKey(key) == 'minecraft:comparator';

  /// `survives()`: free space, supported by solid blocks, no other hanging entity in the way.
  Future<bool> survives(World world, BlueprintState st, P3 pos, Entity? self) async {
    final g = st.geometry(pos);
    // `level.noCollision(this)`: no block with a collision shape in the thin box
    final box = g.boundingBox;
    for (final bp in g.coveredBlocks) {
      final b = world.getBlockState(pos: bp.blockPos);
      if (b.isAir) continue;
      for (final c in b.collisionShapes) {
        final x0 = bp.$1 + c.min.$1, y0 = bp.$2 + c.min.$2, z0 = bp.$3 + c.min.$3;
        final x1 = bp.$1 + c.max.$1, y1 = bp.$2 + c.max.$2, z1 = bp.$3 + c.max.$3;
        if (x0 < box.$4 && x1 > box.$1 && y0 < box.$5 && y1 > box.$2 && z0 < box.$6 && z1 > box.$3) return false;
      }
    }
    for (final sp in g.supportPositions) {
      final b = world.getBlockState(pos: sp.blockPos);
      final sturdy = switch (st.direction) {
        Dir.down => b.downSideSolid,
        Dir.up => b.upSideSolid,
        Dir.north => b.northSideSolid,
        Dir.south => b.southSideSolid,
        Dir.west => b.westSideSolid,
        Dir.east => b.eastSideSolid,
      };
      if (sturdy) continue;
      if (!b.isSolid && !_isDiode(b.blockName)) return false;
    }
    // no other hanging entity in the box (blueprints, item frames, paintings)
    final hangings = world.getEntitiesInBox(
      min: (box.$1, box.$2, box.$3),
      max: (box.$4, box.$5, box.$6),
      filter: const EntityFilterAll(),
    );
    for (final s in hangings) {
      if (self != null && s.id == self.getId()) continue;
      if (const {
        'minecraft:item_frame',
        'minecraft:glow_item_frame',
        'minecraft:painting',
      }.contains(s.entityTypeKey)) return false;
    }
    final others = world.getEntities();
    for (final o in others) {
      if (o.getPluginTypeKey() != blueprintEntityKey) continue;
      if (self != null && o.getId() == self.getId()) continue;
      final os = _states[o.getId()];
      if (os == null) continue;
      final p = o.getPosition();
      final ob = os.geometry((p.$1.floor(), p.$2.floor(), p.$3.floor())).boundingBox;
      if (ob.$1 < box.$4 && ob.$4 > box.$1 && ob.$2 < box.$5 && ob.$5 > box.$2 && ob.$3 < box.$6 && ob.$6 > box.$3) {
        return false;
      }
    }
    return true;
  }

  /// `HangingEntity.tick`: every few seconds the blueprint checks that it is still held.
  Future<void> _onEntityTick(Server server, EntityTickEventData e) async {
    if (reportedEntityTypeKey(e.entityType) != blueprintEntityKey) return;
    final entity = findEntity(server, e.entityId);
    if (entity == null) return;
    final st = stateOf(entity);
    if (st == null) return;
    final p = entity.getPosition();
    // the block position of the entity is the block in front of the wall
    final bp = (
      (p.$1 + st.direction.dx * 0.46875 - 0.5).round(),
      (p.$2 + st.direction.dy * 0.46875 - 0.5).round(),
      (p.$3 + st.direction.dz * 0.46875 - 0.5).round(),
    );
    final world = entity.getWorld();
    if (!world.isLoaded(pos: bp.blockPos)) return;
    if (!await survives(world, st, bp, entity)) {
      await _dropItem(world, entity, null);
    }
  }

  Future<void> _dropItem(World world, Entity entity, Player? by) async {
    final pos = entity.getPosition();
    entity.remove();
    _states.remove(entity.getId());
    env.playSound(world, pos, 'confirm', volume: 0);
    if (by != null && by.isCreative) return;
    final stack = ItemStack.create(registryKey: EqItems.craftingBlueprint, count: 1);
    await world.dropItem(pos, stack);
  }

  // ---------------------------------------------------------------------------------------
  // Interacting
  // ---------------------------------------------------------------------------------------

  Future<PlayerInteractEntityEventData> _onInteractEntity(Server server, PlayerInteractEntityEventData e) async {
    final player = e.player;
    final world = player.getWorld();
    final entity = world.getEntityById(id: e.entityId);
    if (entity == null || entity.getPluginTypeKey() != blueprintEntityKey) return e;
    final st = stateOf(entity);
    if (st == null) return e;

    // where the player's look hits the blueprint (the event has no hit vector)
    final eye = player.eyePosition;
    final range = (player.asEntity().asLiving()?.getAttributeValue(attr: Attribute.blockInteractionRange) ?? 4.5) +
        (player.isCreative ? 0 : -0.5);
    V3 hit = entity.getPosition();
    for (final r in world.rayTraceEntities(start: eye, end: eye + player.lookDirection * range)) {
      if (r.entity.getId() == e.entityId) {
        hit = r.hitPos;
        break;
      }
    }
    final epos = entity.getPosition();
    final rel = (hit.$1 - epos.$1, hit.$2 - epos.$2, hit.$3 - epos.$3);
    final (yaw, pitch) = st.geometry((0, 0, 0)).rotation;
    final index = st.geometry((0, 0, 0)).sectionAt(rel, yRot: yaw, xRot: pitch);
    final section = st.section(index);

    if (e.action == EntityInteractionAction.attack) {
      // `skipAttackInteraction`: a left click clears a recipe; without one the blueprint breaks.
      if (!section.items[9].isEmpty) {
        for (var i = 0; i < 11; i++) {
          section.items[i] = TStack.empty;
        }
        _save(entity, st);
        _syncToTrackers(entity, st);
        return e.cancel();
      }
      await _dropItem(world, entity, player);
      return e.cancel();
    }
    if (e.action == EntityInteractionAction.interactAt) return e.cancel();
    final held = player.getInventory().getItemInHand(hand: Hand.right);
    final holdingWrench = held != null && await held.getRegistryKey() == EqItems.wrench;
    if (!holdingWrench && !section.items[9].isEmpty) {
      await _craft(player, section);
      return e.cancel();
    }
    await _openMenu(player, entity, st, index);
    return e.cancel();
  }

  // -- Crafting from the inventory -------------------------------------------------------------------

  bool _matchesFilter(TStack filter, TStack candidate) {
    if (filter.isEmpty) return false;
    if (filter.key == 'create:filter') return _listFilterMatches(filter, candidate);
    return filter.key == candidate.key;
  }

  bool _listFilterMatches(TStack filter, TStack candidate) {
    List<int>? items;
    var blacklist = false;
    for (final (name, bytes) in filter.comps) {
      if (name == '${StackCodec.customPrefix}create:filter_items') items = bytes;
      if (name == '${StackCodec.customPrefix}create:filter_items_blacklist') blacklist = bytes.isNotEmpty && bytes[0] != 0;
    }
    if (items == null) return false;
    final keys = readItemContainerKeys(items);
    if (keys.isEmpty) return blacklist; // an empty blacklist lets everything pass
    final contains = keys.contains(candidate.key);
    return blacklist ? !contains : contains;
  }

  /// The item keys of an `ItemContainerContents` component value (26.3: optional item templates).
  List<String> readItemContainerKeys(List<int> bytes) {
    try {
      return PacketBuffer.decode(bytes, (r) {
        final n = r.readVarInt();
        final out = <String>[];
        for (var i = 0; i < n; i++) {
          if (!r.readBool()) continue;
          final id = r.readVarInt();
          r.readVarInt();
          ItemComponentPatch.read(r);
          final k = env.itemIds.keyOf(id);
          if (k != null) out.add(k);
        }
        return out;
      });
    } on Object {
      return const [];
    }
  }

  Future<void> _craft(Player player, BlueprintSection section) async {
    final server = player.getWorld();
    var firstPass = true;
    var amountCrafted = 0;
    final storage = player.getInventory().asInventory();
    final recipes = _recipeManager(player);
    if (recipes == null) return;
    do {
      // find one item for every filter without taking anything yet
      final taken = <int>[]; // inventory slot per grid cell, -1 for empty
      final used = <int, int>{}; // slot -> count reserved
      var success = true;
      final grid = <String?>[];
      for (var i = 0; i < 9; i++) {
        final filter = section.items[i];
        if (filter.isEmpty) {
          taken.add(-1);
          grid.add(null);
          continue;
        }
        var found = -1;
        String? key;
        for (var slot = 0; slot < storage.getSize(); slot++) {
          final stack = storage.getItem(slot: slot);
          if (stack == null) continue;
          final cand = await StackCodec.read(stack);
          if (cand.isEmpty || (used[slot] ?? 0) >= cand.count) continue;
          if (!_matchesFilter(filter, cand)) continue;
          found = slot;
          key = cand.key;
          break;
        }
        if (found < 0) {
          success = false;
          break;
        }
        used[found] = (used[found] ?? 0) + 1;
        taken.add(found);
        grid.add(key);
      }
      if (!success) break;
      final rows = [
        for (var r = 0; r < 3; r++) [for (var c = 0; c < 3; c++) grid[r * 3 + c]],
      ];
      final result = recipes.matchCrafting(rows);
      if (result == null) break;
      if (result.output.count + amountCrafted > 64) break;
      // commit: take one of each, give the result
      for (final slot in taken) {
        if (slot < 0) continue;
        final stack = storage.getItem(slot: slot);
        if (stack == null) continue;
        final count = await stack.getCount();
        if (count <= 1) {
          // a container-like ingredient leaves its remainder (bucket, bottle)
          final key = await stack.getRegistryKey();
          await storage.setItem(slot: slot, item: null);
          final remainder = _craftingRemainder(key);
          if (remainder != null) await giveToPlayer(player, server, ItemStack.create(registryKey: remainder, count: 1));
        } else {
          await stack.setCount(count: count - 1);
          final remainder = _craftingRemainder(await stack.getRegistryKey());
          if (remainder != null) await giveToPlayer(player, server, ItemStack.create(registryKey: remainder, count: 1));
        }
      }
      amountCrafted += result.output.count;
      if (firstPass) {
        server.playSound(
          sound: Sound.entityItemPickup,
          category: SoundCategory.players,
          pos: player.getPosition(),
          volume: .2,
          pitch: 1 + env.rng.nextDouble(),
        );
      }
      await giveToPlayer(player, server, ItemStack.create(registryKey: result.output.item, count: result.output.count));
      firstPass = false;
    } while (player.asEntity().isSneaking());
  }

  /// The common crafting remainders of vanilla ingredients.
  String? _craftingRemainder(String key) => switch (key) {
    'minecraft:water_bucket' || 'minecraft:lava_bucket' || 'minecraft:milk_bucket' => 'minecraft:bucket',
    'minecraft:honey_bottle' => 'minecraft:glass_bottle',
    _ => null,
  };

  RecipeManager? _recipeManager(Player player) {
    try {
      return env.ctx.host.getServer().getRecipeManager();
    } on Object {
      return null;
    }
  }

  // ---------------------------------------------------------------------------------------
  // Menu
  // ---------------------------------------------------------------------------------------

  /// `BlueprintMenu.allowRepeats()`: the same item may go into several grid slots.
  MenuClickRules get _rules => MenuClickRules(
    slotRules: [
      // `GhostItemMenu.clicked`: a ghost slot takes one item off the cursor.
      for (var i = 0; i < blueprintLayout.ghostSlots; i++)
        MenuSlotRule(
          slot: blueprintGhostSlot(i),
          kind: const MenuSlotKindGhost(),
          maxStackSize: 1,
        ),
    ],
    quickMoveTargets: const [],
  );

  Future<void> _openMenu(Player player, Entity entity, BlueprintState st, int section) async {
    final extra = PacketBuffer.encode((w) {
      w.writeVarInt(entity.getId());
      w.writeVarInt(section);
    });
    final result = raw.menus.openMenuWithOptions(
      player: player,
      menuTypeKey: blueprintMenuType,
      title: TextComponent.translate(key: 'item.create.crafting_blueprint', with_: const []),
      extraData: extra,
      slotCount: blueprintLayout.menuSlots,
      options: MenuOptions(
        applyVanillaClicks: true,
        // The client's menu adds the player inventory first (`BlueprintMenu.addSlots`), so the
        // server tracks a mirror of it instead of the host's player-inventory layout.
        playerInventory: false,
        rules: _rules,
      ),
    );
    if (result is ErrorResult) {
      env.log.warn('Could not open the blueprint menu: ${(result as ErrorResult).value}');
      return;
    }
    _openMenus[player.getId().asString] = (entity.getId(), section);
    await fillPlayerMirror(player);
    final sec = st.section(section);
    for (var i = 0; i < blueprintLayout.ghostSlots; i++) {
      final host = await StackCodec.write(sec.items[i]);
      if (host == null) continue;
      if (i == 9 && st.inferredIcon) StackCodecFlags.markInferred(host);
      await setMenuSlot(player, blueprintGhostSlot(i), host);
    }
  }

  /// `onCraftMatrixChanged` / `BlueprintCraftSlot.setChanged`, after the ghost slots changed.
  Future<void> _onMenuSlotChanged(Server server, MenuSlotChangedEventData e) async {
    if (e.menuType != blueprintMenuType) return;
    final player = e.player;
    final open = _openMenus[player.getId().asString];
    if (open == null) return;
    final entity = findEntity(server, open.$1);
    if (entity == null) return;
    final st = stateOf(entity);
    if (st == null) return;
    final sec = st.section(open.$2);
    var gridChanged = false;
    var modelChanged = false;
    for (final c in e.changes) {
      // The player inventory mirror of the menu is written back to the real inventory.
      if (await applyPlayerMirrorChange(player, c)) continue;
      final slot = blueprintLayout.ghostIndexAt(c.slot);
      if (slot == null) continue;
      sec.items[slot] = await StackCodec.read(c.stack);
      modelChanged = true;
      if (slot == 9 && !sec.items[9].isEmpty) {
        st.inferredIcon = false;
      }
      if (slot < 9) gridChanged = true;
    }
    if (gridChanged) await _inferResult(player, st, sec);
    if (!modelChanged) return;
    _save(entity, st);
    _syncToTrackers(entity, st);
  }

  /// `BlueprintMenu.onCraftMatrixChanged`: the result slot follows the crafting recipe the grid forms.
  Future<void> _inferResult(Player player, BlueprintState st, BlueprintSection sec) async {
    final recipes = _recipeManager(player);
    if (recipes == null) return;
    final rows = [
      for (var r = 0; r < 3; r++)
        [for (var c = 0; c < 3; c++) sec.items[r * 3 + c].isEmpty ? null : sec.items[r * 3 + c].key],
    ];
    final result = recipes.matchCrafting(rows);
    if (result == null) {
      if (sec.items[9].isEmpty || !st.inferredIcon) return;
      sec.items[9] = TStack.empty;
      st.inferredIcon = false;
      await setMenuSlot(player, blueprintGhostSlot(9), null);
      return;
    }
    final out = ItemStack.create(registryKey: result.output.item, count: result.output.count);
    sec.items[9] = await StackCodec.read(out);
    st.inferredIcon = true;
    StackCodecFlags.markInferred(out);
    await setMenuSlot(player, blueprintGhostSlot(9), out);
  }

  void _onMenuClosed(Server server, MenuClosedEventData e) {
    if (e.menuType != blueprintMenuType) return;
    _openMenus.remove(e.player.getId().asString);
  }

  // ---------------------------------------------------------------------------------------
  // BlueprintAssignCompleteRecipePacket
  // ---------------------------------------------------------------------------------------

  void _onCompleteRecipe(Player player, Map<String, Object?> f) {
    final recipeId = f['recipeId'] as String;
    unawaited(_assign(player, recipeId));
  }

  /// `BlueprintItem.assignCompleteRecipe`: the grid shows the ingredients, the result slot the output.
  Future<void> _assign(Player player, String recipeId) async {
    final open = _openMenus[player.getId().asString];
    if (open == null) return;
    final recipes = _recipeManager(player);
    final info = recipes?.getRecipeById(id: recipeId);
    if (info == null) return;
    final world = player.getWorld();
    Entity? entity;
    for (final w in [world]) {
      entity = w.getEntityById(id: open.$1);
    }
    if (entity == null) return;
    final st = stateOf(entity);
    if (st == null) return;
    final sec = st.section(open.$2);
    for (var i = 0; i < 9; i++) {
      sec.items[i] = TStack.empty;
    }
    final cells = <TStack>[];
    final shape = info.shape;
    TStack ingredientStack(Ingredient ing) {
      final key = switch (ing) {
        IngredientItem(:final value) => value,
        IngredientOneOf(:final value) => value.isEmpty ? null : value.first,
        IngredientTag() => null,
      };
      return key == null ? TStack.empty : TStack(key.contains(':') ? key : 'minecraft:$key', 1);
    }

    if (shape != null && shape.pattern.isNotEmpty) {
      final keyMap = {for (final (k, i) in shape.key) k: i};
      for (var row = 0; row < shape.pattern.length && row < 3; row++) {
        final line = shape.pattern[row];
        for (var col = 0; col < line.length && col < 3; col++) {
          final ing = keyMap[line[col]];
          sec.items[row * 3 + col] = ing == null ? TStack.empty : ingredientStack(ing);
        }
      }
    } else {
      for (var i = 0; i < info.ingredients.length && i < 9; i++) {
        cells.add(ingredientStack(info.ingredients[i].ingredient));
        sec.items[i] = cells.last;
      }
    }
    final out = info.results.isEmpty ? null : info.results.first;
    sec.items[9] = out == null ? TStack.empty : TStack(out.item, out.count);
    st.inferredIcon = false;
    _save(entity, st);
    _syncToTrackers(entity, st);
    for (var i = 0; i < blueprintLayout.ghostSlots; i++) {
      final host = await StackCodec.write(sec.items[i]);
      await setMenuSlot(player, blueprintGhostSlot(i), host);
    }
  }
}

/// The `inferred_from_recipe` marker of the result slot the client reads.
abstract final class StackCodecFlags {
  static void markInferred(ItemStack s) {
    try {
      s.setCustomComponent(EquipmentComponents.inferredFromRecipe, EquipmentWire.flag(true));
    } on Object {
      // not registered: the icon shows as a manual choice
    }
  }
}
