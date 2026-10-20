// The clipboard: `ClipboardBlockItem` (use opens the editor on the client, shift places it),
// `ClipboardBlock` / `ClipboardBlockEntity` (the placed clipboard), `ClipboardEditPacket` and the
// copy / paste handler of `ClipboardValueSettingsHandler`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/equipment.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/nbt.dart';
import '../../protocol/item_stack.dart';
import '../data/equipment_components.dart';
import '../host/env.dart';
import '../host/inventory_util.dart';
import '../host/stack_data.dart';
import '../model/dir.dart';
import 'clipboard_nbt.dart';

const String clipboardEntityType = 'create:clipboard';

/// `ClipboardBlockEntity`.
final class ClipboardBlockEntity extends CreateBlockEntity {
  ClipboardBlockEntity(super.worldId, super.pos);

  ClipboardContentData? content;
  String? lastEdit;
  bool _stateChecked = false;

  static String? Function(int)? itemKeyOf;

  @override
  void initialize() {
    super.initialize();
    updateWrittenState();
  }

  @override
  void tick() {
    super.tick();
    if (!_stateChecked) {
      _stateChecked = true;
      updateWrittenState();
    }
  }

  /// `onEditedBy(player)`.
  void onEditedBy(String uuid) {
    lastEdit = uuid;
    sendData();
    updateWrittenState();
  }

  /// `updateWrittenState`: the `written` property follows whether there is content.
  void updateWrittenState() {
    final w = world;
    if (w == null) return;
    final state = w.getBlockState(pos: pos);
    if (state.blockName != 'create:clipboard') return;
    var written = false;
    for (final (k, v) in state.properties) {
      if (k == 'written') written = v == 'true';
    }
    final shouldBeWritten = content != null;
    if (written == shouldBeWritten) return;
    final id = BlockRegistry.resolveState('create:clipboard', {
      for (final (k, v) in state.properties) k: v,
      'written': '$shouldBeWritten',
    });
    if (id != null) unawaited(w.setBlockState(pos: pos, state: id, updateFlags: BlockUpdateFlags.normal));
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    final c = content;
    if (!clientPacket) {
      if (c != null) tag.putByteArray('Content', EquipmentWire.clipboardContent(c));
      return;
    }
    if (c != null) {
      final components = NbtCompound();
      // the `create:clipboard_content` component as the codec writes it
      final nbt = contentToCodecNbt(c, itemKeyOf ?? (_) => null);
      components.putCompound(EquipmentComponents.clipboardContent, _toCompound(nbt));
      tag.putCompound('components', components);
    }
    final le = lastEdit;
    if (le != null) tag.putIntArray('LastEdit', _uuidInts(le));
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (clientPacket) return;
    final bytes = tag.getByteArray('Content');
    if (bytes != null) {
      try {
        content = EquipmentWire.readClipboardContent(bytes);
      } on Object {
        content = null;
      }
    }
  }
}

