import 'package:dart_mappable/dart_mappable.dart' show MapperException;

import '../core/api.dart';
import '../core/clock.dart';
import '../core/storage.dart';
import 'catalog.dart';
import 'model.dart';
import 'permissions.dart';

const kitsPath = 'kits/kits.json';
const configPath = 'kits/config.json';
const claimsPath = 'kits/claims.json';

/// A player claiming a kit. The server side implements it on the player's
/// inventory, tests use a fake.
abstract interface class KitRecipient {
  String get uuid;
  String get name;
  bool hasPermission(String node);

  /// Whether all of [items] fit into the inventory at once.
  bool canFit(List<KitItem> items);

  /// Puts all of [items] into the inventory. All or nothing: if it throws,
  /// whatever was already put in has been taken out again.
  void give(List<KitItem> items);
}

/// Where a player stands with a kit.
enum KitState {
  /// Can be claimed now.
  available,

  /// The player lacks the kit's permission.
  locked,

  /// A one-time kit that was claimed already.
  claimed,

  /// Waiting for the cooldown, see [KitStatus.remaining].
  cooldown,
}

final class KitStatus {
  final KitState state;

  /// For [KitState.cooldown]: how long to wait.
  final Duration? remaining;

  const KitStatus(this.state, [this.remaining]);

  bool get canClaim => state == KitState.available;
}

enum ClaimFailure {
  unknownKit,
  noPermission,
  alreadyClaimed,
  onCooldown,
  insufficientFunds,
  paymentRefused,
  noSpace,
  deliveryFailed,
}

/// The outcome of a claim.
final class ClaimResult {
  final ClaimFailure? failure;
  final Kit? kit;

  /// What the player paid.
  final int charged;

  /// The player's balance afterwards (0 when no economy was involved).
  final int balance;

  /// For [ClaimFailure.onCooldown]: the wait.
  final Duration? remaining;

  /// For [ClaimFailure.insufficientFunds]: how much is missing.
  final int missing;

  /// For [ClaimFailure.unknownKit]: what the player asked for.
  final String? requested;

  const ClaimResult.ok(Kit this.kit, {this.charged = 0, this.balance = 0})
    : failure = null,
      remaining = null,
      requested = null,
      missing = 0;

  const ClaimResult.failed(
    ClaimFailure this.failure, {
    this.kit,
    this.remaining,
    this.missing = 0,
    this.balance = 0,
    this.requested,
  }) : charged = 0;

  bool get isOk => failure == null;
}

/// What `/kit reload` found.
final class KitReload {
  final String? error;
  final List<String> problems;
  final int kits;

  const KitReload.failed(String this.error) : problems = const [], kits = 0;
  const KitReload.ok(this.kits, this.problems) : error = null;

  bool get ok => error == null;
}

/// An admin edit that could not be done; [message] is shown to the admin.
final class KitException implements Exception {
  final String message;
  const KitException(this.message);

  @override
  String toString() => message;
}

/// The logic of the kits: who may claim what and when, payment, the claim
/// history, and the admin edits. Plain Dart, no server bindings.
///
/// A claim is all or nothing: space is checked first, then the price is
/// charged, then the items are handed over; if that fails the price is
/// refunded and no claim is recorded.
final class KitService {
  final Economy economy;
  final Clock clock;
  final JsonDocument<KitCatalog> _catalogDoc;
  final JsonDocument<KitsConfig> _configDoc;
  final JsonDocument<KitClaims> _claimsDoc;
  final bool Function(String key) isKnownItem;
  final bool Function(String key) isKnownEnchantment;
  final LogSink _warn;

  List<Kit> _kits = const [];
  List<String> _problems = const [];

  KitService({
    required this.economy,
    required this.clock,
    required JsonDocument<KitCatalog> catalog,
    required JsonDocument<KitsConfig> config,
    required JsonDocument<KitClaims> claims,
    required this.isKnownItem,
    required this.isKnownEnchantment,
    LogSink? warn,
  }) : _catalogDoc = catalog,
       _configDoc = config,
       _claimsDoc = claims,
       _warn = warn ?? ((_) {}) {
    _rebuild();
  }

