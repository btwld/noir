import 'dart:async';

import 'package:noir/src/core/input.dart';
import 'package:noir/src/core/stdin_input_driver.dart';
import 'package:test/test.dart';

void main() {
  group('StdinInputDriver lifecycle', () {
    for (final inheritedLineMode in <bool>[false, true]) {
      for (final inheritedEchoMode in <bool>[false, true]) {
        test('restores inherited line=$inheritedLineMode '
            'echo=$inheritedEchoMode exactly', () {
          final source = _FakeStdinInputSource(
            lineMode: inheritedLineMode,
            echoMode: inheritedEchoMode,
          );
          addTearDown(source.close);
          final driver = StdinInputDriver(InputDispatcher(), source: source);

          expect(driver.start(), isTrue);
          expect(source.lineMode, isFalse);
          expect(source.echoMode, isFalse);

          driver.stop();

          expect(source.lineMode, inheritedLineMode);
          expect(source.echoMode, inheritedEchoMode);
          expect(source.modeMutations, <String>[
            'echo=false',
            'line=false',
            'line=$inheritedLineMode',
            'echo=$inheritedEchoMode',
          ]);
        });
      }
    }

    test('non-terminal stdin is not acquired', () {
      final source = _FakeStdinInputSource(
        hasTerminal: false,
        lineMode: true,
        echoMode: true,
      );
      addTearDown(source.close);
      final driver = StdinInputDriver(InputDispatcher(), source: source);

      expect(driver.start(), isFalse);
      driver.stop();

      expect(source.hasTerminalReads, 1);
      expect(source.lineModeReads, 0);
      expect(source.echoModeReads, 0);
      expect(source.listenAttempts, 0);
      expect(source.modeMutations, isEmpty);
    });

    test('echo acquisition failure rolls back and remains primary', () {
      final primary = StateError('echo acquisition failed');
      final primaryStack = StackTrace.current;
      final source = _FakeStdinInputSource(lineMode: true, echoMode: true)
        ..failNextModeMutation('echo=false', primary, primaryStack);
      addTearDown(source.close);
      final driver = StdinInputDriver(InputDispatcher(), source: source);

      final caught = _captureFailure(driver.start);

      expect(caught.error, same(primary));
      expect(caught.stackTrace.toString(), primaryStack.toString());
      expect(source.lineMode, isTrue);
      expect(source.echoMode, isTrue);
      expect(source.listenAttempts, 0);
      expect(source.modeMutations, <String>[
        'echo=false',
        'line=true',
        'echo=true',
      ]);
      expect(driver.stop, returnsNormally);
    });

    test('line acquisition failure restores echo and remains primary', () {
      final primary = StateError('line acquisition failed');
      final primaryStack = StackTrace.current;
      final source = _FakeStdinInputSource(lineMode: true, echoMode: true)
        ..failNextModeMutation('line=false', primary, primaryStack);
      addTearDown(source.close);
      final driver = StdinInputDriver(InputDispatcher(), source: source);

      final caught = _captureFailure(driver.start);

      expect(caught.error, same(primary));
      expect(caught.stackTrace.toString(), primaryStack.toString());
      expect(source.lineMode, isTrue);
      expect(source.echoMode, isTrue);
      expect(source.listenAttempts, 0);
      expect(source.modeMutations, <String>[
        'echo=false',
        'line=false',
        'line=true',
        'echo=true',
      ]);
      expect(driver.stop, returnsNormally);
    });

    test('listen failure restores both modes and remains primary', () {
      final primary = StateError('stdin listen failed');
      final primaryStack = StackTrace.current;
      final source = _FakeStdinInputSource(
        lineMode: true,
        echoMode: false,
        listenFailure: _Failure(primary, primaryStack),
      );
      addTearDown(source.close);
      final driver = StdinInputDriver(InputDispatcher(), source: source);

      final caught = _captureFailure(driver.start);

      expect(caught.error, same(primary));
      expect(caught.stackTrace.toString(), primaryStack.toString());
      expect(source.lineMode, isTrue);
      expect(source.echoMode, isFalse);
      expect(source.listenAttempts, 1);
      expect(source.modeMutations, <String>[
        'echo=false',
        'line=false',
        'line=true',
        'echo=false',
      ]);
      expect(driver.stop, returnsNormally);
    });

    test('listen failure remains primary when rollback also fails', () {
      final primary = StateError('stdin listen failed');
      final primaryStack = StackTrace.current;
      final rollback = StateError('line rollback failed');
      final source = _FakeStdinInputSource(
        lineMode: true,
        echoMode: true,
        listenFailure: _Failure(primary, primaryStack),
      )..failNextModeMutation('line=true', rollback, StackTrace.current);
      addTearDown(source.close);
      final driver = StdinInputDriver(InputDispatcher(), source: source);

      final caught = _captureFailure(driver.start);

      expect(caught.error, same(primary));
      expect(caught.stackTrace.toString(), primaryStack.toString());
      expect(source.lineMode, isFalse);
      expect(source.echoMode, isTrue);
      expect(source.modeMutations, <String>[
        'echo=false',
        'line=false',
        'line=true',
        'echo=true',
      ]);
      expect(driver.stop, returnsNormally);
    });

    test('stop attempts echo restore after line restore failure', () {
      final primary = StateError('line restore failed');
      final primaryStack = StackTrace.current;
      final source = _FakeStdinInputSource(lineMode: true, echoMode: true);
      addTearDown(source.close);
      final driver = StdinInputDriver(InputDispatcher(), source: source);
      expect(driver.start(), isTrue);
      source.failNextModeMutation('line=true', primary, primaryStack);

      final caught = _captureFailure(driver.stop);

      expect(caught.error, same(primary));
      expect(caught.stackTrace.toString(), primaryStack.toString());
      expect(source.lineMode, isFalse);
      expect(source.echoMode, isTrue);
      expect(source.cancelAttempts, 1);
      expect(driver.stop, returnsNormally);
      expect(source.cancelAttempts, 1);
    });

    test('stop restores without probing terminal status again', () {
      final source = _FakeStdinInputSource(lineMode: true, echoMode: false);
      addTearDown(source.close);
      final driver = StdinInputDriver(InputDispatcher(), source: source);
      expect(driver.start(), isTrue);
      source.hasTerminal = false;

      driver.stop();

      expect(source.hasTerminalReads, 1);
      expect(source.lineMode, isTrue);
      expect(source.echoMode, isFalse);
    });

    test('start and stop are idempotent', () {
      final source = _FakeStdinInputSource(lineMode: true, echoMode: true);
      addTearDown(source.close);
      final driver = StdinInputDriver(InputDispatcher(), source: source);

      expect(driver.start(), isTrue);
      expect(driver.start(), isTrue);
      driver
        ..stop()
        ..stop();

      expect(source.listenAttempts, 1);
      expect(source.cancelAttempts, 1);
      expect(source.modeMutations, <String>[
        'echo=false',
        'line=false',
        'line=true',
        'echo=true',
      ]);
    });
  });
}

