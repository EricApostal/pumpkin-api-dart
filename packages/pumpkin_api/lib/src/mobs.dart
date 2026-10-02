/// Typed views of mobs with specialized data (sheep, wolves, villagers, ...).
///
/// A mob's specialized state is exposed by the host as the [MobData] variant.
/// Each view below checks that variant once, then offers plain properties:
///
/// ```dart
/// final zombie = entity.asZombie();
/// if (zombie != null) zombie.isBaby = true;
/// ```
///
/// The views are extension types over [Mob], so every [Mob] member is
/// available on them as well, and they cost nothing at runtime. Property
/// setters read the mob's data, change one field and write it back; they
/// throw a [StateError] if the host rejects the update.
library;

import 'bindings.g.dart';

import 'package:wasm_components/wasm_components.dart' as wc;

Mob? _mobOf(wc.Option<Mob> option) =>
    option.hasValue ? option.requireValue() : null;

/// Wraps [mob] with [wrap] if its data satisfies [matches]; otherwise
/// disposes [mob] when [owned] and returns null.
T? _view<T>(
  Mob? mob,
  bool Function(MobData) matches,
  T Function(Mob) wrap, {
  required bool owned,
}) {
  if (mob == null) return null;
  if (matches(mob.getMobData())) return wrap(mob);
  if (owned) mob.dispose();
  return null;
}

/// A [Mob] known to be a sheep.
///
/// Obtain one with `asSheep()` on a [Mob], [Entity] or [LivingEntity], or with
/// [Sheep.tryFrom].
extension type Sheep._(Mob mob) implements Mob {
  /// Views [mob] as a sheep, or returns null if it is not one.
  static Sheep? tryFrom(Mob mob) =>
      _view(mob, (d) => d is MobDataSheep, Sheep._, owned: false);

  /// All specialized data of this mob.
  SheepData get data => (mob.getMobData() as MobDataSheep).value;

  set data(SheepData value) {
    if (!mob.setMobData(data: MobDataSheep(value))) {
      throw StateError('The host rejected the Sheep data update.');
    }
  }

  /// Fleece dye color.
  WorldDyeColor get color => data.color;

  set color(WorldDyeColor value) => data = data.copyWith(color: value);

  /// Whether the sheep has been sheared.
  bool get isSheared => data.isSheared;

  set isSheared(bool value) => data = data.copyWith(isSheared: value);
}

/// A [Mob] known to be a wolf.
///
/// Obtain one with `asWolf()` on a [Mob], [Entity] or [LivingEntity], or with
/// [Wolf.tryFrom].
extension type Wolf._(Mob mob) implements Mob {
  /// Views [mob] as a wolf, or returns null if it is not one.
  static Wolf? tryFrom(Mob mob) =>
      _view(mob, (d) => d is MobDataWolf, Wolf._, owned: false);

  /// All specialized data of this mob.
  WolfData get data => (mob.getMobData() as MobDataWolf).value;

  set data(WolfData value) {
    if (!mob.setMobData(data: MobDataWolf(value))) {
      throw StateError('The host rejected the Wolf data update.');
    }
  }

  /// Whether the wolf is tamed.
  bool get isTamed => data.isTamed;

  set isTamed(bool value) => data = data.copyWith(isTamed: value);

  /// UUID of the owning player, if any.
  wc.Option<Uuid> get owner => data.owner;

  set owner(wc.Option<Uuid> value) => data = data.copyWith(owner: value);

  /// Whether the wolf is sitting.
  bool get isSitting => data.isSitting;

  set isSitting(bool value) => data = data.copyWith(isSitting: value);

  /// Collar dye color.
  WorldDyeColor get collarColor => data.collarColor;

  set collarColor(WorldDyeColor value) =>
      data = data.copyWith(collarColor: value);

  /// Whether the wolf is angry.
  bool get isAngry => data.isAngry;

  set isAngry(bool value) => data = data.copyWith(isAngry: value);

  /// Whether the wolf is begging.
  bool get isBegging => data.isBegging;

  set isBegging(bool value) => data = data.copyWith(isBegging: value);
}

/// A [Mob] known to be a cat.
///
/// Obtain one with `asCat()` on a [Mob], [Entity] or [LivingEntity], or with
/// [Cat.tryFrom].
extension type Cat._(Mob mob) implements Mob {
  /// Views [mob] as a cat, or returns null if it is not one.
  static Cat? tryFrom(Mob mob) =>
      _view(mob, (d) => d is MobDataCat, Cat._, owned: false);

  /// All specialized data of this mob.
  CatData get data => (mob.getMobData() as MobDataCat).value;

