import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../models/gopher_item.dart';
import '../l10n/l10n.dart';

class GopherException implements Exception {
  final String message;
  GopherException(this.message);

  @override
  String toString() => 'GopherException: $message';
}

/// Owns a socket so navigation can cancel an obsolete request.
class GopherRequest {
  Socket? _socket;
  bool _cancelled = false;

  void attach(Socket socket) {
    if (_cancelled) {
      socket.destroy();
      throw GopherException(t.requestCancelled);
    }
    _socket = socket;
  }

  void cancel() {
    _cancelled = true;
    _socket?.destroy();
  }

  void check() {
    if (_cancelled) throw GopherException(t.requestCancelled);
  }
}

/// Direct TCP transport for native platforms.
class GopherClient {
  final Duration timeout;
  final int maxResponseBytes;

  /// How long a local question may stay silent. Its total time has no limit:
  /// a model on an old computer can think for minutes, and the person can
  /// cancel at any moment.
  final Duration answerSilence;

  GopherClient({
    this.timeout = const Duration(seconds: 30),
    this.maxResponseBytes = 8 * 1024 * 1024,
    this.answerSilence = const Duration(minutes: 15),
  });

  Future<List<int>> _read(
    GopherAddress address,
    GopherRequest request, {
    required bool framed,
    void Function(List<int> chunk)? onChunk,
  }) async {
    Socket? socket;
    final stopwatch = Stopwatch()..start();
    try {
      request.check();
      final host = address.host.replaceAll(RegExp(r'^\[|\]$'), '');
      socket = await Socket.connect(host, address.port, timeout: timeout);
      request.attach(socket);
      final remaining = timeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Connection timed out');
      }
      socket.write('${address.request}\r\n');
      final connection = socket;
      final question = address.isLocalQuestion;
      final reading = (() async {
        await connection.flush();
        final bytes = BytesBuilder(copy: false);
        var lineStart = true;
        var dot = false;
        var dotCr = false;
        final input = question ? connection.timeout(answerSilence) : connection;
        await for (final chunk in input) {
          request.check();
          if (bytes.length + chunk.length > maxResponseBytes) {
            throw GopherException(t.responseTooLarge);
          }
          if (framed) {
            // A standalone period may be split across TCP chunks.
            for (var i = 0; i < chunk.length; i++) {
              final byte = chunk[i];
              if ((dot || dotCr) && byte == 10) {
                bytes.add(chunk.sublist(0, i + 1));
                return bytes.takeBytes();
              }
              if (dot && byte == 13) {
                dot = false;
                dotCr = true;
              } else {
                dot = lineStart && byte == 46;
                dotCr = false;
              }
              lineStart = byte == 10;
            }
          }
          bytes.add(chunk);
          onChunk?.call(chunk);
        }
        request.check();
        // Old servers may leave out the last line, but this is a model that was
        // answering, and it always writes it unless it was stopped.
        if (framed && question) {
          throw GopherException(t.answerStopped);
        }
        return bytes.takeBytes();
      })();
      return await (question ? reading : reading.timeout(remaining));
    } on SocketException catch (e) {
      throw GopherException(t.connectionFailed(e.message));
    } on TimeoutException {
      throw GopherException(t.connectionTimedOut);
    } on GopherException {
      rethrow;
    } catch (e) {
      throw GopherException(t.couldNotReadResponse('$e'));
    } finally {
      socket?.destroy();
    }
  }

  Future<String> fetch(GopherAddress address, {GopherRequest? request}) async {
    return _decode(
      await _read(address, request ?? GopherRequest(), framed: true),
    );
  }

  String _decode(List<int> bytes) {
    // UTF-8 first; Latin-1 preserves bytes in older Gopher documents.
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  Future<String> fetchText(
    GopherAddress address, {
    GopherRequest? request,
  }) async {
    final content = await fetch(address, request: request);
    final lines = content.split('\n');
    final result = <String>[];
    for (var line in lines) {
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line == '.') break;
      if (line.startsWith('..')) line = line.substring(1);
      result.add(line);
    }
    return result.join('\n');
  }

  /// [onPartial] gets every whole menu line so far, as they arrive. The list
  /// returned at the end is still the authority.
  Future<List<GopherItem>> fetchMenu(
    GopherAddress address, {
    GopherRequest? request,
    void Function(List<GopherItem> soFar)? onPartial,
  }) async {
    final partial = onPartial == null ? null : _PartialMenu(this, onPartial);
    return parseMenu(
      _decode(
        await _read(
          address,
          request ?? GopherRequest(),
          framed: true,
          onChunk: partial?.add,
        ),
      ),
    );
  }

  List<GopherItem> parseMenu(String content) {
    final items = <GopherItem>[];
    for (var line in content.split('\n')) {
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line == '.') break;
      if (line.isEmpty) continue;
      try {
        final item = GopherItem.fromLine(line);
        if (item.isNavigable) item.address;
        items.add(item);
      } on FormatException {
        continue;
      } on ArgumentError {
        continue;
      }
    }
    return items;
  }

  Future<List<int>> fetchBinary(
    GopherAddress address, {
    GopherRequest? request,
  }) => _read(address, request ?? GopherRequest(), framed: false);

  Future<List<GopherItem>> search(
    GopherAddress address,
    String query, {
    GopherRequest? request,
  }) => fetchMenu(
    GopherAddress(
      host: address.host,
      port: address.port,
      selector: address.selector,
      type: GopherItemType.search,
      query: query,
    ),
    request: request,
  );
}

/// Parses whole lines as they arrive. A line split across TCP chunks, or a
/// character split inside one, waits for the rest.
class _PartialMenu {
  final GopherClient _client;
  final void Function(List<GopherItem>) _onPartial;
  final _items = <GopherItem>[];
  var _pending = <int>[];

  _PartialMenu(this._client, this._onPartial);

  void add(List<int> chunk) {
    final end = chunk.lastIndexOf(10);
    if (end < 0) {
      _pending = [..._pending, ...chunk];
      return;
    }
    final whole = [..._pending, ...chunk.sublist(0, end + 1)];
    _pending = chunk.sublist(end + 1);
    final fresh = _client.parseMenu(_client._decode(whole));
    if (fresh.isEmpty) return;
    _items.addAll(fresh);
    _onPartial(List.unmodifiable(_items));
  }
}