_CaughtFailure _captureFailure(void Function() action) {
  try {
    action();
  } on Object catch (error, stackTrace) {
    return _CaughtFailure(error, stackTrace);
  }
  throw StateError('Expected action to fail');
}

final class _CaughtFailure {
  const _CaughtFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

final class _Failure {
  const _Failure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

final class _FakeStdinInputSource implements StdinInputSource {
  _FakeStdinInputSource({
    required bool lineMode,
    required bool echoMode,
    bool hasTerminal = true,
    this.listenFailure,
  }) : _hasTerminal = hasTerminal,
       _lineMode = lineMode,
       _echoMode = echoMode {
    _controller = StreamController<List<int>>.broadcast(
      sync: true,
      onCancel: () => cancelAttempts++,
    );
  }

  bool _hasTerminal;
  bool _lineMode;
  bool _echoMode;
  final _modeFailures = <String, _Failure>{};
  late final StreamController<List<int>> _controller;
  final List<String> modeMutations = <String>[];
  final _Failure? listenFailure;
  int hasTerminalReads = 0;
  int lineModeReads = 0;
  int echoModeReads = 0;
  int listenAttempts = 0;
  int cancelAttempts = 0;

  void failNextModeMutation(
    String mutation,
    Object error,
    StackTrace stackTrace,
  ) {
    _modeFailures[mutation] = _Failure(error, stackTrace);
  }

  @override
  bool get hasTerminal {
    hasTerminalReads++;
    return _hasTerminal;
  }

  set hasTerminal(bool value) => _hasTerminal = value;

  @override
  bool get lineMode {
    lineModeReads++;
    return _lineMode;
  }

  @override
  set lineMode(bool value) {
    final mutation = 'line=$value';
    modeMutations.add(mutation);
    final failure = _modeFailures.remove(mutation);
    if (failure != null) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
    _lineMode = value;
  }

  @override
  bool get echoMode {
    echoModeReads++;
    return _echoMode;
  }

  @override
  set echoMode(bool value) {
    final mutation = 'echo=$value';
    modeMutations.add(mutation);
    final failure = _modeFailures.remove(mutation);
    if (failure != null) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
    _echoMode = value;
  }

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>) onData) {
    listenAttempts++;
    final failure = listenFailure;
    if (failure != null) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
    return _controller.stream.listen(onData);
  }

  Future<void> close() => _controller.close();
}
