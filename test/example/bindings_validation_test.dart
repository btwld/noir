import 'dart:async';

import 'package:noir/noir_ffi.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../../example/bindings_validation.dart';
import '../helpers/buffer_capture.dart';

void main() {
  test('renders all validation frames through the borrowed renderer', () async {
    final renderer = Renderer.create(80, 30, testing: true);
    final frames = <CapturedBuffer>[];
    final printed = <String>[];
    addTearDown(renderer.dispose);

    await runZoned(
      () => runBindingsValidationDemos(
        renderer,
        waitForUser: () async {
          frames.add(CapturedBuffer.fromBuffer(renderer.debugCurrentBuffer));
        },
      ),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );

    expect(printed, isEmpty, reason: 'rendering must not write outside frames');
    expect(frames, hasLength(5));

    for (final frame in frames) {
      expect(frame, BufferMatchers.containsText('Press ENTER to continue...'));
    }
    for (final frame in frames.take(4)) {
      expect((frame.width, frame.height), (80, 30));
    }
    expect((frames[4].width, frames[4].height), (120, 40));

    expect(
      frames[0],
      BufferMatchers.containsText('Noir FFI Bindings Validation'),
    );
    expect(frames[0], BufferMatchers.hasColorAt(12, 2, Color.yellow));
    expect(frames[0].getCell(12, 2).hasAttribute(Attr.bold), isTrue);
    expect(frames[0].getCell(12, 2).hasAttribute(Attr.underline), isTrue);

    expect(
      frames[1],
      BufferMatchers.containsText('Color Palette Demonstration'),
    );
    expect(frames[1], BufferMatchers.hasColorAt(5, 5, Color.red));

    expect(
      frames[2],
      BufferMatchers.containsText('Text Attributes Demonstration'),
    );
    expect(frames[2], BufferMatchers.hasColorAt(5, 7, Color.yellow));
    expect(frames[2].getCell(5, 7).hasAttribute(Attr.bold), isTrue);

    expect(frames[3], BufferMatchers.containsText('Box Drawing Demonstration'));
    expect(frames[3].getCell(22, 1).hasAttribute(Attr.bold), isTrue);
    expect(frames[3].findText('Filled box with'), hasLength(1));

    expect(
      frames[4],
      BufferMatchers.containsText('Large Buffer Performance Test (120x40)'),
    );
    expect(frames[4], BufferMatchers.hasColorAt(35, 38, Color.cyan));
  });

  group('bindings validation input lease', () {
    test(
      'consumes capability replies through LF and restores modes once',
      () async {
        final capabilityReplies = <int>[
          ...'\x1b[?2026;1\$y'.codeUnits,
          ...'\x1bP>|iTerm2 3.6.10\x1b\\'.codeUnits,
          ...'\x1b_Gi=1;invalid payload\x1b\\'.codeUnits,
        ];
        final source = _FakeBindingsValidationStdin(
          bytes: [...capabilityReplies, 0x0a, 0x7a],
        );

        final input = BindingsValidationInputLease.acquire(source);

        expect(source.modeMutations, ['echo=false', 'line=false']);
        await input.waitForEnter();
        expect(source.bytesRead, capabilityReplies.length + 1);
        expect(source.remainingBytes, [0x7a]);

        input
          ..restore()
          ..restore();
        expect(source.modeMutations, [
          'echo=false',
          'line=false',
          'line=true',
          'echo=true',
        ]);
      },
    );

    test('uses CR as Enter on Windows', () async {
      final source = _FakeBindingsValidationStdin(
        isWindows: true,
        bytes: [0x1b, 0x0a, 0x0d, 0x51],
      );
      final input = BindingsValidationInputLease.acquire(source);

      await input.waitForEnter();

      expect(source.bytesRead, 3);
      expect(source.remainingBytes, [0x51]);
      input.restore();
    });

    test('reports EOF instead of advancing a scene', () async {
      final input = BindingsValidationInputLease.acquire(
        _FakeBindingsValidationStdin(),
      );
      addTearDown(input.restore);

      await expectLater(input.waitForEnter(), throwsA(isA<StateError>()));
    });

    test('rejects non-terminal stdin before changing modes', () {
      final source = _FakeBindingsValidationStdin(hasTerminal: false);

      expect(
        () => BindingsValidationInputLease.acquire(source),
        throwsA(isA<StateError>()),
      );
      expect(source.modeMutations, isEmpty);
    });

    test('restore attempts both modes and retains its first failure', () async {
      final lineFailure = _failure('restore-line');
      final echoFailure = _failure('restore-echo');
      final source = _FakeBindingsValidationStdin(
        modeFailures: {'line=true': lineFailure, 'echo=true': echoFailure},
      );
      final input = BindingsValidationInputLease.acquire(source);

      await _expectFailureIdentity(() async => input.restore(), lineFailure);
      input.restore();

      expect(source.modeMutations, [
        'echo=false',
        'line=false',
        'line=true',
        'echo=true',
      ]);
    });
  });

  group('bindings validation coordinator', () {
    test('owns input before setup and cleans up after five scenes', () async {
      final events = <String>[];
      final frames = <CapturedBuffer>[];
      final printed = <String>[];
      late _RecordingRuntime runtime;
      final input = _RecordingInput(
        events,
        onWait: () {
          frames.add(
            CapturedBuffer.fromBuffer(runtime.renderer!.debugCurrentBuffer),
          );
        },
      );
      runtime = _RecordingRuntime(events: events, input: input);

      await runZoned(
        () => runBindingsValidation(runtime: runtime),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => printed.add(line),
        ),
      );

      expect(printed, isEmpty);
      expect(events, [
        'create',
        'acquire',
        'setup',
        'hide',
        'wait',
        'wait',
        'wait',
        'wait',
        'wait',
        'restore',
        'dispose',
      ]);
      expect(frames, hasLength(5));
      expect((frames.first.width, frames.first.height), (80, 30));
      expect((frames.last.width, frames.last.height), (120, 40));
      expect(
        frames.first,
        BufferMatchers.containsText('Noir FFI Bindings Validation'),
      );
      expect(
        frames.last,
        BufferMatchers.containsText('Large Buffer Performance Test (120x40)'),
      );
    });

    test(
      'creation failure does not acquire or clean up absent owners',
      () async {
        final failure = _failure('create');
        final runtime = _RecordingRuntime(createFailure: failure);

        await _expectFailureIdentity(
          () => runBindingsValidation(runtime: runtime),
          failure,
        );

        expect(runtime.events, ['create']);
      },
    );

    test('acquisition rollback keeps its error and still disposes', () async {
      final acquisitionFailure = _failure('acquire-line-mode');
      final rollbackFailure = _failure('rollback-line-mode');
      final source = _FakeBindingsValidationStdin(
        modeFailures: {
          'line=false': acquisitionFailure,
          'line=true': rollbackFailure,
        },
      );
      final runtime = _RecordingRuntime(
        acquireInput: () => BindingsValidationInputLease.acquire(source),
      );

      await _expectFailureIdentity(
        () => runBindingsValidation(runtime: runtime),
        acquisitionFailure,
      );

      expect(source.modeMutations, [
        'echo=false',
        'line=false',
        'line=true',
        'echo=true',
      ]);
      expect(runtime.events, ['create', 'acquire', 'dispose']);
    });

    for (final point in ['setup', 'hide']) {
      test('$point failure restores input before renderer disposal', () async {
        final failure = _failure(point);
        final runtime = _RecordingRuntime(
          setupFailure: point == 'setup' ? failure : null,
          hideFailure: point == 'hide' ? failure : null,
        );

        await _expectFailureIdentity(
          () => runBindingsValidation(runtime: runtime),
          failure,
        );

        expect(runtime.events, [
          'create',
          'acquire',
          'setup',
          if (point == 'hide') 'hide',
          'restore',
          'dispose',
        ]);
      });
    }

    test('wait failure remains primary while both cleanups run', () async {
      final events = <String>[];
      final bodyFailure = _failure('wait-eof');
      final disposeFailure = _failure('dispose-after-wait');
      final input = _RecordingInput(
        events,
        waitFailure: bodyFailure,
        failWaitAt: 1,
      );
      final runtime = _RecordingRuntime(
        events: events,
        input: input,
        disposeFailure: disposeFailure,
      );

      await _expectFailureIdentity(
        () => runBindingsValidation(runtime: runtime),
        bodyFailure,
      );

      expect(events, [
        'create',
        'acquire',
        'setup',
        'hide',
        'wait',
        'restore',
        'dispose',
      ]);
    });

    test(
      'restoration failure remains primary and does not skip disposal',
      () async {
        final events = <String>[];
        final restoreFailure = _failure('restore');
        final disposeFailure = _failure('dispose-after-restore');
        final input = _RecordingInput(events, restoreFailure: restoreFailure);
        final runtime = _RecordingRuntime(
          events: events,
          input: input,
          disposeFailure: disposeFailure,
        );

        await _expectFailureIdentity(
          () => runBindingsValidation(runtime: runtime),
          restoreFailure,
        );

        expect(events.last, 'dispose');
        expect(events.where((event) => event == 'restore'), hasLength(1));
        expect(events.where((event) => event == 'dispose'), hasLength(1));
      },
    );

    test('disposal failure escapes when body and restore succeed', () async {
      final failure = _failure('dispose');
      final runtime = _RecordingRuntime(disposeFailure: failure);

      await _expectFailureIdentity(
        () => runBindingsValidation(runtime: runtime),
        failure,
      );

      expect(runtime.events.last, 'dispose');
    });
  });
}

