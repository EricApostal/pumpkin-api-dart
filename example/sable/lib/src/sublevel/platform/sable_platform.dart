// The loader abstraction of Sable, collapsed into plain Dart.
//
// The Java mod has `SablePlatform`, `SableChunkEventPlatform`,
// `SablePlotPlatform`, `SableEventPlatform`, ... each with a NeoForge and a
// Fabric implementation loaded through `ServiceLoader`. A Pumpkin plugin has
// exactly one loader, so the abstraction is unnecessary: these are ordinary
// interfaces with one implementation (the plugin) and explicit HOST GAP notes
// for the hooks the host cannot provide yet.
//
// Pure: no host imports.
import '../host/sub_level_host.dart';

/// The platform hooks Sable calls into the loader for.
///
/// In Java every hook is a service loaded per loader. Here the plugin installs
/// one implementation on [SablePlatform.instance] at load time.
abstract interface class SablePlatform {
  /// The installed platform, or `null` when the plugin has not installed one.
  static SablePlatform? instance;

  /// `SableAssemblyPlatform.setIgnoreOnPlace`: suppresses the "block placed"
  /// hook while a contraption is being placed.
  ///
  /// HOST GAP: the Pumpkin API has no place-hook suppression flag.
  void setIgnoreOnPlace(SableLevel level, bool ignore);

  /// `SableChunkEventPlatform.onPlotChunkLoaded`: fired when a plot chunk is
  /// created or loaded.
  void onPlotChunkLoaded(PlotChunk chunk);

  /// `SableChunkEventPlatform.onOldChunkInvalid`.
  void onOldChunkInvalid(PlotChunk chunk);

  /// `SableChunkEventPlatform.onClientChunkPacketReplaced` (client only; a
  /// server plugin never calls it).
  void onClientChunkPacketReplaced(PlotChunk chunk);

  /// `SablePlotPlatform.writeLightData`: adds the loader-specific light data to
  /// a saved chunk.
  ///
  /// HOST GAP: Pumpkin has no chunk light data to write.
  void writeLightData(Map<String, Object?> chunkTag, PlotChunk chunk);

  /// `SablePlotPlatform.readLightData`.
  ///
  /// HOST GAP: the inverse of [writeLightData].
  void readLightData(Map<String, Object?> chunkTag, PlotChunk chunk);

  /// `SablePlotPlatform.writeChunkAttachments` (NeoForge attachment data).
  ///
  /// HOST GAP: Pumpkin has no data attachments on chunks.
  void writeChunkAttachments(Map<String, Object?> chunkTag, PlotChunk chunk);

  /// `SablePlotPlatform.readChunkAttachments`.
  ///
  /// HOST GAP: the inverse of [writeChunkAttachments].
  void readChunkAttachments(Map<String, Object?> chunkTag, PlotChunk chunk);

  /// `SablePlotPlatform.postLoad`.
  void postLoad(Map<String, Object?> chunkTag, PlotChunk chunk);

  /// `SableEventPlatform.onSubLevelContainerReady`: the container of a level is
  /// ready to use.
  void onSubLevelContainerReady(SableLevel level);

  /// `SableEventPlatform.onPhysicsTick`.
  void onPhysicsTick(SableLevel level, double timeStep);

  /// `SableEventPlatform.onPostPhysicsTick`.
  void onPostPhysicsTick(SableLevel level, double timeStep);
}

/// A platform that does nothing, for tests and for a host without the hooks.
final class NoopSablePlatform implements SablePlatform {
  const NoopSablePlatform();

  @override
  void setIgnoreOnPlace(SableLevel level, bool ignore) {}

  @override
  void onPlotChunkLoaded(PlotChunk chunk) {}

  @override
  void onOldChunkInvalid(PlotChunk chunk) {}

  @override
  void onClientChunkPacketReplaced(PlotChunk chunk) {}

  @override
  void writeLightData(Map<String, Object?> chunkTag, PlotChunk chunk) {}

  @override
  void readLightData(Map<String, Object?> chunkTag, PlotChunk chunk) {}

  @override
  void writeChunkAttachments(Map<String, Object?> chunkTag, PlotChunk chunk) {}

  @override
  void readChunkAttachments(Map<String, Object?> chunkTag, PlotChunk chunk) {}

  @override
  void postLoad(Map<String, Object?> chunkTag, PlotChunk chunk) {}

  @override
  void onSubLevelContainerReady(SableLevel level) {}

  @override
  void onPhysicsTick(SableLevel level, double timeStep) {}

  @override
  void onPostPhysicsTick(SableLevel level, double timeStep) {}
}

/// The plot platform hooks the plot calls, when one is installed.
SablePlatform get sablePlatform => SablePlatform.instance ?? const NoopSablePlatform();