  KitsConfig get config => _configDoc.value;

  /// The usable kits, in file order.
  List<Kit> get kits => _kits;

  /// What was wrong with the kits file the last time it was read.
  List<String> get problems => _problems;

  Kit? kit(String name) {
    final lower = name.toLowerCase();
    for (final kit in _kits) {
      if (kit.name == lower) return kit;
    }
    return null;
  }

  void _rebuild() {
    final report = validateKits(
      _catalogDoc.value,
      isKnownItem: isKnownItem,
      isKnownEnchantment: isKnownEnchantment,
    );
    _kits = report.kits;
    _problems = report.problems;
  }

  // -- Status -----------------------------------------------------------------

  /// The claim history of [uuid] with [kit], or `null` if never claimed.
  KitClaim? claimOf(String uuid, String kit) =>
      _claimsDoc.value.players[uuid]?[kit];

  /// Whether [uuid] ever claimed the kit called [name].
  bool hasClaimed(String uuid, String name) => claimOf(uuid, name) != null;

  /// Where a player stands with [kit]. [hasPermission] answers permission
  /// checks for that player.
  KitStatus status(
    String uuid,
    Kit kit,
    bool Function(String node) hasPermission,
  ) {
    if (!hasPermission(kit.permission)) return const KitStatus(KitState.locked);
    if (hasPermission(KitPerms.bypass.node)) {
      return const KitStatus(KitState.available);
    }
    final claim = claimOf(uuid, kit.name);
    if (claim == null) return const KitStatus(KitState.available);
    if (kit.oneTime) return const KitStatus(KitState.claimed);
    if (kit.cooldownSeconds == 0) return const KitStatus(KitState.available);
    final elapsed = clock.now().difference(claim.lastClaimed);
    // A clock that went back must not lock a player out for longer than the
    // cooldown itself.
    final remaining = elapsed.isNegative
        ? kit.cooldown
        : kit.cooldown - elapsed;
    return remaining > Duration.zero
        ? KitStatus(KitState.cooldown, remaining)
        : const KitStatus(KitState.available);
  }

  // -- Claiming ---------------------------------------------------------------

  /// Gives the kit called [name] to [who].
  ClaimResult claim(KitRecipient who, String name) {
    final kit = this.kit(name);
    if (kit == null) {
      return ClaimResult.failed(ClaimFailure.unknownKit, requested: name);
    }
    ClaimResult fail(ClaimFailure f, {Duration? remaining, int missing = 0}) =>
        ClaimResult.failed(
          f,
          kit: kit,
          remaining: remaining,
          missing: missing,
          balance: economy.balance(who.uuid),
        );

    final status = this.status(who.uuid, kit, who.hasPermission);
    switch (status.state) {
      case KitState.locked:
        return fail(ClaimFailure.noPermission);
      case KitState.claimed:
        return fail(ClaimFailure.alreadyClaimed);
      case KitState.cooldown:
        return fail(ClaimFailure.onCooldown, remaining: status.remaining);
      case KitState.available:
        break;
    }
    if (!who.canFit(kit.items)) return fail(ClaimFailure.noSpace);

    if (kit.price > 0) {
      final paid = economy.withdraw(
        who.uuid,
        kit.price,
        reason: 'kit: ${kit.name}',
      );
      if (!paid.isOk) {
        return paid.failure == TransactionFailure.insufficientFunds
            ? fail(
                ClaimFailure.insufficientFunds,
                missing: kit.price - paid.balance,
              )
            : fail(ClaimFailure.paymentRefused);
      }
    }

    try {
      who.give(kit.items);
    } catch (e) {
      _warn('Could not give kit ${kit.name} to ${who.name}: $e');
      if (kit.price > 0) {
        final back = economy.deposit(
          who.uuid,
          kit.price,
          reason: 'kit refund: ${kit.name}',
        );
        if (!back.isOk) {
          _warn('Could not refund ${kit.price} to ${who.name} (${who.uuid})');
        }
      }
      return fail(ClaimFailure.deliveryFailed);
    }

    _recordClaim(who.uuid, kit.name);
    return ClaimResult.ok(
      kit,
      charged: kit.price,
      balance: kit.price > 0 ? economy.balance(who.uuid) : 0,
    );
  }

