// The Lua surface of the peripherals this package implements, run by a real
// Lua VM through the same `peripheral` table a computer installs
// (`buildPeripheralApi`, exactly what `Computer._createMachine` puts in the
// globals). Every test here calls the methods a Lua program calls, with the
// names and the error messages of the Java peripheral of the same name, so a
// program that works against CC: Tweaked works against this server.
//
// The computer itself is not constructible here (`machine/computer.dart`
// reaches `dart:_wasm` through the native Lua machine, and `CcService` needs the
// host's data folder), so [_Computer] is the same shape of the two things the
// table asks for: `PeripheralLookup.attached(side)` and the `PeripheralAccess`
// a computer hands a peripheral (including the disk-drive mounts of
// `_SideAccess`).
//
// What is therefore *not* proven here: the host side of the peripheral blocks
// (`plugin/world_peripherals.dart`, `plugin/world_monitors.dart`) and the
// payloads they send. Those need a live server and client.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cc_tweaked/src/lua/lua.dart' show LuaError, LuaVm, installStandardLibrary;
import 'package:cc_tweaked/src/machine/api/peripheral_api.dart';
import 'package:cc_tweaked/src/machine/filesystem.dart';
import 'package:cc_tweaked/src/machine/media.dart';
import 'package:cc_tweaked/src/machine/peripheral.dart';
import 'package:cc_tweaked/src/machine/peripherals.dart';
import 'package:cc_tweaked/src/machine/side.dart';
import 'package:test/test.dart';

