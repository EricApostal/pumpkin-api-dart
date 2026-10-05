// Reassembles a file upload from its messages and checks its SHA-256.
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'messages.dart';

/// A finished, verified upload: names and contents.
final class UploadedFile {
  final String name;
  final Uint8List bytes;

  const UploadedFile(this.name, this.bytes);
}

/// The server side of one upload (`ServerInputState.startUpload` and
/// friends): the first message announces the files, slices fill them in, the
/// last one finishes.
final class UploadAssembler {
  String? _uploadId;
  List<UploadFileHeader>? _headers;
  List<Uint8List>? _buffers;

  /// Feeds one message. Returns the files when the message completes the
  /// upload and every checksum matches, throws [StateError] if it does not,
  /// and returns null otherwise.
  List<UploadedFile>? accept(UploadFileMessage message) {
    if (message.isFirst) {
      final headers = message.files!;
      _uploadId = message.uploadId;
      _headers = headers;
      _buffers = [for (final header in headers) Uint8List(header.size)];
    }
    final buffers = _buffers;
    final headers = _headers;
    if (buffers == null || headers == null || _uploadId != message.uploadId) {
      throw StateError('Invalid continueUpload call');
    }
    for (final slice in message.slices) {
      if (slice.fileId >= buffers.length) continue;
      final buffer = buffers[slice.fileId];
      if (slice.offset < 0 || slice.offset + slice.bytes.length > buffer.length) {
        continue;
      }
      buffer.setRange(slice.offset, slice.offset + slice.bytes.length, slice.bytes);
    }
    if (!message.isLast) return null;
    final files = <UploadedFile>[];
    for (var i = 0; i < buffers.length; i++) {
      final digest = sha256.convert(buffers[i]).bytes;
      if (!_equal(digest, headers[i].checksum)) {
        _reset();
        throw StateError('Checksum of ${headers[i].name} does not match');
      }
      files.add(UploadedFile(headers[i].name, buffers[i]));
    }
    _reset();
    return files;
  }

  void _reset() {
    _uploadId = null;
    _headers = null;
    _buffers = null;
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