  set data(CatData value) {
    if (!mob.setMobData(data: MobDataCat(value))) {
      throw StateError('The host rejected the Cat data update.');
    }
  }

  /// Whether the cat is tamed.
  bool get isTamed => data.isTamed;

  set isTamed(bool value) => data = data.copyWith(isTamed: value);

  /// UUID of the owning player, if any.
  wc.Option<Uuid> get owner => data.owner;

  set owner(wc.Option<Uuid> value) => data = data.copyWith(owner: value);

  /// Whether the cat is sitting.
  bool get isSitting => data.isSitting;

  set isSitting(bool value) => data = data.copyWith(isSitting: value);

  /// Collar dye color.
  WorldDyeColor get collarColor => data.collarColor;

  set collarColor(WorldDyeColor value) =>
      data = data.copyWith(collarColor: value);
}

/// A [Mob] known to be a villager.
///
/// Obtain one with `asVillager()` on a [Mob], [Entity] or [LivingEntity], or with
/// [Villager.tryFrom].
extension type Villager._(Mob mob) implements Mob {
  /// Views [mob] as a villager, or returns null if it is not one.
  static Villager? tryFrom(Mob mob) =>
      _view(mob, (d) => d is MobDataVillager, Villager._, owned: false);

  /// All specialized data of this mob.
  VillagerData get data => (mob.getMobData() as MobDataVillager).value;

  set data(VillagerData value) {
    if (!mob.setMobData(data: MobDataVillager(value))) {
      throw StateError('The host rejected the Villager data update.');
    }
  }

  /// The villager's profession.
  VillagerProfession get profession => data.profession;

  set profession(VillagerProfession value) =>
      data = data.copyWith(profession: value);

  /// Trading level (1 to 5).
  int get level => data.level;

  set level(int value) => data = data.copyWith(level: value);

  /// Trading experience points.
  int get experience => data.experience;

  set experience(int value) => data = data.copyWith(experience: value);
}

/// A [Mob] known to be a creeper.
///
/// Obtain one with `asCreeper()` on a [Mob], [Entity] or [LivingEntity], or with
/// [Creeper.tryFrom].
extension type Creeper._(Mob mob) implements Mob {
  /// Views [mob] as a creeper, or returns null if it is not one.
  static Creeper? tryFrom(Mob mob) =>
      _view(mob, (d) => d is MobDataCreeper, Creeper._, owned: false);

  /// All specialized data of this mob.
  CreeperData get data => (mob.getMobData() as MobDataCreeper).value;

  set data(CreeperData value) {
    if (!mob.setMobData(data: MobDataCreeper(value))) {
      throw StateError('The host rejected the Creeper data update.');
    }
  }

  /// Whether the creeper is charged.
  bool get isPowered => data.isPowered;

  set isPowered(bool value) => data = data.copyWith(isPowered: value);

  /// Fuse duration in ticks.
  int get fuse => data.fuse;

  set fuse(int value) => data = data.copyWith(fuse: value);

  /// Whether the creeper has been ignited.
  bool get isIgnited => data.isIgnited;

  set isIgnited(bool value) => data = data.copyWith(isIgnited: value);

  /// Explosion radius.
  int get explosionRadius => data.explosionRadius;

  set explosionRadius(int value) =>
      data = data.copyWith(explosionRadius: value);
}

/// A [Mob] known to be a slime or magma cube.
///
/// Obtain one with `asSlime()` on a [Mob], [Entity] or [LivingEntity], or with
/// [Slime.tryFrom].
extension type Slime._(Mob mob) implements Mob {
  /// Views [mob] as a slime or magma cube, or returns null if it is not one.
  static Slime? tryFrom(Mob mob) =>
      _view(mob, (d) => d is MobDataSlime, Slime._, owned: false);

  /// All specialized data of this mob.
  SlimeData get data => (mob.getMobData() as MobDataSlime).value;

  set data(SlimeData value) {
    if (!mob.setMobData(data: MobDataSlime(value))) {
      throw StateError('The host rejected the Slime data update.');
    }
  }

  /// Size of the slime.
  int get size => data.size;

  set size(int value) => data = data.copyWith(size: value);
}

/// A [Mob] known to be an enderman.
///
/// Obtain one with `asEnderman()` on a [Mob], [Entity] or [LivingEntity], or with
/// [Enderman.tryFrom].
extension type Enderman._(Mob mob) implements Mob {
  /// Views [mob] as an enderman, or returns null if it is not one.
  static Enderman? tryFrom(Mob mob) =>
      _view(mob, (d) => d is MobDataEnderman, Enderman._, owned: false);