void main() {
  late _Computer computer;
  late LuaVm vm;

  setUp(() {
    computer = _Computer();
    vm = LuaVm();
    installStandardLibrary(vm);
    vm.globals.setString('peripheral', buildPeripheralApi(computer));
  });

  /// A call as a Lua program makes it.
  List<Object?> call(String source) => vm.call(vm.load(source, '=prog'), const []);

  /// One `peripheral.call` result list.
  List<Object?> callMethod(String side, String method, [String args = '']) =>
      call('return peripheral.call("$side", "$method"${args.isEmpty ? '' : ', $args'})');

  group('a disk drive', () {
    late _Drive drive;

    setUp(() {
      drive = _Drive();
      computer.attach(ComputerSide.left, DiskDrivePeripheral(drive));
    });

    test('the type and the methods are the ones of Drive', () {
      expect(call("return peripheral.getType('left')"), ['drive']);
      expect(
        call('''
          local methods = peripheral.getMethods("left")
          table.sort(methods)
          return table.concat(methods, ",")
        '''),
        [
          'ejectDisk,getAudioTitle,getDiskID,getDiskLabel,getMountPath,hasAudio,hasData,'
              'isDiskPresent,setDiskLabel',
        ],
      );
    });

    test('an empty drive reports no disk, and mounting is a no-op', () {
      expect(callMethod('left', 'isDiskPresent'), [false]);
      expect(callMethod('left', 'getDiskLabel'), [null]);
      expect(callMethod('left', 'hasData'), [false]);
      expect(callMethod('left', 'getMountPath'), [null]);
      expect(callMethod('left', 'getDiskID'), [null]);
      expect(callMethod('left', 'hasAudio'), [false]);
      expect(callMethod('left', 'getAudioTitle'), [false]);
    });

    test('a data disk gives the drive a disk, a mount and a label', () {
      drive.media = DataDisk(_MemoryMount({'hello.txt': 'hi'}), 7, 'My disk');
      (computer.peripheralOn(ComputerSide.left)! as DiskDrivePeripheral).mediaChanged();

      expect(callMethod('left', 'isDiskPresent'), [true]);
      expect(callMethod('left', 'getDiskLabel'), ['My disk']);
      expect(callMethod('left', 'getDiskID'), [7.0]);
      expect(callMethod('left', 'hasData'), [true]);
      expect(callMethod('left', 'getMountPath'), ['disk']);
      // The mount went to the computer's file system, as Java's
      // `IComputerAccess.mountWritable` does.
      expect(computer.mounts, {'disk': _MemoryMount});
    });

    test('setDiskLabel writes through and clears with nil', () {
      drive.media = DataDisk(_MemoryMount({}), 1, 'Old');
      expect(callMethod('left', 'setDiskLabel', '"New"'), isEmpty);
      expect(drive.media!.label, 'New');
      expect(callMethod('left', 'setDiskLabel'), isEmpty);
      expect(drive.media!.label, isNull);
    });

    test('a label is normalised like StringUtil.normaliseLabel', () {
      drive.media = DataDisk(_MemoryMount({}), 1);
      expect(callMethod('left', 'setDiskLabel', '"${'x' * 40}"'), isEmpty);
      expect(drive.media!.label, 'x' * 32);
      expect(callMethod('left', 'setDiskLabel', '"a\\tb"'), isEmpty);
      expect(drive.media!.label, 'a?b');
    });

    test('a treasure disk refuses a new label, like Java', () {
      drive.media = TreasureDisk(_MemoryMount({}), 'Welcome');
      expect(callMethod('left', 'getDiskLabel'), ['Welcome']);
      expect(
        () => callMethod('left', 'setDiskLabel', '"nope"'),
        throwsA(isA<LuaError>().having((e) => '${e.value}', 'message', contains('Disk label cannot be changed'))),
      );
    });

    test('a record has audio but no title and no mount', () {
      drive.media = RecordDisk();
      expect(callMethod('left', 'hasAudio'), [true]);
      expect(callMethod('left', 'getAudioTitle'), [null]);
      expect(callMethod('left', 'hasData'), [false]);
      expect(callMethod('left', 'getDiskLabel'), [null]);
    });

    test('ejecting reaches the drive and unmounts the disk', () {
      drive.media = DataDisk(_MemoryMount({}), 3, 'Bye');
      (computer.peripheralOn(ComputerSide.left)! as DiskDrivePeripheral).mediaChanged();
      expect(callMethod('left', 'ejectDisk'), isEmpty);
      expect(drive.ejects, 1);
      drive.media = null;
      (computer.peripheralOn(ComputerSide.left)! as DiskDrivePeripheral).mediaChanged();
      expect(callMethod('left', 'getMountPath'), [null]);
      expect(computer.unmounts, ['disk']);
    });

    test('the methods Java does not back here are absent, not silent', () {
      // `playAudio`/`stopAudio` need the record's jukebox song from a datapack
      // registry the host does not expose; a program that calls them fails
      // loudly instead of appearing to work.
      expect(
        () => callMethod('left', 'playAudio'),
        throwsA(isA<LuaError>().having((e) => '${e.value}', 'message', contains('No such method playAudio'))),
      );
    });
  });

  group('a printer', () {
    late _Printer printer;
    late PrinterPeripheral peripheral;

    setUp(() {
      printer = _Printer();
      peripheral = PrinterPeripheral(onPage: printer.pages.add);
      computer.attach(ComputerSide.top, peripheral);
    });

    test('the page size and the supplies are visible', () {
      expect(call("return peripheral.getType('top')"), ['printer']);
      expect(callMethod('top', 'getPageSize'), [25.0, 21.0]);
      peripheral.setSupplies(ink: 3, paper: 2, inkColour: 14);
      expect(callMethod('top', 'getInkLevel'), [3.0]);
      expect(callMethod('top', 'getPaperLevel'), [2.0]);
    });

    test('writing to a page moves the cursor like the Java peripheral', () {
      peripheral.setSupplies(ink: 1, paper: 1, inkColour: 15);
      expect(callMethod('top', 'newPage'), [true]);
      expect(callMethod('top', 'getCursorPos'), [1.0, 1.0]);
      expect(callMethod('top', 'write', '"hello"'), isEmpty);
      expect(callMethod('top', 'getCursorPos'), [6.0, 1.0]);
      expect(callMethod('top', 'setCursorPos', '3, 2'), isEmpty);
      expect(callMethod('top', 'getCursorPos'), [3.0, 2.0]);
      expect(callMethod('top', 'getPageSize'), [25.0, 21.0]);
    });

    test('a page takes one ink and one paper and comes out of the printer', () {
      peripheral.setSupplies(ink: 2, paper: 2, inkColour: 15);
      expect(callMethod('top', 'newPage'), [true]);
      expect(callMethod('top', 'getInkLevel'), [1.0]);
      expect(callMethod('top', 'getPaperLevel'), [1.0]);
      callMethod('top', 'write', '"Hello"');
      expect(callMethod('top', 'setPageTitle', '"Greeting"'), isEmpty);
      expect(callMethod('top', 'endPage'), [true]);
      expect(printer.pages, hasLength(1));
      expect(printer.pages.single.title, 'Greeting');
      expect(printer.pages.single.lines, hasLength(21));
      expect(printer.pages.single.lines.first.$1.substring(0, 5), 'Hello');
    });

    test('without ink or paper a page cannot be started', () {
      peripheral.setSupplies(ink: 0, paper: 5, inkColour: 15);
      expect(callMethod('top', 'newPage'), [false]);
      peripheral.setSupplies(ink: 1, paper: 0, inkColour: 15);
      expect(callMethod('top', 'newPage'), [false]);
    });

    test('the page methods fail with "Page not started" when none is', () {
      expect(
        () => callMethod('top', 'write', '"x"'),
        throwsA(isA<LuaError>().having((e) => '${e.value}', 'message', contains('Page not started'))),
      );
      expect(
        () => callMethod('top', 'getCursorPos'),
        throwsA(isA<LuaError>().having((e) => '${e.value}', 'message', contains('Page not started'))),
      );
      // `endPage` checks the page first and only then whether one is printing
      // (Java: `getCurrentPage()` before `endCurrentPage()`).
      expect(
        () => callMethod('top', 'endPage'),
        throwsA(isA<LuaError>().having((e) => '${e.value}', 'message', contains('Page not started'))),
      );
      expect(
        () => callMethod('top', 'setPageTitle', '"x"'),
        throwsA(isA<LuaError>().having((e) => '${e.value}', 'message', contains('Page not started'))),
      );
    });
  });

  group('a speaker', () {
    late _Sink sink;
    late SpeakerPeripheral speaker;

    setUp(() {
      sink = _Sink();
      speaker = SpeakerPeripheral(sink: sink);
      computer.attach(ComputerSide.right, speaker);
    });

    test('the type and the four methods', () {
      expect(call("return peripheral.getType('right')"), ['speaker']);
      expect(
        call('''
          local methods = peripheral.getMethods("right")
          table.sort(methods)
          return table.concat(methods, ",")
        '''),
        ['playAudio,playNote,playSound,stop'],
      );
    });

    test('playNote plays an instrument at the pitch Java computes', () {
      expect(callMethod('right', 'playNote', '"harp"'), [true]);
      speaker.update(1000);
      expect(sink.played, hasLength(1));
      expect(sink.played.single.id, 'minecraft:block.note_block.harp');
      expect(sink.played.single.volume, 1.0);
      // Java's default pitch argument is 1.0 (not 12), so the sound multiplier
      // is `2^((1 - 12) / 12)` (`SpeakerPeripheral.java:215`).
      expect(sink.played.single.pitch, closeTo(math.pow(2, (1 - 12) / 12).toDouble(), 1e-9));
    });

    test('playNote takes the volume and the pitch in semitones', () {
      expect(callMethod('right', 'playNote', '"bell", 0.5, 24'), [true]);
      speaker.update(1000);
      expect(sink.played.single.volume, 0.5);
      expect(sink.played.single.pitch, closeTo(2.0, 1e-9));
    });

    test('an unknown instrument fails with the Java message', () {
      expect(
        () => callMethod('right', 'playNote', '"theremin"'),
        throwsA(
          isA<LuaError>().having((e) => '${e.value}', 'message', contains('Invalid instrument, "theremin"!')),
        ),
      );
    });

    test('at most eight notes a tick, then false', () {
      for (var i = 0; i < 8; i++) {
        expect(callMethod('right', 'playNote', '"harp"'), [true]);
      }
      expect(callMethod('right', 'playNote', '"harp"'), [false]);
      speaker.update(1000);
      expect(sink.played, hasLength(8));
      expect(callMethod('right', 'playNote', '"harp"'), [true]);
    });

    test('the volume is clamped to 0..3, like clampVolume', () {
      expect(callMethod('right', 'playNote', '"harp", 9'), [true]);
      speaker.update(1000);
      expect(sink.played.single.volume, 3.0);
    });

    test('playSound refuses a malformed name and a too long one', () {
      expect(
        () => callMethod('right', 'playSound', '"Not A Sound"'),
        throwsA(
          isA<LuaError>().having((e) => '${e.value}', 'message', contains('bad argument #1 (malformed sound name)')),
        ),
      );
      expect(
        () => callMethod('right', 'playSound', '"minecraft:${'a' * 520}"'),
        throwsA(
          isA<LuaError>().having((e) => '${e.value}', 'message', contains('bad argument #1 (sound name is too long)')),
        ),
      );
    });

    test('a sound plays once and blocks a second one until it is sent', () {
      expect(callMethod('right', 'playSound', '"entity.creeper.primed"'), [true]);
      expect(callMethod('right', 'playSound', '"entity.creeper.primed"'), [false]);
      speaker.update(1000);
      expect(sink.played.single.id, 'minecraft:entity.creeper.primed');
      expect(callMethod('right', 'playSound', '"entity.creeper.primed"'), [true]);
    });

    test('playAudio encodes DFPWM and asks for more when the buffer frees', () {
      // 8 samples make one byte; the samples ramp so the encoder has work.
      expect(callMethod('right', 'playAudio', '{0, 16, 32, 48, 64, 80, 96, 112}'), [true]);
      // A second call before the first is sent is refused (pendingAudio).
      expect(callMethod('right', 'playAudio', '{0, 0, 0, 0, 0, 0, 0, 0}'), [false]);

      speaker.update(0);
      expect(sink.audio, hasLength(1));
      expect(sink.audio.single.audio, hasLength(1));
      // The chunk carries the codec state before it, as the payload does.
      expect(sink.audio.single.charge, 0);
      expect(sink.audio.single.strength, 0);
      // And the computers are told the buffer is free.
      expect(computer.events.where((e) => e.$1 == 'speaker_audio_empty'), hasLength(1));
      expect(computer.events.single.$2, ['right']);
    });

    test('empty and oversized audio fail with the Java messages', () {
      expect(
        () => callMethod('right', 'playAudio', '{}'),
        throwsA(isA<LuaError>().having((e) => '${e.value}', 'message', contains('Cannot play empty audio'))),
      );
      expect(
        () => callMethod('right', 'playAudio', '{${'0,' * (128 * 1024 + 1)}0}'),
        throwsA(isA<LuaError>().having((e) => '${e.value}', 'message', contains('Audio data is too large'))),
      );
    });

    test('a sample out of range names the item, like Java', () {
      expect(
        () => callMethod('right', 'playAudio', '{0, 0, 0, 0, 0, 0, 0, 200}'),
        throwsA(
          isA<LuaError>().having((e) => '${e.value}', 'message', contains('table item #8 must be between -128 and 127')),
        ),
      );
    });

    test('stop stops the sound that was playing', () {
      expect(callMethod('right', 'playSound', '"entity.creeper.primed"'), [true]);
      speaker.update(0);
      expect(sink.played, hasLength(1));
      expect(callMethod('right', 'stop'), isEmpty);
      speaker.update(1000);
      expect(sink.stops, 1);
    });
  });

  group('a wired modem', () {
    late WiredNetwork network;
    late WiredModem modem;
    late _Sink sink;
    late SpeakerPeripheral speaker;

    setUp(() {
      network = WiredNetwork();
      modem = WiredModem(network: network);
      sink = _Sink();
      speaker = SpeakerPeripheral(sink: sink);
      modem.element = WiredElement('speaker_1', speaker);
      computer.attach(ComputerSide.back, modem);
      // Another computer's modem on the same network, with a computer
      // peripheral of its own.
      final other = WiredModem(network: network);
      other.element = WiredElement('computer_9', ComputerPeripheral('computer', _Controller(9)));
      other.attach(_Access(_Computer(), ComputerSide.left, 9));
      modem.networkChanged();
    });

    test('it is a modem with the peripheral_hub type and no wireless', () {
      expect(call("return peripheral.getType('back')"), ['modem', 'peripheral_hub']);
      expect(call("return peripheral.hasType('back', 'peripheral_hub')"), [true]);
      expect(callMethod('back', 'isWireless'), [false]);
    });

    test('the remote names and the remote meta calls', () {
      expect(call('''
        local names = peripheral.call("back", "getNamesRemote")
        table.sort(names)
        return table.concat(names, ",")
      '''), ['computer_9']);
      expect(callMethod('back', 'isPresentRemote', '"computer_9"'), [true]);
      expect(callMethod('back', 'isPresentRemote', '"computer_1"'), [false]);
      expect(callMethod('back', 'getTypeRemote', '"computer_9"'), ['computer']);
      expect(callMethod('back', 'hasTypeRemote', '"computer_9", "computer"'), [true]);
      expect(callMethod('back', 'getTypeRemote', '"nope"'), [null]);
      expect(callMethod('back', 'hasTypeRemote', '"nope", "computer"'), [null]);
      expect(callMethod('back', 'getMethodsRemote', '"nope"'), [null]);
    });

    test('getMethodsRemote lists the remote methods and callRemote runs one', () {
      expect(call('''
        local methods = peripheral.call("back", "getMethodsRemote", "computer_9")
        table.sort(methods)
        return table.concat(methods, ",")
      '''), ['getID,getLabel,isOn,reboot,shutdown,turnOn']);
      expect(callMethod('back', 'callRemote', '"computer_9", "getID"'), [9.0]);
      expect(callMethod('back', 'callRemote', '"computer_9", "getLabel"'), ['#9']);
    });

    test('calling a peripheral that is not there is a Lua error', () {
      expect(
        () => callMethod('back', 'callRemote', '"nope", "getID"'),
        throwsA(isA<LuaError>().having((e) => e.value, 'message', contains('No peripheral: nope'))),
      );
    });

    test('the computer gets peripheral events when the network changes', () {
      final events = computer.events.length;
      final other = WiredModem(network: network);
      other.element = WiredElement('monitor_2', MonitorPeripheral(2, 2, advanced: true));
      final otherAccess = _Access(_Computer(), ComputerSide.left, 10);
      other.attach(otherAccess);
      modem.networkChanged();
      final added = computer.events.sublist(events).where((e) => e.$1 == 'peripheral').toList();
      expect(added, isNotEmpty);
      expect(added.single.$2, ['monitor_2']);

      // And the same name going away queues `peripheral_detach`.
      other.detach(otherAccess);
      modem.networkChanged();
      expect(computer.events.last.$1, 'peripheral_detach');
      expect(computer.events.last.$2, ['monitor_2']);
    });

    test('a wired message reaches the computers of the network', () {
      final target = _Computer();
      final other = WiredModem(network: network);
      final otherAccess = _Access(target, ComputerSide.left, 11);
      other.attach(otherAccess);
      other.call(otherAccess, 'open', const [5.0]);

      expect(callMethod('back', 'open', '5'), isEmpty);
      expect(callMethod('back', 'isOpen', '5'), [true]);
      expect(callMethod('back', 'transmit', '5, 6, "hi"'), isEmpty);
      // The target computer also got the `peripheral` events of the remotes it
      // can now wrap; the message is the last event, at distance 0.
      final messages = target.events.where((e) => e.$1 == 'modem_message').toList();
      expect(messages, hasLength(1));
      expect(messages.single.$2[1], 5.0);
      expect(messages.single.$2[2], 6.0);
      expect(messages.single.$2[3], 'hi');
      expect(messages.single.$2[4], 0.0);
      expect(callMethod('back', 'closeAll'), isEmpty);
      expect(callMethod('back', 'isOpen', '5'), [false]);
    });
  });

  group('a computer as a peripheral', () {
    late _Controller controller;
    late ComputerPeripheral peripheral;

    setUp(() {
      controller = _Controller(3);
      peripheral = ComputerPeripheral('computer', controller);
      computer.attach(ComputerSide.front, peripheral);
    });

    test('the surface is the one of ComputerPeripheral', () {
      expect(call("return peripheral.getType('front')"), ['computer']);
      expect(callMethod('front', 'getID'), [3.0]);
      expect(callMethod('front', 'isOn'), [false]);
      expect(callMethod('front', 'getLabel'), ['#3']);
    });

    test('the power methods reach the other computer', () {
      expect(callMethod('front', 'turnOn'), isEmpty);
      expect(controller.calls, ['turnOn']);
      expect(callMethod('front', 'isOn'), [true]);
      expect(callMethod('front', 'shutdown'), isEmpty);
      expect(callMethod('front', 'reboot'), isEmpty);
      expect(controller.calls, ['turnOn', 'shutdown', 'reboot']);
    });

    test('a label the other computer has', () {
      controller.label = 'the one';
      expect(callMethod('front', 'getLabel'), ['the one']);
    });
  });

  group('a redstone relay', () {
    late RedstoneRelayPeripheral relay;

    setUp(() {
      relay = RedstoneRelayPeripheral();
      computer.attach(ComputerSide.left, relay);
    });

    test('the surface is RedstoneMethods, with the same errors', () {
      expect(call("return peripheral.getType('left')"), ['redstone_relay']);
      expect(callMethod('left', 'setOutput', '"top", true'), isEmpty);
      expect(callMethod('left', 'getOutput', '"top"'), [true]);
      expect(callMethod('left', 'getAnalogOutput', '"top"'), [15.0]);
      expect(callMethod('left', 'setAnalogOutput', '"bottom", 7'), isEmpty);
      expect(callMethod('left', 'getAnalogOutput', '"bottom"'), [7.0]);
      expect(callMethod('left', 'getInput', '"top"'), [false]);
      expect(
        () => callMethod('left', 'setAnalogOutput', '"top", 99'),
        throwsA(isA<LuaError>().having((e) => '${e.value}', 'message', contains('Expected number in range 0-15'))),
      );
      expect(
        () => callMethod('left', 'getOutput', '"sideways"'),
        throwsA(isA<LuaError>().having((e) => '${e.value}', 'message', contains("unknown option 'sideways'"))),
      );
    });

    test('the world feeds the inputs in and the relay raises the event', () {
      relay.redstone.setInput(ComputerSide.top, 12, 0);
      expect(callMethod('left', 'getAnalogInput', '"top"'), [12.0]);
      expect(callMethod('left', 'getInput', '"top"'), [true]);
      relay.redstoneChanged();
      expect(computer.events.last.$1, 'redstone');
      expect(computer.events.last.$2, isEmpty);
    });

    test('the bundled methods are state, as they are for a computer', () {
      expect(callMethod('left', 'setBundledOutput', '"top", 0xFFFF'), isEmpty);
      expect(callMethod('left', 'getBundledOutput', '"top"'), [65535.0]);
      expect(callMethod('left', 'testBundledInput', '"top", 1'), [false]);
    });
  });

  group('the disk mounts of a computer', () {
    test('a mount appears at disk, is readable and goes away on unmount', () {
      final fs = FileSystem();
      fs.mount('hdd', '', _MemoryMount({'boot.txt': 'hello'}));
      fs.mount('disk', 'disk', _MemoryMount({'startup.lua': 'print(1)'}));

      expect(fs.exists('disk/startup.lua'), isTrue);
      expect(fs.list(''), contains('disk'));
      expect(String.fromCharCodes(fs.openRead('disk/startup.lua').readAll()), 'print(1)');
      expect(fs.mountLabel('disk/startup.lua'), 'disk');

      // An open file on the mount is closed by the unmount, and the paths
      // under it stop resolving.
      final open = fs.openRead('disk/startup.lua');
      expect(open.isClosed, isFalse);
      fs.unmount('disk');
      expect(open.isClosed, isTrue);
      expect(fs.exists('disk/startup.lua'), isFalse);
      expect(fs.exists('boot.txt'), isTrue);
    });
  });

  group('the media model', () {
    test('a data disk label can be set, a treasure disk refuses', () {
      final disk = DataDisk(_MemoryMount({}), 4, 'label');
      expect(disk.diskId, 4);
      expect(disk.setLabel('other'), isTrue);
      expect(disk.label, 'other');
      expect(disk.createDataMount(), isA<_MemoryMount>());

      final treasure = TreasureDisk(_MemoryMount({}), 'Title');
      expect(treasure.label, 'Title');
      expect(treasure.setLabel('no'), isFalse);
      expect(treasure.hasAudio, isFalse);

      final record = RecordDisk();
      expect(record.hasAudio, isTrue);
      expect(record.audioTitle, isNull);
      expect(record.createDataMount(), isNull);
      expect(record.setLabel('no'), isFalse);
    });
  });
}

