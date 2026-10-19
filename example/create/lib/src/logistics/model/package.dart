// Packages (pure): `PackageStyles`, `PackageItem`'s static helpers on [LStack], address matching.
//
// Component encodings. The logical value of a package component inside an [LStack] is UTF-8:
// the address is the plain string, the contents / order data / order context are JSON from the
// mappable models. `host/stack_io.dart` translates these four to the network encodings of the
// Java data components (and keeps a private lossless copy next to them).
import 'dart:convert';
import 'dart:math';

import 'glob.dart';
import 'inventory.dart';
import 'orders.dart';
import 'stack.dart';

/// `PackageStyles.PackageStyle`.
final class PackageStyle {
  final String type;
  final int width;
  final int height;
  final double riggingOffset;
  final bool rare;

  const PackageStyle(this.type, this.width, this.height, this.riggingOffset, {this.rare = false});

  /// `getItemId()` as a registry key (`create:cardboard_package_12x12`, `create:rare_up_package`).
  String get itemKey => 'create:${type}_package${rare ? '' : '_${width}x$height'}';
}

/// `PackageStyles`.
abstract final class PackageStyles {
  static const List<PackageStyle> styles = [
    PackageStyle('cardboard', 12, 12, 23),
    PackageStyle('cardboard', 10, 12, 22),
    PackageStyle('cardboard', 10, 8, 18),
    PackageStyle('cardboard', 12, 10, 21),
    PackageStyle('rare_creeper', 12, 10, 21, rare: true),
    PackageStyle('rare_darcy', 12, 10, 21, rare: true),
    PackageStyle('rare_evan', 12, 10, 21, rare: true),
    PackageStyle('rare_jinx', 12, 10, 21, rare: true),
    PackageStyle('rare_kryppers', 12, 10, 21, rare: true),
    PackageStyle('rare_simi', 12, 10, 21, rare: true),
    PackageStyle('rare_starlotte', 12, 10, 21, rare: true),
    PackageStyle('rare_thunder', 12, 10, 21, rare: true),
    PackageStyle('rare_up', 12, 10, 21, rare: true),
    PackageStyle('rare_vector', 12, 10, 21, rare: true),
  ];

  /// `RARE_CHANCE`: one in 7500 boxes is a rare style.
  static const int rareChance = 7500;

  static final Map<String, PackageStyle> _byKey = {for (final s in styles) s.itemKey: s};

  /// The style of the package item [key], `null` if it is no package.
  static PackageStyle? styleOf(String key) => _byKey[key];

  static List<String> get allKeys => [for (final s in styles) s.itemKey];
  static List<String> get standardKeys => [for (final s in styles) if (!s.rare) s.itemKey];
  static List<String> get rareKeys => [for (final s in styles) if (s.rare) s.itemKey];

  /// `getRandomBox()`: an empty package of a random style.
  static LStack randomBox([Random? random]) {
    final r = random ?? _picker;
    final pool = r.nextInt(rareChance) == 0 ? rareKeys : standardKeys;
    return LStack(pool[r.nextInt(pool.length)], 1, maxStack: 1);
  }

  /// `getDefaultBox()`.
  static LStack defaultBox() => LStack(styles.first.itemKey, 1, maxStack: 1);

  static final Random _picker = Random();
}

/// The component names of the package data.
abstract final class PackageComponents {
  static const String contents = 'create:package_contents';
  static const String address = 'create:package_address';
  static const String orderData = 'create:package_order_data';
  static const String orderContext = 'create:package_order_context';

  /// The components whose value in an [LStack] is the logical (UTF-8) form.
  static const List<String> logical = [contents, address, orderData, orderContext];
}

/// `PackageItem`: the static helpers.
abstract final class PackageItem {
  /// `PackageItem.SLOTS`.
  static const int slots = 9;

  /// `isPackage(stack)`.
  static bool isPackage(LStack stack) => stack.isNotEmpty && PackageStyles.styleOf(stack.key) != null;

  // -- contents -------------------------------------------------------------------------------

  /// `getContents(box)`: the nine slots (empty ones included).
  static MemoryInv getContents(LStack box) {
    final inv = MemoryInv(slots);
    final bytes = box.compBytes(PackageComponents.contents);
    if (bytes == null) return inv;
    try {
      final list = jsonDecode(utf8.decode(bytes)) as List<dynamic>;
      for (var i = 0; i < list.length && i < slots; i++) {
        final e = list[i];
        if (e == null) continue;
        inv.stacks[i] = LStackMapper.fromMap((e as Map).cast<String, dynamic>());
      }
    } on Object {
      // an unreadable value reads as an empty package
    }
    return inv;
  }

  /// The non-empty stacks of the box.
  static List<LStack> contentsList(LStack box) => getContents(box).nonEmpty();