  void _recordClaim(String uuid, String kit) {
    final previous = claimOf(uuid, kit);
    final players = _claimsDoc.value.players;
    _claimsDoc.value = KitClaims(
      players: {
        ...players,
        uuid: {
          ...?players[uuid],
          kit: KitClaim(
            lastClaimed: clock.now(),
            count: (previous?.count ?? 0) + 1,
          ),
        },
      },
    );
    // Cooldowns and one-time limits must survive a crash.
    _claimsDoc.save();
  }

  /// Gives the starter kit to a player who just joined for the first time.
  /// Returns `null` when nothing should happen: the feature is off, the kit
  /// is missing or costs money, the player is not new, or already got it.
  ClaimResult? grantStarterKit(KitRecipient who, {required bool isNewPlayer}) {
    if (!config.giveStarterKit || !isNewPlayer) return null;
    final kit = this.kit(config.starterKit);
    if (kit == null || kit.price > 0) return null;
    if (hasClaimed(who.uuid, kit.name)) return null;
    return claim(who, kit.name);
  }

  // -- Admin ------------------------------------------------------------------

  /// Saves [items] as the kit [name], replacing a kit with that name.
  /// Everything else about a replaced kit (cooldown, price, ...) is kept.
  /// Returns whether a kit was replaced.
  bool createKit(String name, List<KitItem> items) {
    final lower = name.toLowerCase();
    final candidate = Kit(name: lower, items: items);
    final report = validateKits(
      KitCatalog(kits: [candidate]),
      isKnownItem: isKnownItem,
      isKnownEnchantment: isKnownEnchantment,
    );
    if (report.kits.isEmpty) {
      throw KitException(
        report.problems.isEmpty
            ? 'That kit is not valid.'
            : report.problems.first,
      );
    }
    final kits = [..._catalogDoc.value.kits];
    final index = kits.indexWhere((k) => k.name == lower);
    if (index >= 0) {
      kits[index] = kits[index].copyWith(items: items);
    } else {
      kits.add(candidate);
    }
    _catalogDoc.value = KitCatalog(kits: kits);
    _commit();
    return index >= 0;
  }

  /// Deletes the kit [name]. The claim history is kept, so a kit that is
  /// created again does not give one-time kits a second time.
  void deleteKit(String name) {
    final lower = name.toLowerCase();
    final kits = [..._catalogDoc.value.kits];
    final before = kits.length;
    kits.removeWhere((k) => k.name == lower);
    if (kits.length == before) {
      throw KitException('There is no kit called $name.');
    }
    _catalogDoc.value = KitCatalog(kits: kits);
    _commit();
  }

  /// Re-reads the kits and the config from [backend]. A file that can not be
  /// parsed is reported and the old kits stay.
  KitReload reload(StorageBackend backend) {
    try {
      final kitsText = backend.read(kitsPath);
      final configText = backend.read(configPath);
      final catalog = kitsText == null
          ? _catalogDoc.value
          : KitCatalogMapper.fromJson(kitsText);
      final config = configText == null
          ? _configDoc.value
          : KitsConfigMapper.fromJson(configText);
      _catalogDoc.value = catalog;
      _configDoc.value = config;
    } on MapperException catch (e) {
      return KitReload.failed('A kits file is not valid JSON: $e');
    } on FormatException catch (e) {
      return KitReload.failed('A kits file is not valid JSON: $e');
    }
    _rebuild();
    return KitReload.ok(_kits.length, _problems);
  }

  void _commit() {
    _rebuild();
    _catalogDoc.save();
  }
}
