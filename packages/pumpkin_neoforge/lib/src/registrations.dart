// The payload channels NeoForge itself registers (all optional, version "1"):
// what every NeoForge peer, client or server, puts in its `neoforge:register`
// query. Binding-free. Source: `NetworkInitialization` and
// `GenericPacketSplitter` (see docs/neoforge-protocol.md).
import 'payloads.dart';
import 'protocol.dart';

QueryComponent _c(String id, PacketFlow? flow) =>
    QueryComponent(id: id, version: '1', flow: flow, optional: true);

/// NeoForge's own payload registrations per protocol, as a NeoForge client
/// reports them in `neoforge:register`.
final Map<NetworkPhase, List<QueryComponent>> neoForgeOwnRegistrations = {
  NetworkPhase.configuration: [
    _c(NeoForgeChannels.configFile, PacketFlow.clientbound),
    _c(NeoForgeChannels.frozenRegistrySyncStart, PacketFlow.clientbound),
    _c(NeoForgeChannels.frozenRegistry, PacketFlow.clientbound),
    _c(NeoForgeChannels.frozenRegistrySyncCompleted, null),
    _c(NeoForgeChannels.knownRegistryDataMaps, PacketFlow.clientbound),
    _c(NeoForgeChannels.extensibleEnumData, PacketFlow.clientbound),
    _c(NeoForgeChannels.featureFlags, PacketFlow.clientbound),
    _c(NeoForgeChannels.knownRegistryDataMapsReply, PacketFlow.serverbound),
    _c(NeoForgeChannels.extensibleEnumAck, PacketFlow.serverbound),
    _c(NeoForgeChannels.featureFlagsAck, PacketFlow.serverbound),
    _c(NeoForgeChannels.split, null),
  ],
  NetworkPhase.play: [
    _c(NeoForgeChannels.configFile, PacketFlow.clientbound),
    _c('neoforge:advanced_add_entity', PacketFlow.clientbound),
    _c('neoforge:advanced_open_screen', PacketFlow.clientbound),
    _c('neoforge:auxiliary_light_data', PacketFlow.clientbound),
    _c('neoforge:registry_data_map_sync', PacketFlow.clientbound),
    _c('neoforge:advanced_container_set_data', PacketFlow.clientbound),
    _c('neoforge:recipe_content', PacketFlow.clientbound),
    _c('neoforge:sync_attachments', PacketFlow.clientbound),
    _c(NeoForgeChannels.split, null),
  ],
};
