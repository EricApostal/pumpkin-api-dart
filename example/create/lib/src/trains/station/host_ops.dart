// Host helpers of the station, bogey and display blocks: player messages with Create's English
// texts, held item handling and Create sounds.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/sounds.dart';
import '../../redstone/support/text.dart' show Txt, kCreateEnglish;
import '../support/runtime.dart';

/// The English texts of the Create lang keys the station, bogey and display code shows.
const Map<String, String> kTrainsEnglish = {
  'create.bogey.style.invalid': 'Unnamed style',
  'create.bogey.style.no_other_sizes': 'No other sizes',
  'create.bogey.style.standard': 'Standard',
  'create.bogey.style.updated_style': 'Updated style',
  'create.bogey.style.updated_style_and_size': 'Updated style and size',
  'create.train_assembly.bogey_created': 'Bogey created. Click again to cycle type',
  'create.train_assembly.bogeys_too_close': 'Bogeys %1\$s and %2\$s are too close to each other',
  'create.train_assembly.frontmost_bogey_at_station': 'Frontmost Bogey must be at Station Marker',
  'create.train_assembly.no_bogeys': 'No Bogeys Found',
  'create.train_assembly.no_controls':
      'Attach at least one forward-facing Train Controls block (Are you missing Super Glue?)',
  'create.train_assembly.not_connected_in_order': 'Bogeys are not connected in order',
  'create.train_assembly.nothing_attached': 'No structure attached to Bogey %1\$s',
  'create.train_assembly.requires_casing': 'Use Train Casing to create bogeys on tracks',
  'create.train_assembly.sideways_controls': 'Train Controls cannot face sideways',
  'create.train_assembly.single_bogey_carriage': 'This Bogey type cannot support a carriage on its own',
  'create.train_assembly.too_many_bogeys': 'Too many Bogeys attached: %1\$s',
};

/// `CreateLang.translateDirect(key, args)` rendered with the English texts (`Component.getString`).
String trainsLang(String key, [List<Object?> args = const []]) {
  final template = kTrainsEnglish[key] ?? kCreateEnglish[key];
  if (template == null) return key;
  var i = 0;
  return template.replaceAllMapped(RegExp(r'%(?:(\d+)\$)?([sd%])'), (m) {
    if (m.group(2) == '%') return '%';
    final index = m.group(1) != null ? int.parse(m.group(1)!) - 1 : i++;
    return index >= 0 && index < args.length ? '${args[index]}' : '';
  });
}

/// A translatable [Txt] of the station / bogey texts.
Txt trainsText(String key, [List<Object?> args = const []]) => Txt.literal(trainsLang(key, args));

/// `Component.getString()` of [text], with the station / bogey translations.
String plainTrainsText(Txt text) {
  final b = StringBuffer();
  if (text.literal != null) {
    b.write(text.literal);
  } else {
    b.write(trainsLang(text.translateKey!, [for (final a in text.args) plainTrainsText(a)]));
  }
  for (final s in text.siblings) {
    b.write(plainTrainsText(s));
  }
  return b.toString();
}

/// `player.sendOverlayMessage(component)` (the action bar). [color] is a legacy colour code
/// (`c` red).
void sendOverlay(Player player, String text, {String? color}) {
  final prefix = color == null ? '' : '§$color';
  player.sendSystemMessage(text: TextComponent.fromLegacyString(input: '$prefix$text'), overlay: true);
}

/// Plays a Create sound by entry name (`AllSoundEvents.X.playOnServer`) when the sound service is there.
void playCreateSound(World world, (int, int, int) pos, String name, {double volume = 1, double pitch = 1}) {
  Tr.i.service<CreateSounds>()?.playAtBlock(world, pos, name, volume: volume, pitch: pitch);
}

/// `ItemStack.shrink(n)` of the item in [hand] (`Inventory`-based, like the decoration module).
Future<void> shrinkHeld(Player player, Hand hand, [int n = 1]) async {
  final inv = player.getInventory();
  final held = inv.getItemInHand(hand: hand);
  if (held == null) return;
  final count = await held.getCount();
  if (count <= n) {
    await inv.setItemInHand(hand: hand, item: null);
  } else {
    await held.setCount(count: count - n);
    await inv.setItemInHand(hand: hand, item: held);
  }
}

/// Whether [player] is in creative mode (`player.isCreative()`).
bool isCreative(Player player) => player.getGamemode() == GameMode.creative;