typedef _Failure = ({Object error, StackTrace stack});

_Failure _failure(String name) =>
    (error: StateError(name), stack: StackTrace.fromString('$name stack'));

Never _throwFailure(_Failure failure) =>
    Error.throwWithStackTrace(failure.error, failure.stack);

Future<void> _expectFailureIdentity(
  Future<void> Function() action,
  _Failure failure,
) async {
  Object? caughtError;
  StackTrace? caughtStack;
  try {
    await action();
  } catch (error, stackTrace) {
    caughtError = error;
    caughtStack = stackTrace;
  }

  expect(caughtError, same(failure.error));
  expect(caughtStack.toString(), failure.stack.toString());
}

class _FakeBindingsValidationStdin implements BindingsValidationStdin {
  _FakeBindingsValidationStdin({
    this.hasTerminal = true,
    this.isWindows = false,
    bool lineMode = true,
    bool echoMode = true,
    List<int> bytes = const [],
    Map<String, _Failure> modeFailures = const {},
  }) : _lineMode = lineMode,
       _echoMode = echoMode,
       _bytes = List<int>.of(bytes),
       _modeFailures = Map<String, _Failure>.of(modeFailures);

  @override
  final bool hasTerminal;

  @override
  final bool isWindows;

  bool _lineMode;
  bool _echoMode;
  final List<int> _bytes;
  final Map<String, _Failure> _modeFailures;
  final List<String> modeMutations = [];
  int bytesRead = 0;

