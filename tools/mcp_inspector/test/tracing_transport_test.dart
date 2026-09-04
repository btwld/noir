import 'package:mcp_dart/mcp_dart.dart';
import 'package:noir_mcp_inspector/noir_mcp_inspector.dart';
import 'package:test/test.dart';

/// An in-memory [Transport] whose peer traffic the test drives by hand.
final class RecordingTransport implements Transport {
  /// Messages handed to [send], in order.
  final List<JsonRpcMessage> sent = <JsonRpcMessage>[];

  /// Whether [start] ran.
  bool started = false;

  /// Whether [close] ran.
  bool closed = false;

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  @override
  String? get sessionId => 'recording-session';

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async =>
      sent.add(message);

  @override
  Future<void> close() async => closed = true;

  /// Delivers [message] as if the peer had sent it.
  void deliver(JsonRpcMessage message) => onmessage?.call(message);
}

void main() {
  group('TracingTransport', () {
    late RecordingTransport inner;
    late List<ProtocolEntry> entries;
    late TracingTransport traced;

    setUp(() {
      inner = RecordingTransport();
      entries = <ProtocolEntry>[];
      traced = TracingTransport(inner, onEntry: entries.add);
    });

    test('records direction, order, and the exact wire JSON', () async {
      const request = JsonRpcRequest(
        id: 1,
        method: 'tools/call',
        params: <String, dynamic>{'name': 'calculate'},
      );
      const response = JsonRpcResponse(
        id: 1,
        result: <String, dynamic>{'content': <dynamic>[]},
      );

      await traced.send(request);
      inner.deliver(response);

      expect(entries, hasLength(2));
      expect(entries[0].sequence, 1);
      expect(entries[0].direction, ProtocolDirection.outgoing);
      expect(entries[0].message, equals(request.toJson()));
      expect(entries[0].method, 'tools/call');
      expect(entries[0].isRequest, isTrue);
      expect(entries[1].sequence, 2);
      expect(entries[1].direction, ProtocolDirection.incoming);
      expect(entries[1].message, equals(response.toJson()));
      expect(entries[1].isResult, isTrue);
    });

    test('forwards start, send, close, sessionId, and messages', () async {
      JsonRpcMessage? seen;
      traced.onmessage = (message) => seen = message;

      await traced.start();
      const notification = JsonRpcNotification(
        method: 'notifications/tools/list_changed',
      );
      await traced.send(notification);
      inner.deliver(notification);
      await traced.close();

      expect(inner.started, isTrue);
      expect(inner.closed, isTrue);
      expect(inner.sent.single, same(notification));
      expect(seen, same(notification));
      expect(traced.sessionId, 'recording-session');
      expect(entries.map((entry) => entry.direction), <ProtocolDirection>[
        ProtocolDirection.outgoing,
        ProtocolDirection.incoming,
      ]);
      expect(entries.every((entry) => entry.isNotification), isTrue);
    });

    test('degrades a request-id send onto a plain transport', () async {
      const request = JsonRpcRequest(id: 'abc', method: 'ping');

      await traced.sendWithRequestId(request, relatedRequestId: 'abc');

      expect(inner.sent.single, same(request));
      expect(entries.single.direction, ProtocolDirection.outgoing);
      expect(entries.single.id, 'abc');
    });

    test('holds the protocol version a plain transport cannot store', () {
      traced.protocolVersion = '2026-07-28';

      expect(traced.protocolVersion, '2026-07-28');
    });

    test('forwards close and error callbacks to its own listeners', () {
      var closes = 0;
      Error? failure;
      traced.onclose = () {
        closes++;
      };
      traced.onerror = (error) {
        failure = error;
      };

      inner.onclose!();
      inner.onerror!(StateError('boom'));

      expect(closes, 1);
      expect(failure, isA<StateError>());
    });
  });

  group('ProtocolLog', () {
    test('pairs a response with the request that shares its id', () {
      final log = ProtocolLog();
      final sentAt = DateTime(2026, 9, 3, 12);

      log.add(
        ProtocolEntry(
          sequence: 1,
          direction: ProtocolDirection.outgoing,
          message: const <String, dynamic>{'id': 3, 'method': 'tools/call'},
          timestamp: sentAt,
        ),
      );
      final response = log.add(
        ProtocolEntry(
          sequence: 2,
          direction: ProtocolDirection.incoming,
          message: const <String, dynamic>{
            'id': 3,
            'result': <String, dynamic>{},
          },
          timestamp: sentAt.add(const Duration(milliseconds: 12)),
        ),
      );

      expect(response.elapsed, const Duration(milliseconds: 12));
      expect(log.entries.first.label, '-> tools/call #3');
      expect(log.entries.last.label, '<- result #3 12ms');
    });

    test(
      'keeps a client request and a server request with the same id apart',
      () {
        final log = ProtocolLog();
        final at = DateTime(2026, 9, 3, 12);

        log.add(
          ProtocolEntry(
            sequence: 1,
            direction: ProtocolDirection.outgoing,
            message: const <String, dynamic>{'id': 1, 'method': 'tools/call'},
            timestamp: at,
          ),
        );
        log.add(
          ProtocolEntry(
            sequence: 2,
            direction: ProtocolDirection.incoming,
            message: const <String, dynamic>{
              'id': 1,
              'method': 'elicitation/create',
            },
            timestamp: at.add(const Duration(milliseconds: 5)),
          ),
        );
        final serverAnswer = log.add(
          ProtocolEntry(
            sequence: 3,
            direction: ProtocolDirection.outgoing,
            message: const <String, dynamic>{
              'id': 1,
              'result': <String, dynamic>{},
            },
            timestamp: at.add(const Duration(milliseconds: 9)),
          ),
        );
        final clientAnswer = log.add(
          ProtocolEntry(
            sequence: 4,
            direction: ProtocolDirection.incoming,
            message: const <String, dynamic>{
              'id': 1,
              'result': <String, dynamic>{},
            },
            timestamp: at.add(const Duration(milliseconds: 20)),
          ),
        );

        expect(serverAnswer.elapsed, const Duration(milliseconds: 4));
        expect(clientAnswer.elapsed, const Duration(milliseconds: 20));
      },
    );

    test('drops the oldest entries past its limit', () {
      final log = ProtocolLog(limit: 2);
      for (var index = 1; index <= 4; index++) {
        log.add(
          ProtocolEntry(
            sequence: index,
            direction: ProtocolDirection.outgoing,
            message: <String, dynamic>{'method': 'ping', 'id': index},
            timestamp: DateTime(2026, 9, 3, 12, 0, index),
          ),
        );
      }

      expect(log.length, 2);
      expect(log.entries.map((entry) => entry.sequence), <int>[3, 4]);
    });
  });
}