  /// All specialized data of this mob.
  EndermanData get data => (mob.getMobData() as MobDataEnderman).value;

  set data(EndermanData value) {
    if (!mob.setMobData(data: MobDataEnderman(value))) {
      throw StateError('The host rejected the Enderman data update.');
    }
  }

  /// Block state id the enderman carries, if any.
  wc.Option<int> get carriedBlockState => data.carriedBlockState;

  set carriedBlockState(wc.Option<int> value) =>
      data = data.copyWith(carriedBlockState: value);

  /// Whether the enderman is screaming (angry).
  bool get isScreaming => data.isScreaming;

  /// Whether the enderman is staring at a player.
  bool get isStaring => data.isStaring;
}

/// A [Mob] known to be an iron golem.
///
/// Obtain one with `asIronGolem()` on a [Mob], [Entity] or [LivingEntity], or with
/// [IronGolem.tryFrom].
extension type IronGolem._(Mob mob) implements Mob {
  /// Views [mob] as an iron golem, or returns null if it is not one.
  static IronGolem? tryFrom(Mob mob) =>
      _view(mob, (d) => d is MobDataIronGolem, IronGolem._, owned: false);

  /// All specialized data of this mob.
  IronGolemData get data => (mob.getMobData() as MobDataIronGolem).value;

  set data(IronGolemData value) {
    if (!mob.setMobData(data: MobDataIronGolem(value))) {
      throw StateError('The host rejected the IronGolem data update.');
    }
  }

  /// Whether a player built this golem.
  bool get isPlayerCreated => data.isPlayerCreated;

  set isPlayerCreated(bool value) =>
      data = data.copyWith(isPlayerCreated: value);
}

/// A [Mob] known to be a fox.
///
/// Obtain one with `asFox()` on a [Mob], [Entity] or [LivingEntity], or with
/// [Fox.tryFrom].
extension type Fox._(Mob mob) implements Mob {
  /// Views [mob] as a fox, or returns null if it is not one.
  static Fox? tryFrom(Mob mob) =>
      _view(mob, (d) => d is MobDataFox, Fox._, owned: false);

  /// All specialized data of this mob.
  FoxData get data => (mob.getMobData() as MobDataFox).value;

  set data(FoxData value) {
    if (!mob.setMobData(data: MobDataFox(value))) {
      throw StateError('The host rejected the Fox data update.');
    }
  }

  /// Whether the fox is sitting.
  bool get isSitting => data.isSitting;

  set isSitting(bool value) => data = data.copyWith(isSitting: value);

  /// Whether the fox is sleeping.
  bool get isSleeping => data.isSleeping;

  set isSleeping(bool value) => data = data.copyWith(isSleeping: value);

  /// Whether the fox is crouching.
  bool get isCrouching => data.isCrouching;

  set isCrouching(bool value) => data = data.copyWith(isCrouching: value);
}

/// A [Mob] known to be a shulker.
///
/// Obtain one with `asShulker()` on a [Mob], [Entity] or [LivingEntity], or with
/// [Shulker.tryFrom].
extension type Shulker._(Mob mob) implements Mob {
  /// Views [mob] as a shulker, or returns null if it is not one.
  static Shulker? tryFrom(Mob mob) =>
      _view(mob, (d) => d is MobDataShulker, Shulker._, owned: false);

  /// All specialized data of this mob.
  ShulkerData get data => (mob.getMobData() as MobDataShulker).value;

  set data(ShulkerData value) {
    if (!mob.setMobData(data: MobDataShulker(value))) {
      throw StateError('The host rejected the Shulker data update.');
    }
  }

  /// Face the shulker is attached to.
  BlockDirection get attachedFace => data.attachedFace;

  set attachedFace(BlockDirection value) =>
      data = data.copyWith(attachedFace: value);

  /// How far the shell is open (0 to 100).
  int get peekAmount => data.peekAmount;

  set peekAmount(int value) => data = data.copyWith(peekAmount: value);

  /// Dye color, or none when undyed.
  wc.Option<WorldDyeColor> get color => data.color;

  set color(wc.Option<WorldDyeColor> value) =>
      data = data.copyWith(color: value);
}

/// A [Mob] known to be a zombie.
///
/// Obtain one with `asZombie()` on a [Mob], [Entity] or [LivingEntity], or with
/// [Zombie.tryFrom].
extension type Zombie._(Mob mob) implements Mob {
  /// Views [mob] as a zombie, or returns null if it is not one.
  static Zombie? tryFrom(Mob mob) =>
      _view(mob, (d) => d is MobDataZombie, Zombie._, owned: false);

