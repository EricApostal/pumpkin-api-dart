import 'bindings.g.dart';

/// Formatting for [ServerListPingAddress].
extension ServerListPingAddressExt on ServerListPingAddress {
  /// `host:port`, with IPv6 hosts in brackets (`[::1]:25565`).
  String get asString => host.contains(':') ? '[$host]:$port' : '$host:$port';
}
