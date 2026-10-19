// The data components owned by the equipment module (`create:banktank_air`,
// `create:symmetry_wand`, `create:clipboard_content`, ...): their wire codecs and the
// value models, pure so they can be unit tested. The wire layouts are the
// `StreamCodec`s of the Java classes (see the comments); the host needs a
// `ComponentCodec` description of the same layout for each key.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../core/nbt.dart';
import '../../core/pos.dart';
import '../../protocol/item_stack.dart';
import '../model/dir.dart';
import '../symmetry/mirror.dart';

/// The keys of the components the module registers.
abstract final class EquipmentComponents {
  static const backtankAir = 'create:banktank_air';
  static const inferredFromRecipe = 'create:inferred_from_recipe';
  static const placementPattern = 'create:placement_pattern';
  static const shaperBrush = 'create:shaper_brush';
  static const shaperBrushParams = 'create:shaper_brush_params';
  static const shaperPlacementOptions = 'create:shaper_placement_options';
  static const shaperTool = 'create:shaper_tool';
  static const shaperBlockUsed = 'create:shaper_block_used';
  static const shaperSwap = 'create:shaper_swap';
  static const shaperBlockData = 'create:shaper_block_data';
  static const sandPaperPolishing = 'create:sand_paper_polishing';
  static const sandPaperJei = 'create:sand_paper_jei';
  static const toolboxInventory = 'create:toolbox_inventory';
  static const toolboxUuid = 'create:toolbox_uuid';
  static const symmetryWand = 'create:symmetry_wand';
  static const symmetryWandEnable = 'create:symmetry_wand_enable';
  static const symmetryWandSimulate = 'create:symmetry_wand_simulate';
  static const clipboardContent = 'create:clipboard_content';
  static const clipboardType = 'create:clipboard_type';
  static const clipboardPages = 'create:clipboard_pages';
  static const clipboardReadOnly = 'create:clipboard_read_only';
  static const clipboardCopiedValues = 'create:clipboard_copied_values';
  static const clipboardPreviouslyOpenedPage = 'create:clipboard_previously_opened_page';
}

/// One component the module registers: key, wire layout, persistence.
final class EquipmentComponentSpec {
  final String key;
  final ComponentCodec codec;
  final bool persistent;
  const EquipmentComponentSpec(this.key, this.codec, {this.persistent = true});
}

/// `ClipboardEntry`: checked, text component (NBT), icon (optional stack), item amount.
final ComponentCodec _clipboardEntry = ComponentCodec.sequence([
  ComponentCodec.flag,
  ComponentCodec.nbt,
  ComponentCodec.stack,
  ComponentCodec.int32,
]);

