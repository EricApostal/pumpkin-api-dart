// Conversions between [CTag] (pure) and the host's `NbtCompound` / `NbtTree`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/nbt_convert.dart';
import '../util/ctag.dart';

extension CTagToHost on CTag {
  /// The host compound with the same content.
  NbtCompound toHost() => NbtCompound.fromTree(valueToTree(toNbt()));
}

extension HostToCTag on NbtCompound {
  /// A pure copy of this compound.
  CTag toCTag() => CTag.fromNbt(treeToValue(toTree()));
}
