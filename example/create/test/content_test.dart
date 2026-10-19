import 'package:create/src/content/advancement_data.dart';
import 'package:create/src/content/advancement_ids.dart';
import 'package:create/src/content/components.dart';
import 'package:create/src/content/enchantment_data.dart';
import 'package:create/src/content/tag_data.dart';
import 'package:create/src/core/nbt.dart';
import 'package:create/src/manifest/manifest.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

void main() {
  test('data components follow the manifest', () {
    expect(createComponents.length, 57);
    expect([for (final c in createComponents) c.path], [for (final d in kDataComponents) d.key]);
    expect(createComponents.where((c) => c.approximate).map((c) => c.path), ['attribute_filter_matched_attributes']);
    for (final c in createComponents) {
      expect(c.codec.ops, isNotEmpty);
    }
  });

  test('component codecs measure real values', () {
    CreateComponent get(String path) => createComponents.firstWhere((c) => c.path == path);
    // schematic_anchor: a long
    expect(get('schematic_anchor').codec.measure(List.filled(8, 1)), 8);
    // schematic_file: VarInt length + utf8
    final file = PacketBuffer.encode((w) => w.writeString('house.nbt'));
    expect(get('schematic_file').codec.accepts(file), isTrue);
    // schematic_bounds: three ints
    expect(get('schematic_bounds').codec.accepts(List.filled(12, 0)), isTrue);
    expect(get('schematic_bounds').codec.accepts(List.filled(11, 0)), isFalse);
    // sequenced_assembly: text, int, float
    final sa = PacketBuffer.encode((w) {
      w.writeString('create:foo');
      w.writeInt(3);
      w.writeFloat(0.5);
    });
    expect(get('sequenced_assembly').codec.accepts(sa), isTrue);
    // shopping_list: list of (int, long), uuid, uuid
    final shop = PacketBuffer.encode((w) {
      w.writeVarInt(2);
      for (var i = 0; i < 2; i++) {
        w.writeInt(i);
        w.writeLong(123);
      }
      w.writeBytes(List.filled(32, 7));
    });
    expect(get('shopping_list').codec.accepts(shop), isTrue);
    // unit components have no bytes
    expect(get('clipboard_read_only').codec.accepts(const []), isTrue);
    expect(get('sand_paper_jei').codec.accepts(const []), isTrue);
    // symmetry_wand: int, vec3, text, bool
    final sw = PacketBuffer.encode((w) {
      w.writeInt(1);
      w.writeDouble(1);
      w.writeDouble(2);
      w.writeDouble(3);
      w.writeString('plane');
      w.writeBool(true);
    });
    expect(get('symmetry_wand').codec.accepts(sw), isTrue);
    // schematicannon_options: int, bool, bool
    expect(get('schematicannon_options').codec.accepts([0, 0, 0, 1, 1, 0]), isTrue);
    // attribute filter attributes: payload free entries
    final attrs = PacketBuffer.encode((w) {
      w.writeVarInt(2);
      w.writeVarInt(3);
      w.writeBool(false);
      w.writeVarInt(5);
      w.writeBool(true);
    });
    expect(get('attribute_filter_matched_attributes').codec.accepts(attrs), isTrue);
  });

  test('advancement tree', () {
    final tree = AdvancementTree.fromManifest();
    expect(tree.json.length, 102);
    expect(AllAdvancements.all.length, 102);
    expect(AllAdvancements.all.toSet(), tree.json.keys.toSet());
    expect(tree.triggers.length, kTriggers.length + 1);
    expect(tree.triggers, contains(inventoryCheckTrigger));
    expect(tree.inventoryCriteria.length, 13);
    expect(tree.awardable.contains('andesite_casing'), isTrue);
    expect(tree.awardable.contains('andesite_alloy'), isFalse);
    expect(tree.json['andesite_alloy'], contains('create:inventory_check'));
    expect(tree.json['andesite_alloy'], isNot(contains('minecraft:inventory_changed')));
    // every builtin trigger belongs to an advancement
    for (final t in kTriggers) {
      expect(tree.awardable, contains(t.id.substring(7, t.id.length - '_builtin'.length)), reason: t.id);
    }
    final track = tree.inventoryCriteria.firstWhere((c) => c.advancementId == 'track_0');
    bool inTag(String item, String tag) => tag == 'create:tracks' && item == 'create:track';
    expect(track.matches(['minecraft:stone', 'create:track'], inTag), isTrue);
    expect(track.matches(['minecraft:stone'], inTag), isFalse);
    final root = tree.inventoryCriteria.firstWhere((c) => c.advancementId == 'root');
    expect(root.matches(const [], inTag), isTrue);
  });

  test('manifest tags', () {
    final tags = manifestTags();
    expect(tags.where((t) => t.kind == ManifestTagKind.item).length, 98 - 1); // minus the curios/quark tags
    expect(tags.any((t) => t.tag.startsWith('curios:') || t.tag.startsWith('quark:')), isFalse);
    for (final t in tags) {
      expect(t.entries.toSet().length, t.entries.length, reason: t.tag);
    }
  });

  test('potato recovery effect nbt', () {
    final bytes = potatoRecoveryAmmoUse();
    final root = NetworkNbt.decode(bytes)!;
    expect(root.kind, NbtKind.list);
    final first = (root.value as List<NbtValue>).first.asCompound;
    expect(first['effect']!.asCompound['type']!.value, 'minecraft:set');
    final linear = first['effect']!.asCompound['value']!.asCompound;
    expect((linear['per_level_above_first']!.value as double), closeTo(33.333332, 1e-4));
  });
}
