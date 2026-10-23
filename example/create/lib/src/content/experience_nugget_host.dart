// `ExperienceNuggetItem.use` (ExperienceNuggetItem.java:29-70) on the host: a right click in the
// air converts the held experience nuggets into experience points. The item's foil and the value
// math it uses live in `material_content.dart`.
import 'package:pumpkin_api/pumpkin_api.dart';

import 'material_content.dart';

/// The key of the nugget (`AllItems.EXPERIENCE_NUGGET`).
const String experienceNuggetKey = 'create:experience_nugget';

/// The experience nugget: `ExperienceNuggetItem.use`.
final class ExperienceNuggetHost {
  void install(Context context) {
    context.intercept(Events.playerUseItem, _onUseItem);
  }

  /// `ExperienceNuggetItem.use`.
  ///
  /// Only a use in the air counts: the host fires `playerUseItem` for a click on a block too, but
  /// Java's `Item.use` runs only after the clicked block passed the click, and the real client
  /// re-sends a use in the air when the block did not handle it
  /// (`pumpkin-plugin-wit/v0.2/event.wit:2004-2012`) — so the air event is Java's `use`. Skipping
  /// the block case keeps chests, doors and the like working.
  Future<PlayerUseItemEventData> _onUseItem(
    Server server,
    PlayerUseItemEventData e,
  ) async {
    if (e.cancelled || e.clickedPos != null) return e;
    final player = e.player;
    final inventory = player.getInventory();
    try {
      final held = inventory.getItemInHand(hand: e.hand);
      if (held == null || await held.getRegistryKey() != experienceNuggetKey) {
        return e;
      }

      // `amountUsed = player.isShiftKeyDown() ? 1 : stack.getCount()` (`:37`).
      final count = await held.getCount();
      final amountUsed = player.asEntity().isSneaking() ? 1 : count;

      // Java spawns one `ExperienceOrb` per value, which the player then has to touch. The port
      // awards their total directly, because the host cannot give an orb a value: a plugin-spawned
      // `minecraft:experience_orb` always carries amount 1 (`EntityType::EXPERIENCE_ORB =>
      // ExperienceOrbEntity::new(entity, 1)`, `crates/pumpkin-core/src/entity/type.rs:275`), and
      // neither `World.spawn-entity` nor `spawn-entity-from-nbt` can change it (the orb reads no
      // NBT at all, `crates/pumpkin-core/src/entity/experience_orb.rs:20-37`; there is no
      // `spawn-experience-orb`). The core already knows how to do it:
      // `ExperienceOrbEntity::spawn(world, position, amount)`
      // (`crates/pumpkin-core/src/entity/experience_orb.rs:30-38`, Java's own orb-value split),
      // so `world.spawn-experience-orb: async func(pos: position, amount: u32) -> entity` on
      // `resource %world` is the missing primitive. Dozens of orbs worth 1 point each would award
      // the wrong grouping and no motion; `Player.addExperiencePoints` is `Player.addExperience`
      // (it recomputes the level and progress and fires the experience event), so the player gains
      // exactly what the Java orbs are worth, but instantly.
      final xp = experienceNuggetOrbs(amountUsed).fold(0, (sum, value) => sum + value);
      await player.addExperiencePoints(points: xp);

      // `itemInHand.shrink(amountUsed)` (`:64`); an emptied hand is set to `ItemStack.EMPTY`.
      final remaining = count - amountUsed;
      if (remaining <= 0) {
        await inventory.setItemInHand(hand: e.hand, item: null);
      } else {
        await held.setCount(count: remaining);
        await inventory.setItemInHand(hand: e.hand, item: held);
      }
      // `InteractionResult.SUCCESS` (or `CONSUME` when the stack ran out, `:65-69`): the click is
      // used up.
      //
      // `:31-34` plays `SoundEvents.AMETHYST_BLOCK_BREAK` on `pLevel.isClientSide()` alone, and the
      // port runs on the server, so there is nothing to play here: a client with Create's item
      // class plays it from its own copy of `use`.
      return e.cancel();
    } finally {
      inventory.dispose();
    }
  }
}