/// All components in the manifest's registration order (the order is not significant to
/// the host ids of other modules; the lead's canonical order applies).
final List<EquipmentComponentSpec> equipmentComponentSpecs = [
  const EquipmentComponentSpec(EquipmentComponents.backtankAir, ComponentCodec.varInt),
  const EquipmentComponentSpec(EquipmentComponents.inferredFromRecipe, ComponentCodec.flag),
  const EquipmentComponentSpec(EquipmentComponents.placementPattern, ComponentCodec.varInt),
  const EquipmentComponentSpec(EquipmentComponents.shaperBrush, ComponentCodec.varInt),
  const EquipmentComponentSpec(EquipmentComponents.shaperBrushParams, ComponentCodec.long),
  const EquipmentComponentSpec(EquipmentComponents.shaperPlacementOptions, ComponentCodec.varInt),
  const EquipmentComponentSpec(EquipmentComponents.shaperTool, ComponentCodec.varInt),
  const EquipmentComponentSpec(EquipmentComponents.shaperBlockUsed, ComponentCodec.varInt),
  const EquipmentComponentSpec(EquipmentComponents.shaperSwap, ComponentCodec.flag),
  const EquipmentComponentSpec(EquipmentComponents.shaperBlockData, ComponentCodec.nbt),
  EquipmentComponentSpec(EquipmentComponents.sandPaperPolishing, ComponentCodec.stack),
  EquipmentComponentSpec(EquipmentComponents.sandPaperJei, ComponentCodec.sequence([])),
  EquipmentComponentSpec(
    EquipmentComponents.toolboxInventory,
    ComponentCodec.sequence([
      ComponentCodec.repeated(ComponentCodec.sequence([ComponentCodec.int32, ComponentCodec.stack])),
      ComponentCodec.int32,
      ComponentCodec.repeated(ComponentCodec.stack),
    ]),
  ),
  const EquipmentComponentSpec(EquipmentComponents.toolboxUuid, ComponentCodec.uuid),
  EquipmentComponentSpec(
    EquipmentComponents.symmetryWand,
    ComponentCodec.sequence([
      ComponentCodec.int32,
      ComponentCodec.float64,
      ComponentCodec.float64,
      ComponentCodec.float64,
      ComponentCodec.text,
      ComponentCodec.flag,
    ]),
  ),
  const EquipmentComponentSpec(EquipmentComponents.symmetryWandEnable, ComponentCodec.flag),
  const EquipmentComponentSpec(EquipmentComponents.symmetryWandSimulate, ComponentCodec.flag),
  EquipmentComponentSpec(
    EquipmentComponents.clipboardContent,
    ComponentCodec.sequence([
      ComponentCodec.varInt,
      ComponentCodec.repeated(ComponentCodec.repeated(_clipboardEntry)),
      ComponentCodec.flag,
      ComponentCodec.varInt,
      ComponentCodec.optional(ComponentCodec.nbt),
    ]),
  ),
  const EquipmentComponentSpec(EquipmentComponents.clipboardType, ComponentCodec.varInt),
  EquipmentComponentSpec(
    EquipmentComponents.clipboardPages,
    ComponentCodec.repeated(ComponentCodec.repeated(_clipboardEntry)),
  ),
  EquipmentComponentSpec(EquipmentComponents.clipboardReadOnly, ComponentCodec.sequence([])),
  const EquipmentComponentSpec(EquipmentComponents.clipboardCopiedValues, ComponentCodec.nbt),
  const EquipmentComponentSpec(EquipmentComponents.clipboardPreviouslyOpenedPage, ComponentCodec.int32),
];

// ------------------------------------------------------------------------------------
// Value codecs
// ------------------------------------------------------------------------------------

/// Wire (de)serialisation of the module's component values.
abstract final class EquipmentWire {
  static Uint8List varInt(int v) => PacketBuffer.encode((w) => w.writeVarInt(v));
  static int readVarInt(List<int> b) => PacketBuffer.decode(b, (r) => r.readVarInt());

  static Uint8List flag(bool v) => PacketBuffer.encode((w) => w.writeBool(v));
  static bool readFlag(List<int> b) => PacketBuffer.decode(b, (r) => r.readBool());

  static Uint8List unit() => Uint8List(0);

  /// `BlockPos.STREAM_CODEC`: the packed long.
  static Uint8List blockPos(P3 p) => PacketBuffer.encode((w) => w.writeLong(packPos(p.$1, p.$2, p.$3)));
  static P3 readBlockPos(List<int> b) => PacketBuffer.decode(b, (r) => unpackPos(r.readLong()));

  static Uint8List uuid(String v) => PacketBuffer.encode((w) => w.writeUuid(v));
  static String readUuid(List<int> b) => PacketBuffer.decode(b, (r) => r.readUuid());

  static Uint8List nbt(NbtValue? v) => NetworkNbt.encode(v);
  static NbtValue? readNbt(List<int> b) => NetworkNbt.decode(b);

  /// `SymmetryMirror.STREAM_CODEC`: orientation index (int), position (3 doubles), type, enable.
  static Uint8List mirror(SymmetryMirror m) => PacketBuffer.encode((w) {
    w.writeInt(m.orientationIndex);
    w.writeDouble(m.position.$1);
    w.writeDouble(m.position.$2);
    w.writeDouble(m.position.$3);
    w.writeString(m.typeName, maxLength: 32767);
    w.writeBool(m.enable);
  });

  static SymmetryMirror readMirror(List<int> b) => PacketBuffer.decode(b, readMirrorFrom);

