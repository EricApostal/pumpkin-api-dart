/// Permission names to request in [PluginInfo.permissions], granting a plugin
/// access to host features.
abstract final class Permissions {
  /// Perform DNS resolution.
  static const networkDns = 'network.dns';

  /// Use TCP sockets.
  static const networkTcp = 'network.tcp';

  /// Use UDP sockets.
  static const networkUdp = 'network.udp';

  /// Initiate TCP connections.
  static const networkTcpConnect = 'network.tcp.connect';

  /// Bind TCP listeners (accept inbound connections).
  static const networkTcpBind = 'network.tcp.bind';

  /// Send and receive UDP packets to specific destinations.
  static const networkUdpConnect = 'network.udp.connect';

  /// Bind UDP sockets to local ports.
  static const networkUdpBind = 'network.udp.bind';

  /// Send datagrams on non-connected UDP sockets.
  static const networkUdpOutgoingDatagram = 'network.udp.outgoingdatagram';

  /// Restricts all networking permissions to loopback addresses only.
  static const networkLoopback = 'network.loopback';

  /// Make outbound TCP/UDP connections. This is a powerful permission.
  static const networkOutbound = 'network.outbound';

  /// Make outbound HTTP connections (`wasi:http`).
  static const httpOutbound = 'http.outbound';

  /// Read files within the plugin's own data folder.
  static const fsReadData = 'fs.read.data';

  /// Write (and read) files within the plugin's own data folder.
  static const fsWriteData = 'fs.write.data';

  /// Read all environment variables.
  static const sysEnv = 'sys.env';

  /// Prefix for reading a specific environment variable, like `sys.env.PATH`.
  static const sysEnvPrefix = 'sys.env.';

  /// Read system information (CPU, memory, OS).
  static const sysInfo = 'sys.info';

  /// Read CPU information.
  static const sysInfoCpu = 'sys.info.cpu';

  /// Read RAM information.
  static const sysInfoRam = 'sys.info.ram';

  /// Read OS information.
  static const sysInfoOs = 'sys.info.os';

  /// Register custom items and item tags (`ItemRegistries.host`). Only
  /// possible while the server loads, before players can connect.
  static const registryItems = 'registry.items';

  /// Register custom blocks and block tags (`BlockRegistries.host`). Only
  /// possible while the server loads, before players can connect.
  static const registryBlocks = 'registry.blocks';

  /// Register block entity types (`BlockEntityRegistries.host`) and use the
  /// block entities of plugin blocks. Only possible while the server loads,
  /// before players can connect.
  static const registryBlockEntities = 'registry.block-entities';

  /// Register menu types (`MenuRegistries.host`) and open plugin menus. Only
  /// possible while the server loads, before players can connect.
  static const registryMenus = 'registry.menus';

  /// Register custom data component types (`ComponentTypeRegistries.host`).
  /// Only possible while the server loads, before players can connect.
  static const registryComponents = 'registry.components';
}
