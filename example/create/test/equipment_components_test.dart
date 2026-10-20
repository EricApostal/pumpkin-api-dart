import 'package:create/src/core/nbt.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:create/src/equipment/clipboard/clipboard_nbt.dart';
import 'package:create/src/equipment/data/equipment_components.dart';
import 'package:create/src/equipment/symmetry/mirror.dart';
import 'package:create/src/protocol/item_stack.dart';
import 'package:test/test.dart';

void main() {
  test('symmetry wand component round trip and layout', () {
    final m = CrossPlaneMirror((1.5, -2.0, 3.25))
      ..setOrientation(CrossPlaneMirror.d)
      ..enable = false;
    final bytes = EquipmentWire.mirror(m);
    expect(EquipmentWire.readMirror(bytes), m);
    // int(4) + 3 doubles(24) + string(1 + 11) + bool(1)
    expect(bytes.length, 4 + 24 + 1 + 11 + 1);
    final spec = equipmentComponentSpecs.firstWhere((s) => s.key == EquipmentComponents.symmetryWand);
    expect(spec.codec.measure(bytes), bytes.length);
  });

  test('simple components measure', () {
    for (final (key, bytes) in [
      (EquipmentComponents.backtankAir, EquipmentWire.varInt(900)),
      (EquipmentComponents.shaperSwap, EquipmentWire.flag(true)),
      (EquipmentComponents.shaperBrushParams, EquipmentWire.blockPos((3, 2, 1))),
      (EquipmentComponents.toolboxUuid, EquipmentWire.uuid('01234567-89ab-cdef-0123-456789abcdef')),
      (EquipmentComponents.sandPaperJei, EquipmentWire.unit()),
    ]) {
      final spec = equipmentComponentSpecs.firstWhere((s) => s.key == key);
      expect(spec.codec.measure(bytes), bytes.length, reason: key);
    }
    expect(EquipmentWire.readBlockPos(EquipmentWire.blockPos((-3, 70, 12))), (-3, 70, 12));
    expect(EquipmentWire.readUuid(EquipmentWire.uuid('01234567-89ab-cdef-0123-456789abcdef')), '01234567-89ab-cdef-0123-456789abcdef');
  });

  test('toolbox inventory round trip', () {
    final d = ToolboxInventoryData();
    d.slots[0] = const ItemStackData(5, 64);
    d.slots[9] = const ItemStackData(7, 3);
    d.filters[0] = const ItemStackData(5, 1);
    final back = EquipmentWire.readToolboxInventory(EquipmentWire.toolboxInventory(d));
    expect(back.slots[0], const ItemStackData(5, 64));
    expect(back.slots[9], const ItemStackData(7, 3));
    expect(back.slots[1].isEmpty, isTrue);
    expect(back.filters[0], const ItemStackData(5, 1));
    expect(back.filters[1].isEmpty, isTrue);
  });

  ClipboardEntryData entry(String text, {bool checked = false}) =>
      ClipboardEntryData(checked: checked, text: NbtValue.string(text));

  test('clipboard content round trip', () {
    final c = ClipboardContentData(
      type: ClipboardType.written,
      pages: [
        [entry('milk'), entry('eggs', checked: true)],
        [entry('flour')],
      ],
      previouslyOpenedPage: 1,
      copiedValues: NbtValue.compound({'a': const NbtValue.int32(1)}),
    );
    final back = EquipmentWire.readClipboardContent(EquipmentWire.clipboardContent(c));
    expect(back.type, ClipboardType.written);
    expect(back.pages.length, 2);
    expect(back.pages[0][1].checked, isTrue);
    expect(back.pages[0][0].plainText, 'milk');
    expect(back.previouslyOpenedPage, 1);
    expect(back.copiedValues!.asCompound['a']!.value, 1);
  });

  test('clipboard codec nbt', () {
    final c = ClipboardContentData(type: ClipboardType.editing, pages: [[entry('x')]]);
    final n = contentToCodecNbt(c, (id) => null);
    expect(n.asCompound['type']!.value, 'editing');
    final pages = n.asCompound['pages']!.value as List<NbtValue>;
    expect(pages.length, 1);
    final e = (pages[0].value as List<NbtValue>)[0].asCompound;
    expect(e['icon']!.asCompound, isEmpty);
    expect(e['item_amount']!.value, 0);
  });

  test('click events are rejected, entries merged', () {
    final bad = NbtValue.compound({'text': const NbtValue.string('hi'), 'click_event': NbtValue.emptyCompound()});
    expect(processClipboard(ClipboardContentData(pages: [[ClipboardEntryData(checked: false, text: bad)]])), isNull);
    expect(processClipboard(ClipboardContentData(pages: [[entry('ok')]])), isNotNull);
    expect(processClipboard(null), isNull);

    final merged = mergeClipboardPages(
      [[entry('a')]],
      [[entry('a'), entry('b', checked: true)], [entry('c')]],
    );
    expect(merged.length, 1);
    expect(merged[0].map((e) => e.plainText), ['a', 'b', 'c']);
    // a full page (12 entries) starts a new one
    final full = [List.generate(12, (i) => entry('e$i'))];
    final m2 = mergeClipboardPages(full, [[entry('new')]]);
    expect(m2.length, 2);
  });

  test('plain text of components', () {
    final styled = NbtValue.compound({
      'text': const NbtValue.string('Hello '),
      'extra': NbtValue.list([NbtValue.compound({'text': const NbtValue.string('world')})]),
    });
    expect(ClipboardEntryData(checked: false, text: styled).plainText, 'Hello world');
  });

  // `minecraft:equippable`'s `equip_sound` is a `Holder<SoundEvent>` resolved
  // through the *host's* sound registry, and the plugin registers no sound
  // events with it (`CreateSounds` only maps names onto vanilla ones). Naming a
  // plugin sound such as `create:copper_armor_equip` therefore throws while the
  // item components are encoded, which aborts the whole module load — the
  // component has to name the vanilla event the wrapper delegates to.
  test('equip sounds resolve through the host sound registry', () {
    expect(
      () => DataComponentCodec.encode('minecraft:equippable', {
        'slot': 'head',
        'equip_sound': 'minecraft:item.armor.equip_gold',
      }),
      returnsNormally,
    );
    expect(
      () => DataComponentCodec.encode('minecraft:equippable', {
        'slot': 'head',
        'equip_sound': 'create:copper_armor_equip',
      }),
      throwsA(isA<ComponentEncodeException>()),
    );
  });
}
