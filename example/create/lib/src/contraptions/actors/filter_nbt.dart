// The saved form of a `FilteringBehaviour` on an actor block entity: the `Filter` stack, the
// `FilterAmount` and the `UpTo` flag. Shared by the roller and the contraption controls, whose
// block entities each keep one filter (`FilteringBehaviour.write`/`read`).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/nbt_convert.dart';
import '../core/nbt_map.dart';
import '../storage/stacks.dart';

/// `FilteringBehaviour.read` of `Filter` (`TransferUtil.parseItem`).
StoredStack readFilterStack(NbtCompound tag) {
  final filter = tag.getCompound('Filter');
  if (filter == null || filter.isEmpty) return StoredStack.empty;
  return StoredStack.fromNbt(NbtMap.of(valueOfCompound(filter)));
}

/// `FilteringBehaviour.read`: the count is migrated from data written before it existed.
({StoredStack filter, int count, bool upTo}) readFilteringBehaviour(
  NbtCompound tag,
) {
  final filter = readFilterStack(tag);
  var count = tag.getInt('FilterAmount') ?? 0;
  var upTo = tag.getBool('UpTo') ?? false;
  if (count == 0) {
    upTo = true;
    count = filter.isEmpty ? 64 : filter.maxStackSize;
  }
  return (filter: filter, count: count, upTo: upTo);
}

/// `FilteringBehaviour.write`: `Filter` (empty is an empty compound), `FilterAmount`, `UpTo`.
void writeFilteringBehaviour(
  NbtCompound tag,
  StoredStack filter,
  int count,
  bool upTo,
) {
  tag.putCompound(
    'Filter',
    compoundOf((filter.isEmpty ? NbtMap() : filter.toNbt()).toValue()),
  );
  tag.putInt('FilterAmount', count);
  tag.putBool('UpTo', upTo);
}
