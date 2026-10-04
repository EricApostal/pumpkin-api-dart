import 'announcements/announcements_module.dart';
import 'chat/chat_module.dart';
import 'core/module.dart';
import 'economy/economy_module.dart';
import 'kits/kits_module.dart';
import 'mail/mail_module.dart';
import 'moderation/moderation_module.dart';
import 'rewards/rewards_module.dart';
import 'shop/shop_module.dart';

/// Every module of the plugin. Order doesn't matter, `dependsOn` decides the
/// load order. Remove a line to leave a module out.
List<Module> allModules() => [
  EconomyModule(),
  RewardsModule(),
  ShopModule(),
  KitsModule(),
  MailModule(),
  ChatModule(),
  AnnouncementsModule(),
  ModerationModule(),
];
