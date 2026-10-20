import 'package:pumpkin_api/pumpkin_api.dart';
void main() {
  for (final name in ['minecraft:item.armor.equip_gold', 'create:copper_armor_equip']) {
    try {
      DataComponentCodec.encode('minecraft:equippable',
        {'slot': 'head', 'equip_sound': name});
      print('OK   $name');
    } catch (e) {
      print('FAIL $name -> $e');
    }
  }
}
