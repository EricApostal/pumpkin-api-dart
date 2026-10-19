// NBT layouts of the logistics state that a Create client reads or that Java persists.
//
// These mirror the codecs in the Java reference exactly:
//  * `CreateItemStackHandler.serializeNBT` (`Items`, `Size`, `Slot`),
//  * `BigItemStack.CODEC` (`item_stack`, `count`) and `InventorySummary.CODEC` (a list of those),
//  * `PackageOrder.CODEC` (`entries`), `PackageOrderWithCrafts.CODEC` (`ordered_stacks`,
//    `ordered_crafts`) and `PackageItem.PackageOrderData.CODEC`,
//  * `RequestPromise.CODEC` (`ticks_existed`, `promised_stack`) and `RequestPromiseQueue.write`
//    (`List`),
//  * `AutoRequestData.CODEC`,
//  * `PackagePortTarget.CODEC` (a `Codec.dispatch` map: `type` plus the target's own fields).
//
// The plugin's private, lossless form of the same state stays in the `State` JSON (see
// `LgBlockEntity`); these helpers only exist for parity with Java's tags.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../model/inventory.dart';
import '../model/network.dart';
import '../model/orders.dart';
import '../model/stack.dart';
import '../port/package_port_target.dart';
import '../requester/auto_request_data.dart';
import 'nbt_util.dart';

// -- item handlers -----------------------------------------------------------------------------

/// `CreateItemStackHandler.serializeNBT`: `{Items: [{..., Slot: i}], Size: n}`.
NbtCompound itemHandlerToNbt(MemoryInv inv, {required bool client}) {
  final items = <Object>[];
  for (var i = 0; i < inv.slots; i++) {
    final stack = inv.stacks[i];
    if (stack.isEmpty) continue;
    items.add(stackToNbt(stack, client: client)..putInt('Slot', i));
  }
  return NbtCompound()
    ..putList('Items', items)
    ..putInt('Size', inv.slots);
}

/// `CreateItemStackHandler.deserializeNBT`: the stacks at their `Slot` indices.
void itemHandlerFromNbt(NbtCompound tag, MemoryInv inv) {
  final list = tag.getList('Items');
  if (list == null) return;
  for (final entry in list) {
    if (entry is! NbtCompound) continue;
    final slot = entry.getInt('Slot') ?? -1;
    if (slot < 0 || slot >= inv.slots) continue;
    inv.stacks[slot] = stackFromNbt(entry);
  }
}

// -- big stacks and orders ---------------------------------------------------------------------

/// `BigItemStack.CODEC`: `{item_stack: <ItemStack.OPTIONAL_CODEC>, count: n}`.
NbtCompound bigStackToNbt(BigStack entry, {required bool client}) =>
    NbtCompound()
      ..putCompound('item_stack', stackToNbt(entry.stack, client: client))
      ..putInt('count', entry.count);

/// A list of `BigItemStack.CODEC` (`InventorySummary.CODEC`, `PackageOrder.CODEC`).
List<Object> bigStacksToNbt(Iterable<BigStack> list, {required bool client}) =>
    [for (final entry in list) bigStackToNbt(entry, client: client)];

List<BigStack> bigStacksFromNbt(List<Object>? list) => [
  for (final entry in list ?? const <Object>[])
    if (entry is NbtCompound)
      BigStack(
        stackFromNbt(entry.getCompound('item_stack')),
        entry.getInt('count') ?? 0,
      ),
];

/// `PackageOrder.CODEC`: `{entries: [BigItemStack]}`.
NbtCompound packageOrderToNbt(PackageOrder order, {required bool client}) =>
    NbtCompound()
      ..putList('entries', bigStacksToNbt(order.stacks, client: client));

PackageOrder packageOrderFromNbt(NbtCompound tag) =>
    PackageOrder(bigStacksFromNbt(tag.getList('entries')));

/// `PackageOrderWithCrafts.CODEC`; the legacy alternative (`entries` at the top level, 6.0.0 -
/// 6.0.2) is accepted when `ordered_stacks` is absent.
NbtCompound orderWithCraftsToNbt(
  PackageOrderWithCrafts order, {
  required bool client,
}) => NbtCompound()
  ..putCompound(
    'ordered_stacks',
    packageOrderToNbt(order.orderedStacks, client: client),
  )
  ..putList('ordered_crafts', [
    for (final entry in order.orderedCrafts)
      NbtCompound()
        ..putCompound(
          'pattern',
          packageOrderToNbt(entry.pattern, client: client),
        )
        ..putInt('count', entry.count),
  ]);

PackageOrderWithCrafts orderWithCraftsFromNbt(NbtCompound tag) {
  final ordered = tag.getCompound('ordered_stacks');
  if (ordered != null) {
    return PackageOrderWithCrafts(packageOrderFromNbt(ordered), [
      for (final entry in tag.getList('ordered_crafts') ?? const <Object>[])
        if (entry is NbtCompound)
          CraftingEntry(
            packageOrderFromNbt(entry.getCompound('pattern') ?? NbtCompound()),
            entry.getInt('count') ?? 0,
          ),
    ]);
  }
  // The legacy form stores the ordered stacks directly under `entries`.
  if (tag.containsKey('entries')) {
    return PackageOrderWithCrafts.simple(
      bigStacksFromNbt(tag.getList('entries')),
    );
  }
  return PackageOrderWithCrafts.empty();
}

