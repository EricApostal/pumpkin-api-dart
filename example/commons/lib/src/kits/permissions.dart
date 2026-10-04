import '../core/permissions.dart';
import 'model.dart';

/// The kits module's permission nodes. Each kit also has its own node,
/// `commons:kits.kit.<name>` (see [kitNode]).
abstract final class KitPerms {
  static const use = PermNode(
    'commons:kits.use',
    'Use /kit: list, preview and claim kits',
  );
  static const bypass = PermNode(
    'commons:kits.bypass',
    'Claim kits ignoring cooldowns and the one-time limit',
    PermDefault.op,
  );
  static const admin = PermNode(
    'commons:kits.admin',
    'Create, delete and reload kits',
    PermDefault.op,
  );

  static const all = [use, bypass, admin];
}

/// The node that lets a player claim [kit]: everyone has it, unless the kit
/// is [Kit.restricted].
PermNode kitNode(Kit kit) => PermNode(
  kit.permission,
  'Claim the ${kit.name} kit',
  kit.restricted ? PermDefault.op : PermDefault.everyone,
);
