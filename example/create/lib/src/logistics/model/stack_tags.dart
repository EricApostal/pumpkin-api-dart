// The saved-tag form of an [LStack]: the `{id, count}` a Create client reads, with the lossless
// private form next to it so a box keeps its address and contents. Pure, so the module can read and
// write these tags without the host (`host/nbt_util.dart` builds the host compound of the same
// shape).
import '../../trains/util/ctag.dart';
import 'stack.dart';

/// The private JSON of a stack, next to the `{id, count}` a Create client reads.
const String pluginStackKey = 'PluginStack';

/// The component that carries the private copy of the components no codec form can hold.
const String customDataComponent = 'minecraft:custom_data';

/// The key inside [customDataComponent] of that copy: a JSON object of component name -> its
/// [LStack.comps] value. `host/stack_io.dart` writes the same pair on the host's item stacks, and
/// the contraption storages read it back (`port/carriage_packages.dart`).
const String privateDataKey = 'CreateLogistics';

/// [stack] as the compound of a package inventory (`CreateItemStackHandler`: `{id, count}`), with
/// the lossless private form next to it so a box keeps its address and contents. `null` for an
/// empty slot.
CTag? stackToCTag(LStack stack) {
  if (stack.isEmpty) return null;
  return CTag()
    ..putString('id', stack.key)
    ..putInt('count', stack.count)
    ..putString(pluginStackKey, stack.toJson());
}

/// The inverse of [stackToCTag].
LStack stackFromCTag(CTag? tag) {
  if (tag == null) return LStack.empty;
  final json = tag.getString(pluginStackKey);
  if (json.isNotEmpty) {
    try {
      return LStackMapper.fromJson(json);
    } on Object {
      // fall through to the plain form
    }
  }
  final id = tag.getString('id');
  final count = tag.getInt('count');
  if (id.isEmpty || count <= 0) return LStack.empty;
  return LStack(id, count);
}