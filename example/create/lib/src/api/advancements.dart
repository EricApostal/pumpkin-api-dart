/// `CreateAdvancement.awardTo` for all modules. Provided by the `content` module as a service:
///
/// ```dart
/// final adv = ctx.services.require<CreateAdvancements>();
/// await adv.award(player, AllAdvancements.andesiteCasing);
/// ```
library;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/block_entity.dart';

export 'data/all_triggers.dart';
export '../content/advancement_ids.dart';

/// Awards Create's advancements.
abstract interface class CreateAdvancements {
  /// `CreateAdvancement.awardTo(player)`: fires the `create:<id>_builtin` trigger. Returns true
  /// when the advancement was newly granted. Throws an [UnsupportedError] for advancements that
  /// use an external trigger (inventory based), like Java.
  Future<bool> award(Player player, String id);

  /// `CreateAdvancement.isAlreadyAwardedTo(player)`: true if the player has it (or it does not exist).
  bool isAlreadyAwardedTo(Player player, String id);

  /// Whether [id] has a builtin trigger and can be awarded directly.
  bool canAward(String id);

  /// `getWorld().getPlayerByUUID(uuid)`: the online player with [uuid], or `null` when they are
  /// offline. The block driven awards ([AdvancementBehaviour]) need it: they remember only the
  /// uuid of the player that placed the block.
  Player? playerByUuid(String uuid);
}

/// `AdvancementBehaviour` (foundation): remembers the player that placed the block
/// (`AdvancementBehaviour.setPlacedBy`) and awards the block's advancements to them
/// (`SmartBlockEntity.award`, e.g. a packager that sends its first package).
///
/// An award only happens while that player is online, and an advancement the player already has
/// is dropped from [advancements]; the player is forgotten once none is left
/// (`AdvancementBehaviour.java:24-140`). The port has no per-block services, so the owning module
/// passes a getter for [CreateAdvancements].
class AdvancementBehaviour extends BlockEntityBehaviour {
  static const String behaviourId = 'Advancement';

  @override
  String get id => behaviourId;

  /// The advancements of this block (`new AdvancementBehaviour(this, AllAdvancements.X, ...)`).
  final List<String> advancements;

  /// The content module's service: a getter, because a block entity is built while the registries
  /// are being applied and the services are provided afterwards.
  final CreateAdvancements? Function() access;

  /// `playerId`: the player that placed the block, `null` when there is none (or after they got
  /// every advancement of the block).
  String? playerId;

  AdvancementBehaviour(this.advancements, this.access);

  /// `isOwnerPresent()`.
  bool get isOwnerPresent => playerId != null;

  /// `setPlayer(id)`.
  void setPlayer(String id) {
    playerId = id;
    removeAwarded();
    owner.markDirty();
  }

  @override
  void initialize() {
    super.initialize();
    // `AdvancementBehaviour.setPlacedBy`: the store remembers the player that placed the block
    // (`CreateBlockEntity.placedBy`), the way Java's `setPlacedBy` hook does. Read before
    // `removeAwarded()`, which drops the owner once every advancement is granted.
    if (playerId == null) playerId = owner.placedBy;
    removeAwarded();
  }

  /// `awardPlayer(advancement)`: awards it to the owner of the block, when they are online.
  Future<void> awardPlayer(String advancement) async {
    final player = _player;
    if (player == null) return;
    final service = access();
    // `advancements.contains(advancement)`: an advancement the player already got is not awarded
    // again (and one this block does not own is ignored, like Java).
    if (service != null && advancements.contains(advancement)) {
      try {
        await service.award(player, advancement);
      } on UnsupportedError {
        // The advancement has an external trigger; Java's `awardTo` cannot grant it either.
      }
    }
    removeAwarded();
  }

  /// `awardPlayerIfNear(advancement, maxDistance)`: like [awardPlayer], only while the owner is
  /// within [maxDistance] of the block (Java `AdvancementBehaviour.awardPlayerIfNear`).
  Future<void> awardPlayerIfNear(String advancement, int maxDistance) async {
    final player = _player;
    if (player == null) return;
    try {
      final (x, y, z) = player.getPosition();
      final dx = x - (owner.pos.x + 0.5);
      final dy = y - (owner.pos.y + 0.5);
      final dz = z - (owner.pos.z + 0.5);
      if (dx * dx + dy * dy + dz * dz > maxDistance * maxDistance) return;
    } on Object {
      // a handle that went invalid
      return;
    }
    await awardPlayer(advancement);
  }

  /// `removeAwarded()`: forget the advancements of [advancements] the owner already has; once
  /// none is left, the owner is dropped too.
  void removeAwarded() {
    final player = _player;
    final service = access();
    if (player == null || service == null) return;
    advancements.removeWhere((id) => service.isAlreadyAwardedTo(player, id));
    if (advancements.isEmpty) {
      playerId = null;
      owner.markDirty();
    }
  }

  Player? get _player {
    final id = playerId;
    return id == null ? null : access()?.playerByUuid(id);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    final id = playerId;
    if (id != null) tag.putIntArray('Owner', _uuidToInts(id));
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    final ints = tag.getIntArray('Owner');
    if (ints != null && ints.length >= 4) {
      playerId = _uuidFromInts(ints.sublist(0, 4));
      return;
    }
    // The text form of a save this port wrote before.
    final text = tag.getString('Owner');
    if (text != null) playerId = text;
  }
}

/// A UUID string as the four ints of `UUIDUtil.CODEC` (what Java saves).
List<int> _uuidToInts(String uuid) {
  final hex = uuid.replaceAll('-', '');
  int part(int i) =>
      int.parse(hex.substring(i * 8, i * 8 + 8), radix: 16).toSigned(32);
  return [part(0), part(1), part(2), part(3)];
}

/// The UUID string of the four ints of `UUIDUtil.CODEC`.
String _uuidFromInts(List<int> ints) {
  final hex = [
    for (final i in ints) (i & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0'),
  ].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}