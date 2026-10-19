// `SuperGlueItem`: the item data and the block-destroy rule. The item itself is a plain item; the
// gluing happens in [SuperGlueHandler] (off hand placement) and the selection packets.
//
// Java: `content/contraptions/glue/SuperGlueItem`.
import 'package:pumpkin_api/pumpkin_api.dart';

/// `AllItems.SUPER_GLUE`.
const String glueItemKey = 'create:super_glue';

/// The registration of `create:super_glue` (one use per durability point, stack size 1).
ItemRegistration superGlueRegistration() {
  final encoded = DataComponentCodec.encodeAll({'minecraft:max_damage': 99});
  return ItemRegistration(
    key: glueItemKey,
    components: encoded.encoded,
    maxStackSize: 1,
  );
}