/// A read-only mount over [files]: the disk of a drive in these tests.
final class _MemoryMount implements Mount {
  final Map<String, String> files;

  _MemoryMount(this.files);

  @override
  bool exists(String path) => path.isEmpty || files.containsKey(path);

  @override
  bool isDirectory(String path) => path.isEmpty;

  @override
  List<String> list(String path) => path.isEmpty ? files.keys.toList() : const [];

  @override
  int size(String path) => files[path]?.length ?? 0;

  @override
  Uint8List read(String path) {
    final text = files[path];
    if (text == null) throw FileSystemException.of(path, noSuchFile);
    return Uint8List.fromList(text.codeUnits);
  }

  @override
  FileAttributes attributes(String path) =>
      FileAttributes(isDirectory: path.isEmpty, size: size(path), modified: DateTime(2026), created: DateTime(2026));
}

/// The drive a `DiskDrivePeripheral` drives in these tests.
final class _Drive implements DiskDrive {
  @override
  Media? media;
  int ejects = 0;

  @override
  void eject() => ejects++;
}

/// The pages a `PrinterPeripheral` produced.
final class _Printer {
  final List<Printout> pages = [];
}

/// What a speaker played, as the sink sees it.
final class _Sink implements SpeakerSink {
  final List<SpeakerSound> played = [];
  final List<SpeakerAudioChunk> audio = [];
  int stops = 0;
  int moves = 0;

