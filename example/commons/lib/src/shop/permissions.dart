import '../core/permissions.dart';

/// The shop's permission nodes.
abstract final class ShopPerms {
  static const use = PermNode(
    'commons:shop.use',
    'Open the shop menu and look up prices (/shop, /worth)',
  );
  static const buy = PermNode('commons:shop.buy', 'Buy from the shop');
  static const sell = PermNode('commons:shop.sell', 'Sell to the shop');
  static const admin = PermNode(
    'commons:shop.admin',
    'Reload and edit the shop (/shopadmin)',
    PermDefault.op,
  );

  static const all = [use, buy, sell, admin];
}