  /// `box.set(PACKAGE_CONTENTS, ...)`.
  static LStack withContents(LStack box, List<LStack> stacks) {
    final list = <Object?>[for (var i = 0; i < slots; i++) i < stacks.length && stacks[i].isNotEmpty ? stacks[i].toMap() : null];
    return box.withComp(PackageComponents.contents, utf8.encode(jsonEncode(list)));
  }

  /// `containing(CreateItemStackHandler)`.
  static LStack containing(MemoryInv stacks, {Random? random}) =>
      withContents(PackageStyles.randomBox(random), stacks.stacks);

  /// `containing(List<ItemStack>)`: the stacks inserted stacked into nine slots.
  static LStack containingList(List<LStack> stacks, {Random? random}) {
    final inv = MemoryInv(slots);
    for (final s in stacks) {
      inv.insertStackedNow(s);
    }
    return containing(inv, random: random);
  }

  // -- address --------------------------------------------------------------------------------

  /// `getAddress(box)`.
  static String getAddress(LStack box) {
    final bytes = box.compBytes(PackageComponents.address);
    return bytes == null ? '' : utf8.decode(bytes);
  }

  static bool hasAddress(LStack box) => box.hasComp(PackageComponents.address);

  /// `addAddress`.
  static LStack addAddress(LStack box, String address) => box.withComp(PackageComponents.address, utf8.encode(address));

  /// `clearAddress`.
  static LStack clearAddress(LStack box) => box.withComp(PackageComponents.address, null);

  /// `matchAddress(boxAddress, address)`.
  static bool matchAddress(String boxAddress, String address) {
    if (address.trim().isEmpty) return boxAddress.trim().isEmpty;
    if (address == '*' || boxAddress == '*') return true;
    if (address == boxAddress) return true;
    return globMatches(boxAddress, address) || globMatches(address, boxAddress);
  }

  static bool matchBoxAddress(LStack box, String address) => matchAddress(getAddress(box), address);

  // -- order data -----------------------------------------------------------------------------

  static PackageOrderData? orderData(LStack box) {
    final bytes = box.compBytes(PackageComponents.orderData);
    if (bytes == null) return null;
    try {
      return PackageOrderDataMapper.fromJson(utf8.decode(bytes));
    } on Object {
      return null;
    }
  }

  /// `setOrder`.
  static LStack setOrder(
    LStack box,
    int orderId,
    int linkIndex,
    bool isFinalLink,
    int fragmentIndex,
    bool isFinal,
    PackageOrderWithCrafts? orderContext,
  ) {
    final data = PackageOrderData(orderId, linkIndex, isFinalLink, fragmentIndex, isFinal, orderContext);
    return box.withComp(PackageComponents.orderData, utf8.encode(data.toJson()));
  }

  static bool hasOrderData(LStack box) => box.hasComp(PackageComponents.orderData);

  /// `getOrderId`: -1 without order data.
  static int getOrderId(LStack box) => orderData(box)?.orderId ?? -1;

  /// `getIndex`: the fragment index, -1 without order data.
  static int getIndex(LStack box) => orderData(box)?.fragmentIndex ?? -1;

  static bool isFinal(LStack box) => orderData(box)?.isFinal ?? false;

  static int getLinkIndex(LStack box) => orderData(box)?.linkIndex ?? -1;

  static bool isFinalLink(LStack box) => orderData(box)?.isFinalLink ?? false;

  /// `getOrderContext`: the order data's context, else the legacy `create:package_order_context`.
  static PackageOrderWithCrafts? getOrderContext(LStack box) {
    final data = orderData(box);
    if (data != null) return data.orderContext;
    final bytes = box.compBytes(PackageComponents.orderContext);
    if (bytes == null) return null;
    try {
      return PackageOrderWithCraftsMapper.fromJson(utf8.decode(bytes));
    } on Object {
      return null;
    }
  }

  /// `addOrderContext`.
  static LStack addOrderContext(LStack box, PackageOrderWithCrafts context) =>
      box.withComp(PackageComponents.orderContext, utf8.encode(context.toJson()));

  // -- geometry -------------------------------------------------------------------------------

  /// `getWidth` in blocks.
  static double getWidth(LStack box) => (PackageStyles.styleOf(box.key)?.width ?? 16) / 16;

  /// `getHeight` in blocks.
  static double getHeight(LStack box) => (PackageStyles.styleOf(box.key)?.height ?? 16) / 16;

  /// `getHookDistance` in blocks.
  static double getHookDistance(LStack box) => (PackageStyles.styleOf(box.key)?.riggingOffset ?? 16) / 16;

  /// `getPackageVelocity(ticksUsed)`: the throw speed after charging for that many ticks.
  static double getPackageVelocity(int ticks) {
    var f = ticks / 20.0;
    f = (f * f + f * 2.0) / 3.0;
    return f > 1.0 ? 1.0 : f;
  }

  /// `getUseDuration`.
  static const int useDuration = 72000;

  /// `canFitInsideContainerItems`: false for packages.
  static bool canFitInsideContainerItems(LStack stack) => !isPackage(stack);
}
