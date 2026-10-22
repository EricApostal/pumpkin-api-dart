// Frequencies and the host: reading the frequency of an item stack, and the item tag
// format the Create client expects in `FrequencyFirst` / `FrequencyLast`
// (`ItemStack.CODEC`: `{id, count, components?}`).
import 'package:pumpkin_api/pumpkin_api.dart';

import 'frequency.dart';

/// The `minecraft:dyed_color` rgb value, -1 if the stack is not dyed.
Future<int> dyedColorOf(ItemStack stack) async {
  for (final c in await stack.getComponents()) {
    if (c.component != DataComponent.dyedColor) continue;
    final v = c.value;
    if (v.length >= 4) {
      final n = (v[0] << 24) | (v[1] << 16) | (v[2] << 8) | v[3];
      return n.toSigned(32);
    }
  }
  return -1;
}

/// `Frequency.of(stack)`. An empty stack gives [Frequency.empty].
Future<Frequency> frequencyOfStack(ItemStack? stack) async {
  if (stack == null) return Frequency.empty;
  if (await stack.getCount() <= 0) return Frequency.empty;
  return Frequency.of(await stack.getRegistryKey(), color: await dyedColorOf(stack));
}

/// `TransferUtil.saveItem(frequency.getStack())`: an empty compound for the empty frequency.
/// The components are the codec form (`ItemStack.CODEC`), where `minecraft:dyed_color` is a
/// compound `{rgb:<int>}` (`DyedItemColor`), not a bare int.
NbtCompound frequencyToNbt(Frequency f) {
  final tag = NbtCompound();
  final item = f.item;
  if (item == null) return tag;
  tag.putString('id', item);
  tag.putInt('count', 1);
  if (f.color != -1) tag.putCompound('components', dyedComponents(f.color));
  return tag;
}

/// `Frequency.of(TransferUtil.parseItem(tag))`.
Frequency frequencyFromNbt(NbtCompound? tag) {
  if (tag == null) return Frequency.empty;
  final id = tag.getString('id');
  if (id == null) return Frequency.empty;
  final count = tag.getInt('count') ?? tag.getInt('Count') ?? 1;
  if (count <= 0) return Frequency.empty;
  var color = -1;
  final components = tag.getCompound('components');
  if (components != null) color = colorOfComponent(components) ?? -1;
  return Frequency.of(id, color: color);
}

/// The `minecraft:dyed_color` of a `components` compound: the codec form `{rgb:<int>}`, with the
/// bare int a save of this port wrote before accepted too.
int? colorOfComponent(NbtCompound components) {
  final dyed = components.getCompound('minecraft:dyed_color');
  if (dyed != null) return dyed.getInt('rgb');
  return components.getInt('minecraft:dyed_color');
}

/// A `components` compound holding `minecraft:dyed_color` in its codec form, what
/// `ItemStack.CODEC` writes (`DyedItemColor.CODEC`).
NbtCompound dyedComponents(int color) =>
    NbtCompound()..putCompound('minecraft:dyed_color', NbtCompound()..putInt('rgb', color));