  @override
  void play(SpeakerSound sound) => played.add(sound);

  @override
  void playAudio(SpeakerAudioChunk chunk) => audio.add(chunk);

  @override
  void stop() => stops++;

  @override
  void moved() => moves++;
}

/// The other computer of a `ComputerPeripheral`.
final class _Controller implements ComputerController {
  @override
  final int id;
  @override
  String? label;
  bool on = false;
  final List<String> calls = [];

  _Controller(this.id) : label = '#$id';

  @override
  bool get isOn => on;

  @override
  void turnOn() {
    on = true;
    calls.add('turnOn');
  }

  @override
  void shutdown() {
    on = false;
    calls.add('shutdown');
  }

  @override
  void reboot() => calls.add('reboot');
}

/// The two things the `peripheral` table asks of a computer:
/// `PeripheralLookup.attached(side)` and the access a peripheral is handed
/// (`Computer._SideAccess`, including the mounts a disk drive makes).
final class _Computer implements PeripheralLookup {
  final Map<ComputerSide, (Peripheral, PeripheralAccess)> _sides = {};
  final List<(String, List<Object?>)> events = [];
  final List<String> unmounts = [];

  /// The mounts the disk drives made, by path.
  final Map<String, Type> mounts = {};

  @override
  (Peripheral, PeripheralAccess)? attached(ComputerSide side) => _sides[side];

  Peripheral? peripheralOn(ComputerSide side) => _sides[side]?.$1;

  void attach(ComputerSide side, Peripheral peripheral) {
    final access = _Access(this, side, 0);
    _sides[side] = (peripheral, access);
    peripheral.attach(access);
  }

  void detach(ComputerSide side) {
    final existing = _sides.remove(side);
    existing?.$1.detach(existing.$2);
  }
}

/// `Computer._SideAccess`: what a peripheral sees of the computer it is on. The
/// mount methods are the ones of `_SideAccess.mountDisk`/`unmountDisk`.
final class _Access implements PeripheralAccess {
  final _Computer _computer;
  final ComputerSide _side;

  _Access(this._computer, this._side, this.computerId);

  @override
  final int computerId;

  @override
  String get attachmentName => _side.luaName;

  @override
  void queueEvent(String name, List<Object?> args) => _computer.events.add((name, args));

  @override
  String? mountDisk(Object mount) {
    // The real `_SideAccess` walks `disk`, `disk2`, ... on the computer's file
    // system; this records what it was given.
    _computer.mounts['disk'] = mount.runtimeType;
    return 'disk';
  }

  @override
  void unmountDisk(String path) => _computer.unmounts.add(path);
}