  List<int> get remainingBytes => _bytes.sublist(bytesRead);

  @override
  bool get lineMode => _lineMode;

  @override
  set lineMode(bool value) {
    final event = 'line=$value';
    modeMutations.add(event);
    final failure = _modeFailures[event];
    if (failure != null) _throwFailure(failure);
    _lineMode = value;
  }

  @override
  bool get echoMode => _echoMode;

  @override
  set echoMode(bool value) {
    final event = 'echo=$value';
    modeMutations.add(event);
    final failure = _modeFailures[event];
    if (failure != null) _throwFailure(failure);
    _echoMode = value;
  }

  @override
  int readByteSync() {
    if (bytesRead == _bytes.length) return -1;
    return _bytes[bytesRead++];
  }
}

class _RecordingInput implements BindingsValidationInput {
  _RecordingInput(
    this.events, {
    this.onWait,
    this.waitFailure,
    this.failWaitAt,
    this.restoreFailure,
  });

  final List<String> events;
  final void Function()? onWait;
  final _Failure? waitFailure;
  final int? failWaitAt;
  final _Failure? restoreFailure;
  int _waitCount = 0;
  bool _restored = false;

  @override
  Future<void> waitForEnter() async {
    events.add('wait');
    _waitCount++;
    onWait?.call();
    if (_waitCount == failWaitAt && waitFailure != null) {
      _throwFailure(waitFailure!);
    }
  }

  @override
  void restore() {
    if (_restored) return;
    _restored = true;
    events.add('restore');
    final failure = restoreFailure;
    if (failure != null) _throwFailure(failure);
  }
}

class _RecordingRuntime implements BindingsValidationRuntime {
  _RecordingRuntime({
    List<String>? events,
    BindingsValidationInput? input,
    BindingsValidationInput Function()? acquireInput,
    this.createFailure,
    this.setupFailure,
    this.hideFailure,
    this.disposeFailure,
  }) : events = events ?? <String>[],
       _input = input,
       _acquireInput = acquireInput;

  final List<String> events;
  BindingsValidationInput? _input;
  final BindingsValidationInput Function()? _acquireInput;
  final _Failure? createFailure;
  final _Failure? setupFailure;
  final _Failure? hideFailure;
  final _Failure? disposeFailure;
  Renderer? renderer;

  @override
  Renderer createRenderer(int width, int height) {
    events.add('create');
    final failure = createFailure;
    if (failure != null) _throwFailure(failure);
    return renderer = Renderer.create(width, height, testing: true);
  }

  @override
  BindingsValidationInput acquireInput() {
    events.add('acquire');
    return _acquireInput?.call() ?? (_input ??= _RecordingInput(events));
  }

  @override
  void setupTerminal(Renderer renderer) {
    events.add('setup');
    final failure = setupFailure;
    if (failure != null) _throwFailure(failure);
  }

  @override
  void hideCursor(Renderer renderer) {
    events.add('hide');
    final failure = hideFailure;
    if (failure != null) _throwFailure(failure);
  }

  @override
  void disposeRenderer(Renderer renderer) {
    events.add('dispose');
    renderer.dispose();
    final failure = disposeFailure;
    if (failure != null) _throwFailure(failure);
  }
}
