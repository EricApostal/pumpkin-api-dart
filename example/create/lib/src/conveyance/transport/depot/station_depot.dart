// The station's single schedule slot: a `DepotBehaviour` that only accepts schedule items, so a
// player can leave a schedule on the station and the arriving train picks it up
// (`StationBlockEntity.getAutoSchedule` / `applyAutoSchedule`).
//
// Java: `behaviours.add(depotBehaviour = new DepotBehaviour(this).onlyAccepts(AllItems.SCHEDULE::isIn)
// .withCallback(s -> applyAutoSchedule()))` (`StationBlockEntity.java:165-167`). The depot
// behaviour itself belongs to this module, so the station's slot is provided from here
// (`api/trains.dart`, `StationDepotFactory`).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/trains.dart' show StationDepot, StationDepotFactory;
import '../../../common/direction.dart';
import '../../../core/block_entity.dart';
import '../../belt/transported_item.dart';
import '../../items/item_codec.dart' show ItemCodec;
import 'depot_behaviour.dart';

/// `AllItems.SCHEDULE`: the only item the station's slot accepts.
const String scheduleItemKey = 'create:schedule';

/// Creates the station's schedule slot.
final class StationDepotFactoryImpl implements StationDepotFactory {
  const StationDepotFactoryImpl();

  @override
  StationDepot create(
    CreateBlockEntity station, {
    required void Function() onChanged,
  }) => StationDepotAdapter(station, onChanged: onChanged);
}

/// `DepotBehaviour` restricted to schedule items, as `StationBlockEntity.depotBehaviour`.
///
/// The adapter is the behaviour the station adds and keeps in its `depot` field; the depot itself
/// is a second behaviour of the same block entity (it owns the item, the tick and the sub
/// behaviours).
final class StationDepotAdapter extends BlockEntityBehaviour
    implements StationDepot {
  @override
  String get id => 'station_depot';

  final DepotBehaviour depot;

  StationDepotAdapter(
    CreateBlockEntity station, {
    required void Function() onChanged,
  }) : depot = station.addBehaviour(
         DepotBehaviour()
           ..onlyAccepts((stack) => stack.key == scheduleItemKey)
           ..withCallback((_) => onChanged()),
       ) {
    depot.addSubBehaviours();
  }

  /// `getHeldItemStack()` as the host stack the station reads the schedule component from.
  ///
  /// The slot only ever holds a schedule item, whose data lives in the custom
  /// `create:train_schedule` component: the custom components of the depot's value are set on a
  /// fresh host stack (the sync component setters; the plain ones would need the asynchronous
  /// `ItemStack.setComponent` and are never present on a schedule).
  @override
  ItemStack? get heldItem {
    final held = depot.heldItem;
    if (held == null || held.stack.isEmpty) return null;
    final stack = ItemStack.create(
      registryKey: held.stack.key,
      count: held.stack.count,
    );
    for (final (name, bytes) in held.stack.comps) {
      if (!name.startsWith(ItemCodec.customPrefix)) continue;
      try {
        stack.setCustomComponent(
          name.substring(ItemCodec.customPrefix.length),
          bytes,
        );
      } on Object {
        // a component the host rejects is dropped
      }
    }
    return stack;
  }

  /// `removeHeldItem()`.
  @override
  void removeHeldItem() => depot.heldItem = null;

  /// `SharedDepotBlockMethods.onLanded` for the station: a package item that fell onto the station
  /// enters the schedule slot through `DepotBehaviour.tryInsertingFromSide` (Java
  /// `DirectBeltInputBehaviour.handleInsertion`), `true` when the slot kept the whole stack.
  /// The station calls this from its `on-landed-upon` hook, the port of `StationBlock.fallOn`
  /// (the stock `super.fallOn` fall-damage path stays a no-op for packages because the vanilla
  /// base of every Create block plays dead there).
  @override
  bool acceptLandedPackage(covariant TransportedItemStack transported) => depot
      .tryInsertingFromSide(transported, Direction.down, false)
      .stack
      .isEmpty;
}