List<int> _uuidInts(String uuid) {
  final hex = uuid.replaceAll('-', '');
  int part(int i) {
    final v = int.parse(hex.substring(i * 8, i * 8 + 8), radix: 16);
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  return [part(0), part(1), part(2), part(3)];
}

/// The host NBT compound for a pure [NbtValue] compound.
NbtCompound _toCompound(NbtValue v) {
  final c = NbtCompound();
  for (final e in v.asCompound.entries) {
    _put(c, e.key, e.value);
  }
  return c;
}

void _put(NbtCompound c, String key, NbtValue v) {
  switch (v.kind) {
    case NbtKind.byte:
      c.putByte(key, v.value as int);
    case NbtKind.short:
      c.putShort(key, v.value as int);
    case NbtKind.int:
      c.putInt(key, v.value as int);
    case NbtKind.long:
      c.putLong(key, v.value as int);
    case NbtKind.float:
      c.putFloat(key, v.value as double);
    case NbtKind.double:
      c.putDouble(key, v.value as double);
    case NbtKind.string:
      c.putString(key, v.value as String);
    case NbtKind.byteArray:
      c.putByteArray(key, (v.value as List).cast<int>());
    case NbtKind.intArray:
      c.putIntArray(key, (v.value as List).cast<int>());
    case NbtKind.longArray:
      c.putLongArray(key, (v.value as List).cast<int>());
    case NbtKind.list:
      c.putList(key, [for (final e in v.value as List<NbtValue>) _listElement(e)]);
    case NbtKind.compound:
      c.putCompound(key, _toCompound(v));
    case NbtKind.end:
      break;
  }
}

Object _listElement(NbtValue v) {
  switch (v.kind) {
    case NbtKind.compound:
      return _toCompound(v);
    case NbtKind.list:
      return [for (final e in v.value as List<NbtValue>) _listElement(e)];
    case NbtKind.string:
      return NbtTagStringTag(v.value as String);
    case NbtKind.int:
      return NbtTagInt(v.value as int);
    case NbtKind.byte:
      return NbtTagByte(v.value as int);
    case NbtKind.short:
      return NbtTagShort(v.value as int);
    case NbtKind.long:
      return NbtTagLong(v.value as int);
    case NbtKind.float:
      return NbtTagFloat(v.value as double);
    case NbtKind.double:
      return NbtTagDouble(v.value as double);
    default:
      return NbtTagByte(0);
  }
}

final class ClipboardHost {
  final EquipmentEnv env;

  ClipboardHost(this.env);

  void install(CreateContext ctx) {
    ClipboardBlockEntity.itemKeyOf = env.itemIds.keyOf;
    ctx.host.intercept(Events.itemUseFirst, _onUseFirst);
    ctx.host.intercept(Events.playerUseItem, _onUseItem);
    ctx.host.intercept(Events.canAttackBlock, _onLeftClick);
    env.bus.onServerbound('create:clipboard_edit', _onEdit);
  }

  ClipboardBlockEntity? _be(World world, BlockPos pos) =>
      env.ctx.blockEntities.typed<ClipboardBlockEntity>(world.getId(), pos);

  // -- Block --------------------------------------------------------------------------------------

  BlockBehavior behavior() => BlockBehavior(
    onUse: _onUse,
    onAttack: (server, e) => _breakAndCollect(e.targetWorld, e.pos, e.player),
    onPlayerWillDestroy: _willDestroy,
    onNeighborUpdate: _onNeighbor,
    onPlaced: _onPlaced,
  );

  Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
    if (e.player.asEntity().isSneaking()) {
      await _breakAndCollect(e.targetWorld, e.pos, e.player);
      return BlockUseResult.success;
    }
    // The editor opens on the client.
    return BlockUseResult.success;
  }

  /// `breakAndCollect`: the clipboard returns to the player's hand (or inventory).
  Future<void> _breakAndCollect(World world, BlockPos pos, Player player) async {
    final be = _be(world, pos);
    final stack = await stackFor(be?.content);
    await world.destroyBlock(pos: pos, drop: false, player: null, withParticles: true);
    final inv = player.getInventory();
    final selected = inv.heldStackAtSelected;
    if (selected == null) {
      await inv.asInventory().setItem(slot: inv.getSelectedSlot(), item: stack);
    } else {
      await giveToPlayer(player, world, stack);
    }
  }

  /// `getCloneItemStack`: a clipboard item with [content].
  Future<ItemStack> stackFor(ClipboardContentData? content) async {
    final stack = ItemStack.create(registryKey: EqItems.clipboard, count: 1);
    if (content != null) {
      stack.setCustomComponent(EquipmentComponents.clipboardContent, EquipmentWire.clipboardContent(content));
    }
    return stack;
  }

  /// `playerWillDestroy`: survival players get the clipboard back as a drop.
  Future<bool> _willDestroy(Server server, CustomBlockPlayerWillDestroyEventData e) async {
    if (e.player.isCreative) return true;
    final be = _be(e.targetWorld, e.pos);
    final stack = await stackFor(be?.content);
    await e.targetWorld.dropItem((e.pos.x + .5, e.pos.y + .5, e.pos.z + .5), stack);
    return true;
  }

  /// `canSurvive`: the supporting block must not be replaceable.
  Future<void> _onNeighbor(Server server, CustomBlockNeighborUpdateEventData e) async {
    final world = e.targetWorld;
    final state = world.getBlockState(pos: e.pos);
    final props = {for (final (k, v) in state.properties) k: v};
    final face = props['face'] ?? 'floor';
    final facing = Dir.parse(props['facing'] ?? 'north') ?? Dir.north;
    final connected = switch (face) {
      'ceiling' => Dir.down,
      'floor' => Dir.up,
      _ => facing,
    };
    final support = world.getBlockState(pos: e.pos.p3.rel(connected.opposite).blockPos);
    if (!support.replaceable && !support.isAir) return;
    final be = _be(world, e.pos);
    final stack = await stackFor(be?.content);
    await world.destroyBlock(pos: e.pos, drop: false, player: null, withParticles: true);
    await world.dropItem((e.pos.x + .5, e.pos.y + .5, e.pos.z + .5), stack);
  }

  Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
    final be = _be(e.targetWorld, e.pos);
    if (be == null) return;
    final uuid = e.player;
    if (uuid == null || e.moved) return;
    final player = server.getPlayerByUuid(id: uuid);
    if (player == null) return;
    final held = player.getInventory().getItemInHand(hand: Hand.right);
    if (held == null || await held.getRegistryKey() != EqItems.clipboard) return;
    final raw = StackData.raw(held, EquipmentComponents.clipboardContent);
    if (raw != null) {
      try {
        be.content = EquipmentWire.readClipboardContent(raw);
      } on Object {
        be.content = null;
      }
    }
    be.sendData();
    be.updateWrittenState();
  }

  // -- Item ----------------------------------------------------------------------------------------

  /// `ClipboardBlockItem.useOn`: shift places the block, everything else is `use`.
  Future<ItemUseFirstEventData> _onUseFirst(Server server, ItemUseFirstEventData e) async {
    if (await stackKey(e.stack) != EqItems.clipboard) return e;
    final player = e.player;
    final sneaking = player.asEntity().isSneaking();
    if (!sneaking && await _copyOrPaste(player, e.stack, e.blockPos, e.face, paste: false)) {
      return e.copyWith(useResult: ItemUseFirstResult.success);
    }
    if (sneaking) {
      final placed = await _place(server, player, e);
      return placed ? e.copyWith(useResult: ItemUseFirstResult.success) : e;
    }
    await _use(player, e.hand);
    return e.copyWith(useResult: ItemUseFirstResult.success);
  }

  Future<PlayerUseItemEventData> _onUseItem(Server server, PlayerUseItemEventData e) async {
    if (e.clickedPos != null) return e;
    if (await stackKey(e.item) != EqItems.clipboard) return e;
    await _use(e.player, e.hand);
    return e.cancel();
  }

  /// `ClipboardBlockItem.use`: sets the type to `editing`; the client opens the editor.
  Future<void> _use(Player player, Hand hand) async {
    if (hand == Hand.left) return;
    final held = player.getInventory().getItemInHand(hand: hand);
    if (held == null) return;
    player.setCooldown(EqItems.clipboard, 10);
    final raw = StackData.raw(held, EquipmentComponents.clipboardContent);
    var content = ClipboardContentData.empty;
    if (raw != null) {
      try {
        content = EquipmentWire.readClipboardContent(raw);
      } on Object {
        content = ClipboardContentData.empty;
      }
    }
    held.setCustomComponent(EquipmentComponents.clipboardContent, EquipmentWire.clipboardContent(content.setType(ClipboardType.editing)));
    await player.getInventory().setItemInHand(hand: hand, item: held);
  }

  /// The placement of a clipboard (`getStateForPlacement` of `FaceAttachedHorizontalDirectionalBlock`
  /// and `ClipboardBlock`).
  Future<bool> _place(Server server, Player player, ItemUseFirstEventData e) async {
    final world = player.getWorld();
    var pos = e.blockPos;
    if (!world.getBlockState(pos: pos).replaceable) pos = pos.p3.rel(e.face.dir).blockPos;
    final target = world.getBlockState(pos: pos);
    if (!target.replaceable && !target.isAir) return false;
    final look = player.lookDirection;
    final ordered = [...Dir.values]..sort((a, b) {
        double dot(Dir d) => d.dx * look.$1 + d.dy * look.$2 + d.dz * look.$3;
        return dot(b).compareTo(dot(a));
      });
    final horizontal = Dir.fromYRot(player.getYaw());
    String? face;
    Dir? facing;
    for (final d in ordered) {
      String f;
      Dir fc;
      if (d.axis == Ax.y) {
        f = d == Dir.up ? 'ceiling' : 'floor';
        fc = horizontal;
      } else {
        f = 'wall';
        fc = d.opposite;
      }
      final connected = switch (f) {
        'ceiling' => Dir.down,
        'floor' => Dir.up,
        _ => fc,
      };
      final support = world.getBlockState(pos: pos.p3.rel(connected.opposite).blockPos);
      if (support.replaceable || support.isAir) continue;
      face = f;
      facing = fc;
      break;
    }
    if (face == null || facing == null) return false;
    if (face != 'wall') facing = facing.opposite;
    final water = world.getFluidState(pos: pos);
    final waterlogged = water != null && water.fluid == 'minecraft:water' && water.isSource;
    final raw = StackData.raw(e.stack, EquipmentComponents.clipboardContent);
    final written = raw != null;
    final id = BlockRegistry.resolveState('create:clipboard', {
      'face': face,
      'facing': facing.name,
      'waterlogged': '$waterlogged',
      'written': '$written',
    });
    if (id == null) return false;
    await world.setBlockState(pos: pos, state: id, updateFlags: BlockUpdateFlags.normal);
    var be = _be(world, pos);
    be ??= env.ctx.blockEntities.createAt(world, pos, clipboardEntityType) as ClipboardBlockEntity?;
    if (be != null) {
      if (raw != null) {
        try {
          be.content = EquipmentWire.readClipboardContent(raw);
        } on Object {
          be.content = null;
        }
      }
      be.sendData();
    }
    if (!player.isCreative) await shrinkHeld(player, e.hand, 1);
    return true;
  }

  // -- Copy / paste ------------------------------------------------------------------------------------

  /// `ClipboardValueSettingsHandler.interact`: copying values from a block entity (right click)
  /// or pasting them (left click). Returns true when the click was handled.
  Future<bool> _copyOrPaste(Player player, ItemStack item, BlockPos pos, BlockDirection face, {required bool paste}) async {
    if (player.isSpectator) return false;
    if (player.asEntity().isSneaking()) return false;
    final world = player.getWorld();
    final be = env.ctx.blockEntities.at(world.getId(), pos);
    if (be == null) return false;
    var content = ClipboardContentData.empty;
    final raw = StackData.raw(item, EquipmentComponents.clipboardContent);
    if (raw != null) {
      try {
        content = EquipmentWire.readClipboardContent(raw);
      } on Object {
        content = ClipboardContentData.empty;
      }
    }
    if (be is ClipboardBlockEntity) {
      // A click with a clipboard on a placed clipboard copies the entries of the placed one into
      // the held item and cancels the click, for a right click (copy) and a left click (paste)
      // alike: `ClipboardValueSettingsHandler.interact` never lets a left click reach the block,
      // so the placed clipboard is not broken.
      final from = be.content?.pages ?? const <List<ClipboardEntryData>>[];
      final pages = mergeClipboardPages(content.pages, from);
      var next = content.setPages(pages);
      if (pages.isNotEmpty) next = next.setType(ClipboardType.written);
      item.setCustomComponent(EquipmentComponents.clipboardContent, EquipmentWire.clipboardContent(next));
      player.showActionbar(text: TextComponent.translate(key: 'create.clipboard.copied_from_clipboard', with_: [_blockName(world, pos)]));
      return true;
    }
    final cloneables = <ClipboardCloneable>[
      if (be is ClipboardCloneables) ...(be as ClipboardCloneables).clipboardCloneables,
      if (be is ClipboardCloneable) be as ClipboardCloneable,
    ];
    if (cloneables.isEmpty) return false;
    final copied = content.copiedValues;
    if (paste && copied == null) return false;
    final tagIn = _compound(copied);
    var anySuccess = false;
    final tagOut = NbtCompound();
    for (final c in cloneables) {
      if (paste) {
        final sub = tagIn.getCompound(c.clipboardKey) ?? NbtCompound();
        anySuccess = c.readFromClipboard(sub, player, face, false) || anySuccess;
      } else {
        final sub = NbtCompound();
        if (c.writeToClipboard(sub, face)) {
          tagOut.putCompound(c.clipboardKey, sub);
          anySuccess = true;
        }
      }
    }
    if (anySuccess) {
      player.showActionbar(
        text: TextComponent.translate(
          key: paste ? 'create.clipboard.pasted_to' : 'create.clipboard.copied_from',
          with_: [_blockName(world, pos)],
        ),
      );
      if (!paste) {
        var next = content.setType(ClipboardType.written).setCopiedValues(nbtCompoundToValueSafe(tagOut));
        item.setCustomComponent(EquipmentComponents.clipboardContent, EquipmentWire.clipboardContent(next));
      }
    }
    return true;
  }

  NbtCompound _compound(NbtValue? v) {
    final c = NbtCompound();
    if (v == null || v.kind != NbtKind.compound) return c;
    return _toCompound(v);
  }

  TextComponent _blockName(World world, BlockPos pos) {
    final name = world.getBlockState(pos: pos).blockName;
    return TextComponent.translate(key: 'block.${name.replaceFirst(':', '.')}', with_: const []);
  }

  /// Left click with a clipboard on a block entity pastes the copied values (and does not break it).
  Future<CanAttackBlockEventData> _onLeftClick(Server server, CanAttackBlockEventData e) async {
    if (await stackKey(e.stack) != EqItems.clipboard) return e;
    final player = e.player;
    final held = player.getInventory().getItemInHand(hand: Hand.right);
    if (held == null) return e;
    final handled = await _copyOrPaste(player, held, e.blockPos, BlockDirection.up, paste: true);
    return handled ? e.cancel() : e;
  }

  // -- ClipboardEditPacket ----------------------------------------------------------------------------

  void _onEdit(Player player, Map<String, Object?> f) {
    final hotbarSlot = f['hotbarSlot'] as int;
    final raw = f['clipboardContent'] as Map<String, Object?>?;
    final target = f['targetedBlock'] as (int, int, int)?;
    final content = processClipboard(raw == null ? null : _decodeContent(raw));
    unawaited(_handleEdit(player, hotbarSlot, content, target));
  }

  ClipboardContentData _decodeContent(Map<String, Object?> m) {
    final typeOrdinal = (m['type'] as int).clamp(0, ClipboardType.values.length - 1);
    final pages = <List<ClipboardEntryData>>[];
    for (final page in (m['pages'] as List).cast<List<Object?>>()) {
      pages.add([
        for (final e in page.cast<Map<String, Object?>>())
          ClipboardEntryData(
            checked: e['checked'] as bool,
            text: e['text'] as NbtValue,
            icon: e['icon'] as ItemStackData,
            itemAmount: e['itemAmount'] as int,
          ),
      ]);
    }
    return ClipboardContentData(
      type: ClipboardType.values[typeOrdinal],
      pages: pages,
      readOnly: m['readOnly'] as bool,
      previouslyOpenedPage: m['previouslyOpenedPage'] as int,
      copiedValues: m['copiedValues'] as NbtValue?,
    );
  }

  Future<void> _handleEdit(Player player, int hotbarSlot, ClipboardContentData? content, (int, int, int)? target) async {
    if (target != null) {
      final world = player.getWorld();
      final bp = target.blockPos;
      if (!world.isLoaded(pos: bp)) return;
      final (px, py, pz) = player.getPosition();
      final dx = px - (target.$1 + .5), dy = py - (target.$2 + .5), dz = pz - (target.$3 + .5);
      if (dx * dx + dy * dy + dz * dz > 20 * 20) return;
      final be = _be(world, bp);
      if (be == null) return;
      be.content = content;
      be.onEditedBy(player.getId().asString);
      return;
    }
    if (hotbarSlot < 0 || hotbarSlot > 8) return;
    final storage = player.getInventory().asInventory();
    final stack = storage.getItem(slot: hotbarSlot);
    if (stack == null || await stack.getRegistryKey() != EqItems.clipboard) return;
    if (content == null) {
      StackData.remove(stack, EquipmentComponents.clipboardContent);
    } else {
      stack.setCustomComponent(EquipmentComponents.clipboardContent, EquipmentWire.clipboardContent(content));
    }
    await storage.setItem(slot: hotbarSlot, item: stack);
  }
}

NbtValue nbtCompoundToValueSafe(NbtCompound c) {
  final entries = <String, NbtValue>{};
  for (final k in c.keys) {
    final sub = c.getCompound(k);
    if (sub != null) entries[k] = nbtCompoundToValueSafe(sub);
  }
  return NbtValue.compound(entries);
}

extension on PlayerInventory {
  ItemStack? get heldStackAtSelected => asInventory().getItem(slot: getSelectedSlot());
}
