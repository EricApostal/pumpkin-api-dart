// `RepackagerBlockEntity`: takes packages from the inventory behind it apart and combines the
// fragments of one order into new packages (or passes single packages on).
import 'dart:async';

import '../../host/runtime.dart';
import '../../model/inventory.dart';
import '../../model/orders.dart';
import '../../model/package.dart';
import '../../model/stack.dart';
import '../packager_block_entity.dart';
import 'repackage_helper.dart';

class RepackagerBlockEntity extends PackagerBlockEntity {
  static const String type = 'create:repackager';

  final PackageRepackageHelper repackageHelper = PackageRepackageHelper();

  RepackagerBlockEntity(super.worldId, super.pos);

  @override
  Future<bool> unwrapBox(LStack box, {required bool simulate}) async {
    if (animationTicks > 0) return false;

    final targetInv = targetInventory;
    if (targetInv == null) return false;

    var anySpace = false;
    for (var slot = 0; slot < targetInv.slots; slot++) {
      final remainder = await targetInv.insert(slot, box, simulate: simulate);
      if (remainder.isEmpty) {
        anySpace = true;
        break;
      }
    }

    if (!anySpace) return false;
    if (simulate) return true;

    previouslyUnwrapped = box;
    animationInward = true;
    animationTicks = PackagerBlockEntity.cycle;
    notifyUpdate();
    return true;
  }

  @override
  void recheckIfLinksPresent() {}

  @override
  bool get redstoneModeActive => true;

  @override
  Future<void> attemptToSend(List<PackagingRequest>? queuedRequests) async {
    if (heldBox.isNotEmpty || animationTicks != 0 || buttonCooldown > 0) return;
    if (queuedExitingPackages.isNotEmpty) return;

    final targetInv = targetInventory;
    if (targetInv == null) return;

    await _attemptToRepackage(targetInv);
    if (heldBox.isEmpty) return;

    updateSignAddress();
    if (signBasedAddress.trim().isNotEmpty) {
      heldBox = PackageItem.addAddress(heldBox, signBasedAddress);
    }
  }

  /// `attemptToRepackage(targetInv)`.
  Future<void> _attemptToRepackage(ItemInv targetInv) async {
    repackageHelper.clear();
    var completedOrderId = -1;

    for (var slot = 0; slot < targetInv.slots; slot++) {
      final extracted = await targetInv.extract(slot, 1, simulate: true);
      if (extracted.isEmpty || !PackageItem.isPackage(extracted)) continue;

      if (!repackageHelper.isFragmented(extracted)) {
        await targetInv.extract(slot, 1);
        heldBox = extracted;
        animationInward = false;
        animationTicks = PackagerBlockEntity.cycle;
        notifyUpdate();
        return;
      }

      completedOrderId = repackageHelper.addPackageFragment(extracted);
      if (completedOrderId != -1) break;
    }

    if (completedOrderId == -1) return;

    final boxesToExport = repackageHelper.repack(completedOrderId, Lg.i.random);

    for (var slot = 0; slot < targetInv.slots; slot++) {
      final extracted = await targetInv.extract(slot, 1, simulate: true);
      if (extracted.isEmpty || !PackageItem.isPackage(extracted)) continue;
      if (PackageItem.getOrderId(extracted) != completedOrderId) continue;
      await targetInv.extract(slot, 1);
    }

    if (boxesToExport.isEmpty) return;
    queuedExitingPackages.addAll(boxesToExport);
    notifyUpdate();
  }
}