  /// All specialized data of this mob.
  ZombieData get data => (mob.getMobData() as MobDataZombie).value;

  set data(ZombieData value) {
    if (!mob.setMobData(data: MobDataZombie(value))) {
      throw StateError('The host rejected the Zombie data update.');
    }
  }

  /// Whether the zombie is a baby.
  bool get isBaby => data.isBaby;

  set isBaby(bool value) => data = data.copyWith(isBaby: value);

  /// Whether the zombie can break doors.
  bool get canBreakDoors => data.canBreakDoors;

  set canBreakDoors(bool value) => data = data.copyWith(canBreakDoors: value);
}

/// A [Mob] known to be an ageable animal (cow, pig, chicken, rabbit, ...).
///
/// Obtain one with `asAgeable()` on a [Mob], [Entity] or [LivingEntity], or with
/// [Ageable.tryFrom].
extension type Ageable._(Mob mob) implements Mob {
  /// Views [mob] as an ageable animal (cow, pig, chicken, rabbit, ...), or returns null if it is not one.
  static Ageable? tryFrom(Mob mob) =>
      _view(mob, (d) => d is MobDataAgeable, Ageable._, owned: false);

  /// All specialized data of this mob.
  AgeableData get data => (mob.getMobData() as MobDataAgeable).value;

  set data(AgeableData value) {
    if (!mob.setMobData(data: MobDataAgeable(value))) {
      throw StateError('The host rejected the Ageable data update.');
    }
  }

  /// Whether the animal is a baby.
  bool get isBaby => data.isBaby;

  set isBaby(bool value) => data = data.copyWith(isBaby: value);

  /// Age in ticks (negative for babies).
  int get age => data.age;

  set age(int value) => data = data.copyWith(age: value);

  /// Remaining ticks in love mode.
  int get inLoveTicks => data.inLoveTicks;

  set inLoveTicks(int value) => data = data.copyWith(inLoveTicks: value);
}

/// Typed mob views for a [Entity]. Each returns null if this is not a mob of
/// that kind. The returned view holds a new handle that is released at the
/// end of the current host callback; call `keep()` to retain it.
extension EntityMobViews on Entity {
  /// This as a sheep, or null.
  Sheep? asSheep() =>
      _view(_mobOf(asMob()), (d) => d is MobDataSheep, Sheep._, owned: true);

  /// This as a wolf, or null.
  Wolf? asWolf() =>
      _view(_mobOf(asMob()), (d) => d is MobDataWolf, Wolf._, owned: true);

  /// This as a cat, or null.
  Cat? asCat() =>
      _view(_mobOf(asMob()), (d) => d is MobDataCat, Cat._, owned: true);

  /// This as a villager, or null.
  Villager? asVillager() => _view(
    _mobOf(asMob()),
    (d) => d is MobDataVillager,
    Villager._,
    owned: true,
  );

  /// This as a creeper, or null.
  Creeper? asCreeper() => _view(
    _mobOf(asMob()),
    (d) => d is MobDataCreeper,
    Creeper._,
    owned: true,
  );

  /// This as a slime or magma cube, or null.
  Slime? asSlime() =>
      _view(_mobOf(asMob()), (d) => d is MobDataSlime, Slime._, owned: true);

  /// This as an enderman, or null.
  Enderman? asEnderman() => _view(
    _mobOf(asMob()),
    (d) => d is MobDataEnderman,
    Enderman._,
    owned: true,
  );

  /// This as an iron golem, or null.
  IronGolem? asIronGolem() => _view(
    _mobOf(asMob()),
    (d) => d is MobDataIronGolem,
    IronGolem._,
    owned: true,
  );

  /// This as a fox, or null.
  Fox? asFox() =>
      _view(_mobOf(asMob()), (d) => d is MobDataFox, Fox._, owned: true);

  /// This as a shulker, or null.
  Shulker? asShulker() => _view(
    _mobOf(asMob()),
    (d) => d is MobDataShulker,
    Shulker._,
    owned: true,
  );

  /// This as a zombie, or null.
  Zombie? asZombie() =>
      _view(_mobOf(asMob()), (d) => d is MobDataZombie, Zombie._, owned: true);

  /// This as an ageable animal (cow, pig, chicken, rabbit, ...), or null.
  Ageable? asAgeable() => _view(
    _mobOf(asMob()),
    (d) => d is MobDataAgeable,
    Ageable._,
    owned: true,
  );
}