/// `PackageItem.PackageOrderData.CODEC`.
NbtCompound packageOrderDataToNbt(
  PackageOrderData data, {
  required bool client,
}) {
  final tag = NbtCompound()
    ..putInt('order_id', data.orderId)
    ..putInt('link_index', data.linkIndex)
    ..putBool('is_final_link', data.isFinalLink)
    ..putInt('fragment_index', data.fragmentIndex)
    ..putBool('is_final', data.isFinal);
  final context = data.orderContext;
  if (context != null) {
    tag.putCompound(
      'order_context',
      orderWithCraftsToNbt(context, client: client),
    );
  }
  return tag;
}

PackageOrderData? packageOrderDataFromNbt(NbtCompound tag) {
  if (!tag.containsKey('order_id')) return null;
  final context = tag.getCompound('order_context');
  return PackageOrderData(
    tag.getInt('order_id') ?? 0,
    tag.getInt('link_index') ?? 0,
    tag.getBool('is_final_link') ?? false,
    tag.getInt('fragment_index') ?? 0,
    tag.getBool('is_final') ?? false,
    context == null ? null : orderWithCraftsFromNbt(context),
  );
}

// -- promises ----------------------------------------------------------------------------------

/// `RequestPromiseQueue.write`: `{List: [{ticks_existed, promised_stack}]}`.
NbtCompound requestPromiseQueueToNbt(
  RequestPromiseQueue queue, {
  required bool client,
}) => NbtCompound()
  ..putList('List', [
    for (final promise in queue.toList())
      NbtCompound()
        ..putInt('ticks_existed', promise.ticksExisted)
        ..putCompound(
          'promised_stack',
          bigStackToNbt(promise.promisedStack, client: client),
        ),
  ]);

/// `RequestPromiseQueue.read`.
RequestPromiseQueue requestPromiseQueueFromNbt(
  NbtCompound? tag,
  void Function() onChanged,
) {
  final promises = <RequestPromise>[];
  for (final entry in tag?.getList('List') ?? const <Object>[]) {
    if (entry is! NbtCompound) continue;
    final stack = entry.getCompound('promised_stack');
    if (stack == null) continue;
    final parsed = bigStacksFromNbt([stack]);
    promises.add(
      RequestPromise(
        parsed.isEmpty ? BigStack(LStack.empty) : parsed.first,
        entry.getInt('ticks_existed') ?? 0,
      ),
    );
  }
  return RequestPromiseQueue.fromList(promises, onChanged);
}

// -- auto request data -------------------------------------------------------------------------

/// `AutoRequestData.CODEC`.
NbtCompound autoRequestDataToNbt(
  AutoRequestData data, {
  required bool client,
}) => NbtCompound()
  ..putCompound(
    'encoded_request',
    orderWithCraftsToNbt(data.encodedRequest, client: client),
  )
  ..putString('encoded_target_address', data.encodedTargetAddress)
  ..putIntArray('target_offset', [
    data.targetOffset.$1,
    data.targetOffset.$2,
    data.targetOffset.$3,
  ])
  ..putString('target_dim', data.targetDim)
  ..putBool('is_valid', data.isValid);

AutoRequestData autoRequestDataFromNbt(NbtCompound tag) {
  final offset = tag.getIntArray('target_offset');
  final request = tag.getCompound('encoded_request');
  return AutoRequestData(
    request == null
        ? PackageOrderWithCrafts.empty()
        : orderWithCraftsFromNbt(request),
    tag.getString('encoded_target_address') ?? '',
    offset != null && offset.length >= 3
        ? (offset[0], offset[1], offset[2])
        : (0, 0, 0),
    tag.getString('target_dim') ?? 'null',
    tag.getBool('is_valid') ?? false,
  );
}

// -- package port targets ----------------------------------------------------------------------

/// `PackagePortTarget.CODEC`: the dispatch `type` key plus the target's fields.
NbtCompound packagePortTargetToNbt(PackagePortTarget target) {
  final tag = NbtCompound()
    ..putString('type', 'create:${target.type.id}')
    ..putIntArray('relative_pos', [
      target.relativePos.$1,
      target.relativePos.$2,
      target.relativePos.$3,
    ]);
  if (target.type == PackagePortTargetType.chainConveyor) {
    tag.putFloat('chain_pos', target.chainPos);
    final connection = target.connection;
    if (connection != null) {
      tag.putIntArray('connection', [
        connection.$1,
        connection.$2,
        connection.$3,
      ]);
    }
    tag.putBool('flipped', target.flipped);
  }
  return tag;
}

PackagePortTarget? packagePortTargetFromNbt(NbtCompound tag) {
  final rawType = tag.getString('type') ?? '';
  final type = PackagePortTargetType.byId(
    rawType.startsWith('create:') ? rawType.substring(7) : rawType,
  );
  final relative = tag.getIntArray('relative_pos');
  if (type == null || relative == null || relative.length < 3) return null;
  final connection = tag.getIntArray('connection');
  return PackagePortTarget(
    type,
    (relative[0], relative[1], relative[2]),
    chainPos: tag.getDouble('chain_pos') ?? 0,
    connection: connection != null && connection.length >= 3
        ? (connection[0], connection[1], connection[2])
        : null,
    flipped: tag.getBool('flipped') ?? false,
  );
}
