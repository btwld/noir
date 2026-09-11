/// The wire-level record of one MCP session.
///
/// [ProtocolEntry] is one JSON-RPC message exactly as it crossed the
/// transport. [ProtocolLog] keeps a bounded tail of those entries and pairs
/// each response with the request that carries the same JSON-RPC id, so the
/// user interface can show a round-trip time without asking the SDK.
library;

/// Which way a recorded JSON-RPC message travelled.
enum ProtocolDirection {
  /// The client sent the message to the server.
  outgoing,

  /// The client received the message from the server.
  incoming,
}

/// One JSON-RPC message recorded by the tracing transport.
final class ProtocolEntry {
  /// Creates a recorded message.
  const ProtocolEntry({
    required this.sequence,
    required this.direction,
    required this.message,
    required this.timestamp,
    this.elapsed,
  });

  /// Position of this entry in the session, starting at one.
  final int sequence;

  /// Which way the message travelled.
  final ProtocolDirection direction;

  /// The message as JSON, exactly as `JsonRpcMessage.toJson()` produced it.
  final Map<String, dynamic> message;

  /// When the transport recorded the message.
  final DateTime timestamp;

  /// Round-trip time, present only on a response paired with its request.
  final Duration? elapsed;

  /// The JSON-RPC method, or null for a response.
  String? get method {
    final value = message['method'];
    return value is String ? value : null;
  }

  /// The JSON-RPC id, or null for a notification.
  Object? get id => message['id'];

  /// Whether this entry carries a successful result.
  bool get isResult => message.containsKey('result');

  /// Whether this entry carries a JSON-RPC error.
  bool get isError => message.containsKey('error');

  /// Whether this entry is a request that expects a response.
  bool get isRequest => method != null && message.containsKey('id');

  /// Whether this entry is a notification.
  bool get isNotification => method != null && !message.containsKey('id');

  /// One row of the protocol pane, such as `-> tools/call #3`.
  String get label {
    final arrow = direction == ProtocolDirection.outgoing ? '->' : '<-';
    final name = method ?? (isError ? 'error' : 'result');
    final reference = id == null ? '' : ' #$id';
    final timing = elapsed == null ? '' : ' ${elapsed!.inMilliseconds}ms';
    return '$arrow $name$reference$timing';
  }

  /// Returns a copy of this entry with [elapsed] attached.
  ProtocolEntry withElapsed(Duration value) => ProtocolEntry(
    sequence: sequence,
    direction: direction,
    message: message,
    timestamp: timestamp,
    elapsed: value,
  );
}

/// A bounded, request-paired record of the JSON-RPC traffic on one session.
final class ProtocolLog {
  /// Creates a log that keeps at most [limit] entries.
  ProtocolLog({this.limit = 500}) : assert(limit > 0, 'limit must be positive');

  /// Greatest number of entries retained; older entries are dropped first.
  final int limit;

  final List<ProtocolEntry> _entries = <ProtocolEntry>[];
  final Map<String, DateTime> _pendingRequests = <String, DateTime>{};

  /// The retained entries, oldest first.
  List<ProtocolEntry> get entries => List<ProtocolEntry>.unmodifiable(_entries);

  /// Number of entries retained.
  int get length => _entries.length;

  /// Records [entry], pairing a response with its request when possible.
  ///
  /// Returns the stored entry, which carries [ProtocolEntry.elapsed] when this
  /// call paired a response with an earlier request of the same id.
  ProtocolEntry add(ProtocolEntry entry) {
    var stored = entry;
    final id = entry.id;
    if (id != null) {
      // A request is keyed by the direction that sent it, so a client request
      // and a server request that reuse the same JSON-RPC id stay separate.
      if (entry.isRequest) {
        _pendingRequests['${entry.direction.name}:$id'] = entry.timestamp;
      } else if (entry.isResult || entry.isError) {
        final origin = entry.direction == ProtocolDirection.incoming
            ? ProtocolDirection.outgoing
            : ProtocolDirection.incoming;
        final sentAt = _pendingRequests.remove('${origin.name}:$id');
        if (sentAt != null) {
          stored = entry.withElapsed(entry.timestamp.difference(sentAt));
        }
      }
    }
    _entries.add(stored);
    while (_entries.length > limit) {
      _entries.removeAt(0);
    }
    return stored;
  }

  /// Drops every retained entry and every unpaired request.
  void clear() {
    _entries.clear();
    _pendingRequests.clear();
  }
}