  static SymmetryMirror readMirrorFrom(PacketReader r) {
    final index = r.readInt();
    final pos = (r.readDouble(), r.readDouble(), r.readDouble());
    final type = r.readString(maxLength: 32767);
    final enable = r.readBool();
    return SymmetryMirror.create(index, pos, type, enable);
  }

  static Uint8List toolboxInventory(ToolboxInventoryData d) => PacketBuffer.encode(d.write);
  static ToolboxInventoryData readToolboxInventory(List<int> b) => PacketBuffer.decode(b, ToolboxInventoryData.read);

  static Uint8List clipboardContent(ClipboardContentData d) => PacketBuffer.encode(d.write);
  static ClipboardContentData readClipboardContent(List<int> b) => PacketBuffer.decode(b, ClipboardContentData.read);
}

// ------------------------------------------------------------------------------------
// ToolboxInventory
// ------------------------------------------------------------------------------------

/// The `ToolboxInventory.STREAM_CODEC` value: 32 slots (8 compartments of 4) and the
/// 8 compartment filters. Stacks are wire stacks ([ItemStackData]).
final class ToolboxInventoryData {
  static const compartments = 8;
  static const stacksPerCompartment = 4;
  static const slotCount = compartments * stacksPerCompartment;

  final List<ItemStackData> slots;
  final List<ItemStackData> filters;

  ToolboxInventoryData({List<ItemStackData>? slots, List<ItemStackData>? filters})
    : slots = slots ?? List.filled(slotCount, ItemStackData.empty, growable: true),
      filters = filters ?? List.filled(compartments, ItemStackData.empty, growable: true);

  /// The map form `ItemSlots` writes: non-empty slots by index, then the size.
  void write(PacketWriter w) {
    final nonEmpty = <int>[for (var i = 0; i < slots.length; i++) if (!slots[i].isEmpty) i];
    w.writeVarInt(nonEmpty.length);
    for (final i in nonEmpty) {
      w.writeInt(i);
      slots[i].write(w, allowEmpty: false);
    }
    // `ItemSlots.size`: the highest non-empty slot + 1 (the handler size for fromHandler).
    w.writeInt(slots.length);
    w.writeVarInt(filters.length);
    for (final f in filters) {
      f.write(w);
    }
  }

  static ToolboxInventoryData read(PacketReader r) {
    final n = r.readVarInt();
    if (n < 0 || n > slotCount) throw PacketException('Implausible toolbox slot count $n');
    final map = <int, ItemStackData>{};
    for (var i = 0; i < n; i++) {
      map[r.readInt()] = ItemStackData.read(r, allowEmpty: false);
    }
    final size = r.readInt();
    final fn = r.readVarInt();
    final filters = [for (var i = 0; i < fn; i++) ItemStackData.read(r)];
    final slots = List<ItemStackData>.filled(size > slotCount ? size : slotCount, ItemStackData.empty, growable: true);
    map.forEach((k, v) {
      if (k >= 0 && k < slots.length) slots[k] = v;
    });
    while (filters.length < compartments) {
      filters.add(ItemStackData.empty);
    }
    return ToolboxInventoryData(slots: slots, filters: filters);
  }
}

// ------------------------------------------------------------------------------------
// Clipboard
// ------------------------------------------------------------------------------------

/// `ClipboardOverrides.ClipboardType`.
enum ClipboardType {
  empty('empty'),
  written('written'),
  editing('editing');

  const ClipboardType(this.serializedName);
  final String serializedName;
}

/// `ClipboardEntry`: [text] is the text component in network NBT form.
final class ClipboardEntryData {
  final bool checked;
  final NbtValue text;
  final ItemStackData icon;
  final int itemAmount;

  const ClipboardEntryData({
    required this.checked,
    required this.text,
    this.icon = ItemStackData.empty,
    this.itemAmount = 0,
  });

  ClipboardEntryData copyWith({bool? checked, NbtValue? text}) => ClipboardEntryData(
    checked: checked ?? this.checked,
    text: text ?? this.text,
    icon: icon,
    itemAmount: itemAmount,
  );

  /// `text.getString()`: plain text of a literal component (string tag or `{"text": ...}`),
  /// concatenated with its `extra` parts; a translatable returns its key.
  String get plainText => _plain(text);

