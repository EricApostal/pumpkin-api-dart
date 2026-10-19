// `PackageRepackageHelper` (pure): collects the fragments of one order and repacks them into
// fresh packages, split by the order's crafting context when there is one.
import 'dart:math';

import '../../model/inventory.dart';
import '../../model/orders.dart';
import '../../model/package.dart';
import '../../model/stack.dart';

/// `PackageRepackageHelper`.
class PackageRepackageHelper {
  final Map<int, List<LStack>> collectedPackages = {};

  void clear() => collectedPackages.clear();

  /// `isFragmented(box)`: a package that carries order data.
  bool isFragmented(LStack box) => PackageItem.hasOrderData(box);

  /// `addPackageFragment(box)`: the completed order id, or -1.
  int addPackageFragment(LStack box) {
    final orderId = PackageItem.getOrderId(box);
    if (orderId == -1) return -1;
    collectedPackages.putIfAbsent(orderId, () => []).add(box);
    return isOrderComplete(orderId) ? orderId : -1;
  }

  /// `isOrderComplete(orderId)`.
  bool isOrderComplete(int orderId) {
    final boxes = collectedPackages[orderId] ?? const <LStack>[];
    var finalLinkReached = false;
    links:
    for (var linkCounter = 0; linkCounter < 1000; linkCounter++) {
      if (finalLinkReached) break;
      for (var packageCounter = 0; packageCounter < 1000; packageCounter++) {
        var found = false;
        for (final box in boxes) {
          final data = PackageItem.orderData(box);
          if (data == null) continue;
          if (linkCounter != data.linkIndex) continue;
          if (packageCounter != data.fragmentIndex) continue;
          found = true;
          finalLinkReached = data.isFinalLink;
          if (data.isFinal) continue links;
          break;
        }
        if (!found) return false;
      }
    }
    return true;
  }

  /// `repack(orderId, random)`: the packages to export.
  List<BigStack> repack(int orderId, Random random) {
    final exporting = <BigStack>[];
    var address = '';
    PackageOrderWithCrafts? orderContext;
    final summary = InventorySummary();

    for (final box in collectedPackages[orderId] ?? const <LStack>[]) {
      address = PackageItem.getAddress(box);
      final context = PackageItem.orderData(box)?.orderContext;
      if (context != null && !context.isEmpty) orderContext = context;
      for (final stack in PackageItem.contentsList(box)) {
        summary.addStack(stack);
      }
    }

    final orderedStacks = <BigStack>[];
    if (orderContext != null) {
      final byRecipe = repackBasedOnRecipes(summary, orderContext, random);
      exporting.addAll(byRecipe);
      if (byRecipe.isEmpty) {
        for (final stack in orderContext.stacks) {
          orderedStacks.add(BigStack(stack.stack, stack.count));
        }
      }
    }

    final allItems = summary.getStacks();
    final outputSlots = <LStack>[];

    repack:
    while (true) {
      allItems.removeWhere((e) => e.count == 0);
      if (allItems.isEmpty) break;

      BigStack? targetedEntry;
      if (orderedStacks.isNotEmpty) targetedEntry = orderedStacks.removeAt(0);

      search:
      for (final entry in allItems) {
        var targetAmount = entry.count;
        if (targetAmount == 0) continue;
        if (targetedEntry != null) {
          targetAmount = targetedEntry.count;
          if (!entry.stack.sameItemSameComponents(targetedEntry.stack))
            continue;
        }

        while (targetAmount > 0) {
          final removed = min(
            min(targetAmount, entry.stack.maxStack),
            entry.count,
          );
          if (removed == 0) continue search;

          outputSlots.add(entry.stack.withCount(removed));
          targetAmount -= removed;
          if (targetedEntry != null) targetedEntry.count = targetAmount;
          entry.count -= removed;
        }
        continue repack;
      }
    }

    var currentSlot = 0;
    var target = MemoryInv(PackageItem.slots);
    for (final item in outputSlots) {
      target.set(currentSlot++, item);
      if (currentSlot < PackageItem.slots) continue;
      exporting.add(BigStack(PackageItem.containing(target), 1));
      target = MemoryInv(PackageItem.slots);
      currentSlot = 0;
    }
    if (target.nonEmpty().isNotEmpty)
      exporting.add(BigStack(PackageItem.containing(target), 1));

    for (final box in exporting) {
      box.stack = PackageItem.addAddress(box.stack, address);
    }

    for (var i = 0; i < exporting.length; i++) {
      final box = exporting[i];
      final isFinal = i == exporting.length - 1;
      final outboundContext = isFinal && orderContext != null
          ? orderContext
          : null;
      if (PackageItem.getOrderId(box.stack) == -1) {
        box.stack = PackageItem.setOrder(
          box.stack,
          orderId,
          0,
          true,
          0,
          true,
          outboundContext,
        );
      }
    }

    return exporting;
  }

  /// `repackBasedOnRecipes(summary, order, address, random)`.
  List<BigStack> repackBasedOnRecipes(
    InventorySummary summary,
    PackageOrderWithCrafts order,
    Random random,
  ) {
    if (order.orderedCrafts.isEmpty) return const [];
    final packages = <BigStack>[];

    for (final craftingEntry in order.orderedCrafts) {
      var packagesToCreate = 0;
      crafts:
      for (var i = 0; i < craftingEntry.count; i++) {
        for (final required in craftingEntry.pattern.stacks) {
          if (required.stack.isEmpty) continue;
          if (summary.countOf(required.stack) <= 0) break crafts;
          summary.add(required.stack, -1);
        }
        packagesToCreate++;
      }

      final target = MemoryInv(PackageItem.slots);
      final stacks = craftingEntry.pattern.stacks;
      for (var slot = 0; slot < min(stacks.length, target.slots); slot++) {
        target.set(slot, stacks[slot].stack.withCount(1));
      }

      final box = PackageItem.containing(target);
      final ordered = PackageItem.setOrder(
        box,
        random.nextInt(1 << 31),
        0,
        true,
        0,
        true,
        PackageOrderWithCrafts.singleRecipe(craftingEntry.pattern.stacks),
      );
      packages.add(BigStack(ordered, packagesToCreate));
    }

    return packages;
  }
}
