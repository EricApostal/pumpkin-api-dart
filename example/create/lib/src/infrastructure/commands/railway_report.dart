// The text of `/create trains` (`DumpRailwaysCommand.fillReport`) as data (pure).
import '../../api/infra_data.dart';
import 'command_parsing.dart';

const int white = 0xFFFFFF;
const int blue = 0xaac8e0;
const int darkBlue = 0x88a5b7;
const int darkerBlue = 0x6b8694;
const int darkestBlue = 0x536b75;
const int bright = 0xFFEFEF;
const int orange = 0xFFAD60;

/// One line of the report.
sealed class ReportLine {
  const ReportLine();
}

/// A colored text line.
final class TextLine extends ReportLine {
  final String text;
  final int color;

  const TextLine(this.text, this.color);

  @override
  String toString() => text;
}

/// The `[Teleport]` button of a train.
final class TeleportButton extends ReportLine {
  final String trainId;
  final String trainName;

  const TeleportButton(this.trainId, this.trainName);

  String get command => '/c train tp $trainId';
}

/// The `[Remove]` button of a train.
final class DeleteButton extends ReportLine {
  final String trainId;
  final String trainName;

  const DeleteButton(this.trainId, this.trainName);

  String get command => '/c train remove $trainId';
}

/// The report for [summary] (what `fillReport` sends to the chat).
List<ReportLine> railwayReport(RailwaySummary summary) {
  final out = <ReportLine>[];
  void chat(String s, int color) => out.add(TextLine(s, color));

  chat('', white);
  chat('-+------<< Train Summary: >>------+-', white);
  chat('Track Networks: ${summary.graphCount}', blue);
  chat('Signal Groups: ${summary.signalGroupCount}', blue);
  chat('Trains: ${summary.trainCount}', blue);
  chat('', white);

  if (summary.graphCount > 0) {
    chat('Nearest Graphs: ', orange);
    chat('', white);
    for (final graph in summary.nearestGraphs) {
      chat('${shortId(graph.id)} with ${graph.nodeCount} Nodes', white);
      if (graph.signalCount > 0) chat(' -> ${graph.signalCount} Signals', blue);
      if (graph.stationCount > 0) chat(' -> ${graph.stationCount} Stations', blue);
    }
    chat('', white);
    if (summary.graphCount > 5) {
      chat('[...]', white);
      chat('', white);
    }
  }

  if (summary.trainCount > 0 && summary.nearestTrains.isNotEmpty) {
    chat('Nearest Trains: ', orange);
    chat('', white);
    for (final train in summary.nearestTrains) {
      chat('┬${shortId(train.id)}: ${train.name}, ${train.carriageCount} Wagons', bright);
      if (train.derailed) {
        chat('├─Derailed', orange);
      } else if (train.graphId != null) {
        chat('├─On Track: ${shortId(train.graphId!)}', blue);
      }
      if (train.ownerName != null) chat('├─Owned by ${train.ownerName}', blue);
      if (train.currentStationName != null) {
        chat('├─Waiting at: ${train.currentStationName}', blue);
      } else if (train.destinationName != null) {
        chat('├─Travelling to ${train.destinationName} (${train.distanceToDestination.floor()}m away)', darkBlue);
      }
      if (train.hasSchedule) {
        chat(
          '├─Schedule, Entry ${train.scheduleEntry}, '
          '${train.schedulePaused ? 'Paused' : train.scheduleState.replaceAll('_', ' ')}',
          train.schedulePaused ? darkBlue : blue,
        );
      } else {
        chat('├─Idle, No Schedule', darkBlue);
      }
      if (train.presence.length > 1) chat('├─Travelling between Dimensions:', darkerBlue);
      for (final p in train.presence) {
        chat('├─In ${p.dimension} near [${shortPos(p.position)}]', darkerBlue);
      }
      out.add(TeleportButton(train.id, train.name));
      out.add(DeleteButton(train.id, train.name));
      chat('', white);
    }
    if (summary.trainCount > 5) {
      chat('[...]', white);
      chat('', white);
    }
  }
  chat('-+--------------------------------+-', white);
  return out;
}
