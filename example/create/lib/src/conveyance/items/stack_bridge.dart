// Bridges between the conveyance stack value [ItemValue] and the processing stack value
// [PStack] (pure). Belts carry [ItemValue]s, while the processing machines above them (press,
// saw, basin, ...) speak [PStack]; the two differ only in the `damageable` flag, which PStack
// derives from its stack limit.
import '../../processing/common/stack.dart' show PStack;
import 'item_data.dart';

/// [ItemValue] as a [PStack].
PStack toPStack(ItemValue v) => v.isEmpty
    ? PStack.empty
    : PStack(v.key, v.count, maxStack: v.maxStack, comps: v.comps);

/// [PStack] as an [ItemValue].
ItemValue fromPStack(PStack p) => p.isEmpty
    ? ItemValue.empty
    : ItemValue(p.key, p.count, maxStack: p.maxStack, comps: p.comps);