  static String _plain(NbtValue v) {
    switch (v.kind) {
      case NbtKind.string:
        return v.value as String;
      case NbtKind.list:
        return (v.value as List<NbtValue>).map(_plain).join();
      case NbtKind.compound:
        final m = v.asCompound;
        final b = StringBuffer();
        if (m['text'] != null) {
          b.write(_plain(m['text']!));
        } else if (m['translate'] != null) {
          b.write(_plain(m['translate']!));
        }
        final extra = m['extra'];
        if (extra != null) b.write(_plain(extra));
        return b.toString();
      default:
        return '';
    }
  }

  void write(PacketWriter w) {
    w.writeBool(checked);
    NetworkNbt.write(w, text);
    icon.write(w);
    w.writeInt(itemAmount);
  }

  static ClipboardEntryData read(PacketReader r) {
    final checked = r.readBool();
    final text = NetworkNbt.read(r) ?? const NbtValue.string('');
    final icon = ItemStackData.read(r);
    final amount = r.readInt();
    return ClipboardEntryData(checked: checked, text: text, icon: icon, itemAmount: amount);
  }
}

/// `ClipboardContent`.
final class ClipboardContentData {
  final ClipboardType type;
  final List<List<ClipboardEntryData>> pages;
  final bool readOnly;
  final int previouslyOpenedPage;
  final NbtValue? copiedValues;

  const ClipboardContentData({
    this.type = ClipboardType.empty,
    this.pages = const [],
    this.readOnly = false,
    this.previouslyOpenedPage = 0,
    this.copiedValues,
  });

  static const ClipboardContentData empty = ClipboardContentData();

  ClipboardContentData setType(ClipboardType t) => ClipboardContentData(
    type: t,
    pages: pages,
    readOnly: readOnly,
    previouslyOpenedPage: previouslyOpenedPage,
    copiedValues: copiedValues,
  );

  ClipboardContentData setPages(List<List<ClipboardEntryData>> p) => ClipboardContentData(
    type: type,
    pages: p,
    readOnly: readOnly,
    previouslyOpenedPage: previouslyOpenedPage,
    copiedValues: copiedValues,
  );

  ClipboardContentData setCopiedValues(NbtValue v) => ClipboardContentData(
    type: type,
    pages: pages,
    readOnly: readOnly,
    previouslyOpenedPage: previouslyOpenedPage,
    copiedValues: v,
  );

  void write(PacketWriter w) {
    w.writeVarInt(type.index);
    writePages(w, pages);
    w.writeBool(readOnly);
    w.writeVarInt(previouslyOpenedPage);
    final c = copiedValues;
    w.writeBool(c != null);
    if (c != null) NetworkNbt.write(w, c);
  }

  static void writePages(PacketWriter w, List<List<ClipboardEntryData>> pages) {
    w.writeVarInt(pages.length);
    for (final page in pages) {
      w.writeVarInt(page.length);
      for (final e in page) {
        e.write(w);
      }
    }
  }

  static List<List<ClipboardEntryData>> readPages(PacketReader r) {
    final n = r.readVarInt();
    if (n < 0 || n > 4096) throw PacketException('Implausible clipboard page count $n');
    return [
      for (var i = 0; i < n; i++)
        [
          for (var j = 0, m = _checkedCount(r.readVarInt()); j < m; j++) ClipboardEntryData.read(r),
        ],
    ];
  }

  static int _checkedCount(int n) {
    if (n < 0 || n > 4096) throw PacketException('Implausible clipboard entry count $n');
    return n;
  }

  static ClipboardContentData read(PacketReader r) {
    final ordinal = r.readVarInt();
    final type = ordinal >= 0 && ordinal < ClipboardType.values.length ? ClipboardType.values[ordinal] : ClipboardType.empty;
    final pages = readPages(r);
    final readOnly = r.readBool();
    final prev = r.readVarInt();
    final copied = r.readBool() ? NetworkNbt.read(r) : null;
    return ClipboardContentData(type: type, pages: pages, readOnly: readOnly, previouslyOpenedPage: prev, copiedValues: copied);
  }
}
