// `ServerSpeedProvider.serverTick` (pure): every `tickrateSyncTimer` ticks the clients get a
// `create:server_speed` packet; they measure how many of their own ticks passed between two of
// them to derive the server's tick rate.

/// Counts server ticks and says when to send the next sync packet.
final class ServerSpeedSync {
  int _serverTimer = 0;

  /// Called once per server tick with the configured interval; returns true when the packet is due.
  bool tick(int syncInterval) {
    _serverTimer++;
    if (_serverTimer > syncInterval) {
      _serverTimer = 0;
      return true;
    }
    return false;
  }

  void reset() => _serverTimer = 0;
}
