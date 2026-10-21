// The items of Offroad: the four tires. Every other item is a block item and
// comes with its block.
//
// Java: `index/OffroadItems.java`, `content/items/tire/TireItem.java`.
//
// Order matters: `Offroad.init()` registers the blocks (whose builders register
// their block items) before `OffroadItems.init()` (`Offroad.java:37-41`), so the
// three block items come first in the item registry and the tires after them
// (`OffroadIds.items`).
//
// Host: this file uses `pumpkin_api` (item registration).
// ignore_for_file: implementation_imports
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../index/offroad_ids.dart';

/// `TireItem`: the item only warns on the client that a tire cannot be placed
/// (`TireItem.java:18-26`); the server side is a plain item.
const String tirePlacementErrorKey = 'item.offroad.tire.placement_error';

/// The four tire items.
///
/// TODO(parity): `OffroadItems.java:20,30,40,56` gives each tire the
/// `offroad:tire` *default* component. The host's item registry only accepts the
/// vanilla component set (`DataComponentCodec.supported`), so a plugin component
/// cannot be a default component yet; the value is resolved from the item key
/// instead (`TireLike.forItem`, which keeps the same presets).
List<ItemRegistration> offroadItems() => const [
  ItemRegistration(key: OffroadIds.smallTire),
  ItemRegistration(key: OffroadIds.tire),
  ItemRegistration(key: OffroadIds.largeTire),
  ItemRegistration(key: OffroadIds.monstrousTire),
];