/// Typed mob views for a [LivingEntity]. Each returns null if this is not a mob of
/// that kind. The returned view holds a new handle that is released at the
/// end of the current host callback; call `keep()` to retain it.
extension LivingEntityMobViews on LivingEntity {
  /// This as a sheep, or null.
  Sheep? asSheep() =>
      _view(_mobOf(asMob()), (d) => d is MobDataSheep, Sheep._, owned: true);

  /// This as a wolf, or null.
  Wolf? asWolf() =>
      _view(_mobOf(asMob()), (d) => d is MobDataWolf, Wolf._, owned: true);

  /// This as a cat, or null.
  Cat? asCat() =>
      _view(_mobOf(asMob()), (d) => d is MobDataCat, Cat._, owned: true);

  /// This as a villager, or null.
  Villager? asVillager() => _view(
    _mobOf(asMob()),
    (d) => d is MobDataVillager,
    Villager._,
    owned: true,
  );

  /// This as a creeper, or null.
  Creeper? asCreeper() => _view(
    _mobOf(asMob()),
    (d) => d is MobDataCreeper,
    Creeper._,
    owned: true,
  );

  /// This as a slime or magma cube, or null.
  Slime? asSlime() =>
      _view(_mobOf(asMob()), (d) => d is MobDataSlime, Slime._, owned: true);

  /// This as an enderman, or null.
  Enderman? asEnderman() => _view(
    _mobOf(asMob()),
    (d) => d is MobDataEnderman,
    Enderman._,
    owned: true,
  );

  /// This as an iron golem, or null.
  IronGolem? asIronGolem() => _view(
    _mobOf(asMob()),
    (d) => d is MobDataIronGolem,
    IronGolem._,
    owned: true,
  );

  /// This as a fox, or null.
  Fox? asFox() =>
      _view(_mobOf(asMob()), (d) => d is MobDataFox, Fox._, owned: true);

  /// This as a shulker, or null.
  Shulker? asShulker() => _view(
    _mobOf(asMob()),
    (d) => d is MobDataShulker,
    Shulker._,
    owned: true,
  );

  /// This as a zombie, or null.
  Zombie? asZombie() =>
      _view(_mobOf(asMob()), (d) => d is MobDataZombie, Zombie._, owned: true);

  /// This as an ageable animal (cow, pig, chicken, rabbit, ...), or null.
  Ageable? asAgeable() => _view(
    _mobOf(asMob()),
    (d) => d is MobDataAgeable,
    Ageable._,
    owned: true,
  );
}

/// Typed mob views for a [Mob]. Each returns null if this mob is not of that
/// kind. The view shares this mob's handle.
extension MobMobViews on Mob {
  /// This as a sheep, or null.
  Sheep? asSheep() => Sheep.tryFrom(this);

  /// This as a wolf, or null.
  Wolf? asWolf() => Wolf.tryFrom(this);

  /// This as a cat, or null.
  Cat? asCat() => Cat.tryFrom(this);

  /// This as a villager, or null.
  Villager? asVillager() => Villager.tryFrom(this);

  /// This as a creeper, or null.
  Creeper? asCreeper() => Creeper.tryFrom(this);

  /// This as a slime or magma cube, or null.
  Slime? asSlime() => Slime.tryFrom(this);

  /// This as an enderman, or null.
  Enderman? asEnderman() => Enderman.tryFrom(this);

  /// This as an iron golem, or null.
  IronGolem? asIronGolem() => IronGolem.tryFrom(this);

  /// This as a fox, or null.
  Fox? asFox() => Fox.tryFrom(this);

  /// This as a shulker, or null.
  Shulker? asShulker() => Shulker.tryFrom(this);

  /// This as a zombie, or null.
  Zombie? asZombie() => Zombie.tryFrom(this);

  /// This as an ageable animal (cow, pig, chicken, rabbit, ...), or null.
  Ageable? asAgeable() => Ageable.tryFrom(this);
}

/// Nullable alternatives to [Entity.asLiving] and [Entity.asMob], which
/// return an `Option`.
extension EntityKindOrNull on Entity {
  /// This entity as a [LivingEntity], or null if it has no health.
  LivingEntity? get livingOrNull {
    final living = asLiving();
    return living.hasValue ? living.requireValue() : null;
  }

  /// This entity as an AI [Mob], or null.
  Mob? get mobOrNull => _mobOf(asMob());
}

/// Nullable alternative to [LivingEntity.asMob].
extension LivingEntityKindOrNull on LivingEntity {
  /// This entity as an AI [Mob], or null.
  Mob? get mobOrNull => _mobOf(asMob());
}
