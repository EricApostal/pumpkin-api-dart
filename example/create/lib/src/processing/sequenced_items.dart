// The three `SequencedAssemblyItem`s (the transitional items of sequenced assembly recipes):
// stack size 1, a progress bar from the `create:sequenced_assembly` component.
import '../core/registry.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';

/// The keys of the transitional items registered by the module.
const List<String> sequencedAssemblyItemKeys = [
  'create:incomplete_precision_mechanism',
  'create:unprocessed_obsidian_sheet',
  'create:incomplete_track',
];

/// Registers the items (`AllItems.INCOMPLETE_*`, in manifest order).
void registerSequencedAssemblyItems(CreateRegistry registry) {
  for (final key in sequencedAssemblyItemKeys) {
    registry.item(ItemRegistration(key: key, maxStackSize: 1));
  }
}

/// `SequencedAssemblyItem.getBarWidth`: 13 pixels at full progress.
int sequencedBarWidth(double progress) => (progress * 13).round();

/// `SequencedAssemblyItem.getBarColor`: `Color.mixColors(0xFFFFC074, 0xFF46FFE0, progress)`.
int sequencedBarColor(double progress) {
  int mix(int a, int b) => (a + (b - a) * progress).round();
  const from = 0xFFC074, to = 0x46FFE0;
  final r = mix((from >> 16) & 0xff, (to >> 16) & 0xff);
  final g = mix((from >> 8) & 0xff, (to >> 8) & 0xff);
  final b = mix(from & 0xff, to & 0xff);
  return (r << 16) | (g << 8) | b;
}
