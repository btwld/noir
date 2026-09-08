import 'package:mcp_dart/mcp_dart.dart';

import 'protocol_log.dart';

/// A [Transport] decorator that records every JSON-RPC message it carries.
///
/// The decorator forwards `start`, `send`, `close`, and `sessionId` to the
/// wrapped transport and reports each message to [onEntry] as a
/// [ProtocolEntry]. Recorded JSON is exactly `JsonRpcMessage.toJson()`, so the
/// protocol pane shows the wire shape rather than a Dart summary.
///
/// [RequestIdAwareTransport] and [ProtocolVersionAwareTransport] are
/// implemented as pass-throughs. Both degrade correctly when the wrapped
/// transport does not implement them: request-id sends fall back to
/// [Transport.send] through `sendPreservingRequestId`, and the protocol
/// version is held here. Other optional transport capabilities, such as
/// [SubscriptionReplayAcknowledgmentTransport] and
/// [RequestCancellationAwareTransport], are deliberately not forwarded; a
/// decorator cannot implement them conditionally, and claiming them for a
/// transport that lacks them would change protocol behavior.
final class TracingTransport
    implements
        Transport,
        RequestIdAwareTransport,
        ProtocolVersionAwareTransport {
  /// Wraps [inner] and reports every message to [onEntry].
  TracingTransport(this.inner, {required this.onEntry}) {
    inner
      ..onmessage = _receive
      ..onclose = _closed
      ..onerror = _failed;
  }

  /// The wrapped transport that performs the real input and output.
  final Transport inner;

  /// Receives one entry for every message this transport carries.
  final void Function(ProtocolEntry entry) onEntry;

  int _sequence = 0;
  String? _protocolVersion;

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  @override
  String? get sessionId => inner.sessionId;

  @override
  String? get protocolVersion {
    final transport = inner;
    // `Transport` and `ProtocolVersionAwareTransport` are unrelated classes,
    // so an explicit cast is required here. mcp_dart casts the same way in
    // `client.dart` and `protocol.dart`.
    if (transport is! ProtocolVersionAwareTransport) return _protocolVersion;
    return (transport as ProtocolVersionAwareTransport).protocolVersion;
  }

  @override
  set protocolVersion(String? value) {
    _protocolVersion = value;
    final transport = inner;
    if (transport is! ProtocolVersionAwareTransport) return;
    (transport as ProtocolVersionAwareTransport).protocolVersion = value;
  }

  @override
  Future<void> start() => inner.start();

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) {
    _record(ProtocolDirection.outgoing, message);
    return inner.send(message, relatedRequestId: relatedRequestId);
  }

  @override
  Future<void> sendWithRequestId(
    JsonRpcMessage message, {
    RequestId? relatedRequestId,
  }) {
    _record(ProtocolDirection.outgoing, message);
    return inner.sendPreservingRequestId(
      message,
      relatedRequestId: relatedRequestId,
    );
  }

  @override
  Future<void> close() => inner.close();

  void _receive(JsonRpcMessage message) {
    _record(ProtocolDirection.incoming, message);
    onmessage?.call(message);
  }

  void _closed() => onclose?.call();

  void _failed(Error error) => onerror?.call(error);

  void _record(ProtocolDirection direction, JsonRpcMessage message) {
    _sequence++;
    onEntry(
      ProtocolEntry(
        sequence: _sequence,
        direction: direction,
        message: message.toJson(),
        timestamp: DateTime.now(),
      ),
    );
  }
}
