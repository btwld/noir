@Tags(['process-spawning'])
// Serialized wrapper lifecycles compose setup, event gates, bounded process
// completion, stream closure, and cleanup inside one Dart test; 60 seconds is
// the file's composed outer ceiling while _Harness.run bounds each spawned
// wrapper individually (P9-050).
@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

const _scriptPath = 'scripts/run_go_snapshot.sh';
const _fixtureDirectory = 'test/fixtures/go_snapshot';
const _timeoutDiagnostic =
    'Go snapshot timed out after 1 seconds in snapshot mode.\n';

String _timeoutDiagnosticFor(int seconds) =>
    'Go snapshot timed out after $seconds seconds in snapshot mode.\n';

final _posixOpen = ffi.DynamicLibrary.process()
    .lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ffi.Char>, ffi.Int32),
      int Function(ffi.Pointer<ffi.Char>, int)
    >('open');
final _posixWrite = ffi.DynamicLibrary.process()
    .lookupFunction<
      ffi.IntPtr Function(ffi.Int32, ffi.Pointer<ffi.Void>, ffi.IntPtr),
      int Function(int, ffi.Pointer<ffi.Void>, int)
    >('write');
final _posixClose = ffi.DynamicLibrary.process()
    .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>('close');

void _writeStartFifoToken(File fifo) {
  final path = fifo.path.toNativeUtf8();
  final token = 'start\n'.toNativeUtf8();
  var descriptor = -1;
  try {
    descriptor = _posixOpen(path.cast(), 1); // O_WRONLY.
    if (descriptor < 0) {
      throw FileSystemException('could not open start FIFO', fifo.path);
    }
    final written = _posixWrite(descriptor, token.cast(), 6);
    if (written != 6) {
      throw FileSystemException('could not write start FIFO', fifo.path);
    }
  } finally {
    if (descriptor >= 0) _posixClose(descriptor);
    calloc
      ..free(token)
      ..free(path);
  }
}

void main() {
  group('P9-042 Go snapshot supervisor', () {
    test(
      'preserves ordinary streams/status and removes its private temp',
      () async {
        await _withHarness((harness) async {
          final success = await harness.run(
            mode: 'success',
            arguments: const ['--probe', 'two words', ''],
            parentDeadline: const Duration(seconds: 16),
          );

          expect(success.exitCode, 0);
          expect(success.stdout, 'fixture stdout\n');
          expect(success.stderr, 'fixture stderr\n');
          expect(success.log, contains('argv|0|7|--probe\n'));
          expect(success.log, contains('argv|1|9|two words\n'));
          expect(success.log, contains('argv|2|0|\n'));
          expect(success.log, contains('cwd|${harness.goToolDirectory}\n'));
          expect(
            _traceCount(success.trace, '|cause|child|status=0'),
            1,
            reason: success.trace,
          );
          expect(
            _traceCount(success.trace, '|action|child|release|'),
            1,
            reason: success.trace,
          );
          expect(_traceCount(success.trace, '|action|watchdog|release|'), 1);
          expect(_signalsAfterAction(success.trace, 'child'), isEmpty);
          expect(_signalsAfterAction(success.trace, 'watchdog'), isEmpty);
          expect(_traceCount(success.trace, '|wait_consumed|child|'), 1);
          expect(_traceCount(success.trace, '|wait_consumed|watchdog|'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(success);

          final nonzero = await harness.run(mode: 'nonzero');
          expect(nonzero.exitCode, 23);
          expect(nonzero.stdout, 'fixture nonzero stdout\n');
          expect(nonzero.stderr, 'fixture nonzero stderr\n');
          expect(_traceCount(nonzero.trace, '|cause|child|status=23'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(nonzero);

          final inheritedErrexit = await harness.run(
            mode: 'nonzero',
            bashArguments: const ['-e'],
          );
          expect(inheritedErrexit.exitCode, 23);
          expect(inheritedErrexit.stdout, 'fixture nonzero stdout\n');
          expect(inheritedErrexit.stderr, 'fixture nonzero stderr\n');
          expect(
            _traceCount(inheritedErrexit.trace, '|cause|child|status=23'),
            1,
          );
          await harness.expectNoTempOwnersOrFixtureSurvivors(inheritedErrexit);
        });
      },
    );

    test(
      'validates the one timeout input before temp or process launch',
      () async {
        await _withHarness((harness) async {
          for (final invalid in <String>['', 'abc', '-1', ' 1', '0', '3601']) {
            final result = await harness.run(
              mode: 'success',
              timeoutValue: invalid,
            );
            expect(
              result.exitCode,
              64,
              reason: 'timeout value ${jsonEncode(invalid)} was accepted',
            );
            expect(result.stdout, isEmpty);
            expect(
              result.stderr,
              'invalid GO_SNAPSHOT_TIMEOUT_SECONDS: '
              'expected decimal integer 1..3600\n',
            );
            expect(result.log, isEmpty, reason: 'the fake Go command started');
            await harness.expectNoTempOwnersOrFixtureSurvivors(result);
          }

          final oneSecond = await harness.run(
            mode: 'success',
            timeoutValue: '0001',
            parentDeadline: const Duration(seconds: 12),
          );
          expect(oneSecond.exitCode, 124, reason: oneSecond.trace);
          expect(oneSecond.stderr, _timeoutDiagnostic);
          expect(oneSecond.log, isNot(contains('command-started|')));
          await harness.expectNoTempOwnersOrFixtureSurvivors(oneSecond);

          for (final valid in <String?>[null, '90', '3600']) {
            final result = await harness.run(
              mode: 'success',
              timeoutValue: valid,
            );
            expect(
              result.exitCode,
              0,
              reason:
                  'valid timeout $valid failed\n'
                  'stderr=${result.stderr}\ntrace=${result.trace}',
            );
            await harness.expectNoTempOwnersOrFixtureSurvivors(result);
          }
        });
      },
    );

    test(
      'records INT first, forwards it to the owned tree, and returns 130',
      () async {
        await _withHarness((harness) async {
          final result = await harness.run(
            mode: 'signal',
            timeoutValue: '20',
            afterStart: (process, run) async {
              await run.waitForLog('descendant-started', process: process);
              expect(
                Process.killPid(process.pid, ProcessSignal.sigint),
                isTrue,
              );
            },
          );

          expect(result.exitCode, 130);
          expect(result.stdout, 'fixture signal stdout\n');
          expect(result.stderr, 'fixture signal stderr\n');
          expect(result.log, contains('command-int'));
          expect(result.log, contains('descendant-int'));
          expect(_traceCount(result.trace, '|cause|signal|status=130'), 1);
          expect(_traceCount(result.trace, '|signal|child|INT|'), 1);
          expect(_traceCount(result.trace, '|wait_consumed|child|'), 1);
          expect(_traceCount(result.trace, '|wait_consumed|watchdog|'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );

    test(
      'records TERM first, forwards it to the owned tree, and returns 143',
      () async {
        await _withHarness((harness) async {
          final result = await harness.run(
            mode: 'signal',
            timeoutValue: '20',
            afterStart: (process, run) async {
              await run.waitForLog('descendant-started', process: process);
              expect(Process.killPid(process.pid), isTrue);
            },
          );

          expect(result.exitCode, 143);
          expect(result.stdout, 'fixture signal stdout\n');
          expect(result.stderr, 'fixture signal stderr\n');
          expect(result.log, contains('command-term'));
          expect(result.log, contains('descendant-term'));
          expect(_traceCount(result.trace, '|cause|signal|status=143'), 1);
          expect(_traceCount(result.trace, '|signal|child|TERM|'), 1);
          expect(_traceCount(result.trace, '|wait_consumed|child|'), 1);
          expect(_traceCount(result.trace, '|wait_consumed|watchdog|'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );

    test(
      'enforces a hard timeout and reaps a TERM-resistant descendant',
      () async {
        await _withHarness((harness) async {
          final result = await harness.run(
            mode: 'stubborn',
            timeoutValue: '4',
            parentDeadline: const Duration(seconds: 12),
          );

          expect(
            result.exitCode,
            124,
            reason: 'stderr=${result.stderr}\ntrace=${result.trace}',
          );
          expect(result.stdout, 'fixture stubborn stdout\n');
          expect(
            result.stderr,
            'fixture stubborn stderr\n${_timeoutDiagnosticFor(4)}',
          );
          expect(result.log, contains('command-term-ignored'));
          expect(result.log, contains('descendant-term-ignored'));
          expect(_traceCount(result.trace, '|cause|timeout|status=124'), 1);
          expect(_traceCount(result.trace, '|action|child|final_kill|'), 1);
          expect(_traceCount(result.trace, '|action|child|release|'), 0);
          expect(_traceCount(result.trace, '|signal|child|KILL|'), 1);
          expect(_traceCount(result.trace, '|wait_consumed|child|'), 1);
          expect(_traceCount(result.trace, '|wait_consumed|watchdog|'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );

    test('keeps child status 127 distinct from watchdog timeout 124', () async {
      await _withHarness((harness) async {
        final result = await harness.run(
          mode: 'exit127',
          parentDeadline: const Duration(seconds: 16),
        );
        expect(result.exitCode, 127);
        expect(result.stdout, 'fixture 127 stdout\n');
        expect(result.stderr, 'fixture 127 stderr\n');
        await harness.expectNoTempOwnersOrFixtureSurvivors(result);
      });
    });

    test('keeps child status 138 distinct from watchdog timeout 124', () async {
      await _withHarness((harness) async {
        final result = await harness.run(
          mode: 'exit138',
          parentDeadline: const Duration(seconds: 16),
        );
        expect(result.exitCode, 138);
        expect(result.stdout, 'fixture 138 stdout\n');
        expect(result.stderr, 'fixture 138 stderr\n');
        await harness.expectNoTempOwnersOrFixtureSurvivors(result);
      });
    });

    test(
      'watchdog timeout remains distinct from delayed child status 127',
      () async {
        await _withHarness((harness) async {
          final result = await harness.run(
            mode: 'delayed127',
            timeoutValue: '4',
            parentDeadline: const Duration(seconds: 12),
          );
          expect(result.exitCode, 124);
          expect(result.stdout, 'fixture delayed127 stdout\n');
          expect(
            result.stderr,
            'fixture delayed127 stderr\n${_timeoutDiagnosticFor(4)}',
          );
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );

    test('fails closed before releasing a rejected child anchor', () async {
      await _withHarness(fakePsMode: 'reject-child', (harness) async {
        final result = await harness.run(
          mode: 'success',
          parentDeadline: const Duration(seconds: 12),
        );

        expect(result.exitCode, 1);
        expect(result.stdout, isEmpty);
        expect(result.log, isEmpty, reason: 'the child gate was released');
        expect(result.stderr, contains('child process-group anchor'));
        await harness.expectNoTempOwnersOrFixtureSurvivors(result);
      });
    });

    test(
      'fails closed before releasing either anchor when watchdog rejects',
      () async {
        await _withHarness(fakePsMode: 'reject-watchdog', (harness) async {
          final result = await harness.run(
            mode: 'success',
            parentDeadline: const Duration(seconds: 12),
          );

          expect(result.exitCode, 1);
          expect(result.stdout, isEmpty);
          expect(result.log, isEmpty, reason: 'an anchor gate was released');
          expect(result.stderr, contains('watchdog process-group anchor'));
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );

    test(
      'retains and names temp when unaccepted identity cannot be consumed',
      () async {
        await _withHarness(fakePsMode: 'reject-child-uncertain', (
          harness,
        ) async {
          final result = await harness.run(
            mode: 'success',
            parentDeadline: const Duration(seconds: 16),
          );

          expect(result.exitCode, 1);
          expect(result.stdout, isEmpty);
          expect(result.log, isEmpty);
          expect(result.stderr, contains('retained temporary directory:'));
          final owners = harness.tempOwners;
          expect(owners, hasLength(1));
          expect(result.stderr, contains(owners.single.path));
          await harness.expectNoFixtureSurvivors(result);
        });
      },
    );

    test(
      'later cleanup signals cannot replace the first selected signal',
      () async {
        await _withHarness((harness) async {
          final intThenTerm = await harness.run(
            mode: 'stubborn',
            timeoutValue: '20',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForLog('descendant-started', process: process);
              await run.recordDescendants(process.pid);
              expect(
                Process.killPid(process.pid, ProcessSignal.sigint),
                isTrue,
              );
              await run.waitForLog('command-int-ignored', process: process);
              expect(Process.killPid(process.pid), isTrue);
            },
          );
          expect(intThenTerm.exitCode, 130);
          expect(intThenTerm.stdout, 'fixture stubborn stdout\n');
          expect(intThenTerm.stderr, 'fixture stubborn stderr\n');
          expect(_traceCount(intThenTerm.trace, '|cause|signal|status=130'), 1);
          expect(
            _traceCount(intThenTerm.trace, '|late_signal|TERM|ignored|'),
            1,
          );
          final lateSignal = intThenTerm.trace.indexOf(
            '|late_signal|TERM|ignored|',
          );
          final childAbsent = intThenTerm.trace.indexOf('|pid_absent|child|');
          final childConsumed = intThenTerm.trace.indexOf(
            '|wait_consumed|child|',
          );
          expect(lateSignal, greaterThanOrEqualTo(0));
          expect(childAbsent, greaterThan(lateSignal));
          expect(childConsumed, greaterThan(childAbsent));
          expect(
            intThenTerm.trace.substring(0, lateSignal),
            isNot(contains('|wait_consumed|child|')),
          );
          expect(_traceCount(intThenTerm.trace, '|wait_cached|child|'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(intThenTerm);

          final termThenInt = await harness.run(
            mode: 'stubborn',
            timeoutValue: '20',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForLog('descendant-started', process: process);
              await run.recordDescendants(process.pid);
              expect(Process.killPid(process.pid), isTrue);
              await run.waitForLog('command-term-ignored', process: process);
              expect(
                Process.killPid(process.pid, ProcessSignal.sigint),
                isTrue,
              );
            },
          );
          expect(termThenInt.exitCode, 143);
          expect(termThenInt.stdout, 'fixture stubborn stdout\n');
          expect(termThenInt.stderr, 'fixture stubborn stderr\n');
          expect(_traceCount(termThenInt.trace, '|cause|signal|status=143'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(termThenInt);
        });
      },
    );

    test(
      'validation drain ignores a later signal and consumes its leader',
      () async {
        await _withHarness(fakePsMode: 'reject-child-drain-gated', (
          harness,
        ) async {
          final result = await harness.run(
            mode: 'success',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForPsMarker(process: process);
              await run.recordDescendants(process.pid);
              expect(Process.killPid(process.pid), isTrue);
              await run.psGate.create();
            },
          );
          expect(result.exitCode, 1);
          expect(result.stdout, isEmpty);
          expect(
            result.stderr,
            'failed to verify child process-group anchor\n',
          );
          expect(_traceCount(result.trace, '|cause|protocol|status=1'), 1);
          expect(_traceCount(result.trace, '|wait_consumed|child|'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );

    test(
      'signal-before-selection wins and selected child ignores late signal',
      () async {
        await _withHarness((harness) async {
          final signalFirst = await harness.run(
            mode: 'gated-success',
            runFakePsMode: 'passthrough',
            timeoutValue: '20',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForLog('command-started', process: process);
              await run.waitForPsCount(5, process: process);
              await run.recordDescendants(process.pid);
              expect(
                Process.killPid(process.pid, ProcessSignal.sigstop),
                isTrue,
              );
              await run.commandGate.create();
              await run.waitForOwnedFile('outcome', process: process);
              expect(
                Process.killPid(process.pid, ProcessSignal.sigint),
                isTrue,
              );
              expect(
                Process.killPid(process.pid, ProcessSignal.sigcont),
                isTrue,
              );
            },
          );
          expect(signalFirst.exitCode, 130);
          expect(signalFirst.stdout, 'fixture gated stdout\n');
          expect(signalFirst.stderr, 'fixture gated stderr\n');
          await harness.expectNoTempOwnersOrFixtureSurvivors(signalFirst);

          final childFirst = await harness.run(
            mode: 'gated-success',
            runFakePsMode: 'passthrough',
            fakeRmMode: 'signal-final-term',
            timeoutValue: '20',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForLog('command-started', process: process);
              await run.recordDescendants(process.pid);
              await run.commandGate.create();
            },
          );
          expect(childFirst.exitCode, 0);
          expect(childFirst.stdout, 'fixture gated stdout\n');
          expect(childFirst.stderr, 'fixture gated stderr\n');
          expect(_traceCount(signalFirst.trace, '|cause|signal|status=130'), 1);
          expect(_traceCount(childFirst.trace, '|cause|child|status=0'), 1);
          expect(childFirst.trace, isNot(contains('|cause|signal|')));
          await harness.expectNoTempOwnersOrFixtureSurvivors(childFirst);
        });
      },
    );

    test(
      'validation final-removal failure names the retained owner once',
      () async {
        await _withHarness(fakePsMode: 'reject-child', (harness) async {
          final result = await harness.run(
            mode: 'success',
            fakeRmMode: 'fail-final',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForPsCount(3, process: process);
              await run.recordDescendants(process.pid);
            },
          );
          expect(result.exitCode, 1);
          expect(result.stdout, isEmpty);
          final owners = harness.tempOwners;
          expect(owners, hasLength(1));
          final retainedLine =
              'cleanup could not remove; retained temporary directory: '
              '${owners.single.path}\n';
          expect(result.stderr, contains(retainedLine));
          expect(_occurrences(result.stderr, retainedLine), 1);
          await harness.expectNoOwnedSurvivors(result);
        });
      },
    );

    test(
      'rejects out-of-root, symlink, and non-private mktemp results',
      () async {
        await _withHarness((harness) async {
          late Directory outside;
          final outOfRoot = await harness.run(
            mode: 'success',
            fakeMktempMode: 'out-of-root',
            afterStart: (process, run) async {
              outside = run.outsideTemp;
            },
          );
          expect(outOfRoot.exitCode, 1);
          expect(outOfRoot.log, isEmpty);
          expect(outOfRoot.stderr, contains('invalid temporary directory'));
          expect(outside.existsSync(), isTrue);
          expect(outside.listSync(), isEmpty);
          await harness.expectNoOwnedSurvivors(outOfRoot);

          late Link invalidLink;
          late Directory linkTarget;
          final symlink = await harness.run(
            mode: 'success',
            fakeMktempMode: 'symlink',
            afterStart: (process, run) async {
              invalidLink = run.symlinkPath;
              linkTarget = run.symlinkTarget;
            },
          );
          expect(symlink.exitCode, 1);
          expect(symlink.log, isEmpty);
          expect(symlink.stderr, contains('invalid temporary directory'));
          expect(invalidLink.existsSync(), isTrue);
          expect(linkTarget.existsSync(), isTrue);
          expect(linkTarget.listSync(), isEmpty);
          await harness.expectNoOwnedSurvivors(symlink);

          final publicDirectory = await harness.run(
            mode: 'success',
            fakeMktempMode: 'public-dir',
          );
          expect(publicDirectory.exitCode, 1);
          expect(publicDirectory.log, isEmpty);
          expect(
            publicDirectory.stderr,
            contains('invalid temporary directory'),
          );
          expect(harness.tempEntries, isNotEmpty);
          await harness.expectNoOwnedSurvivors(publicDirectory);

          final entryPathsBeforeWrongPrefix = harness.tempEntries
              .map((entry) => entry.path)
              .toSet();
          final wrongPrefix = await harness.run(
            mode: 'success',
            fakeMktempMode: 'wrong-prefix',
          );
          expect(wrongPrefix.exitCode, 1);
          expect(wrongPrefix.log, isEmpty);
          expect(wrongPrefix.stderr, contains('invalid temporary directory'));
          final wrongEntries = harness.tempEntries
              .where(
                (entry) => !entryPathsBeforeWrongPrefix.contains(entry.path),
              )
              .toList();
          expect(wrongEntries, hasLength(1));
          final wrongDirectory = wrongEntries.single as Directory;
          expect(wrongDirectory.existsSync(), isTrue);
          expect(wrongDirectory.listSync(), isEmpty);
          await harness.expectNoOwnedSurvivors(wrongPrefix);

          final rootIsNotNormalizedToEmpty = await harness.run(
            mode: 'success',
            fakeMktempMode: 'fail',
            extraEnvironment: const <String, String>{'TMPDIR': '/'},
          );
          expect(rootIsNotNormalizedToEmpty.exitCode, 1);
          expect(
            rootIsNotNormalizedToEmpty.stderr,
            contains('could not create the Go snapshot temporary directory'),
          );
          expect(
            rootIsNotNormalizedToEmpty.stderr,
            isNot(contains('invalid TMPDIR')),
          );
          await harness.expectNoOwnedSurvivors(rootIsNotNormalizedToEmpty);
        });
      },
    );

    test('missing tools and failed temp acquisition start no owner', () async {
      await _withHarness((harness) async {
        for (final tool in const <String>[
          'go',
          'pkg-config',
          'uname',
          'tr',
          'mktemp',
          'mkdir',
          'rm',
          'ps',
          'stat',
          'nm',
        ]) {
          final missing = await harness.run(mode: 'success', missingTool: tool);
          expect(missing.exitCode, 1, reason: tool);
          expect(missing.stdout, isEmpty, reason: tool);
          expect(missing.log, isEmpty, reason: tool);
          expect(
            missing.stderr,
            'missing required Go snapshot tool: $tool\n',
            reason: tool,
          );
          await harness.expectNoTempOwnersOrFixtureSurvivors(missing);
        }

        final failedMktemp = await harness.run(
          mode: 'success',
          fakeMktempMode: 'fail',
        );
        expect(failedMktemp.exitCode, 1);
        expect(failedMktemp.stdout, isEmpty);
        expect(failedMktemp.log, isEmpty);
        expect(failedMktemp.stderr, contains('could not create'));
        await harness.expectNoTempOwnersOrFixtureSurvivors(failedMktemp);
      });
    });

    test(
      'malformed outcome is protocol failure without fabricated status',
      () async {
        await _withHarness((harness) async {
          final result = await harness.run(
            mode: 'gated-success',
            timeoutValue: '20',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForLog('command-started', process: process);
              await run.recordDescendants(process.pid);
              await File(
                '${run.activeTempOwner.path}/outcome',
              ).writeAsString('malformed\n');
            },
          );
          expect(result.exitCode, 1);
          expect(result.stdout, isEmpty);
          expect(result.stderr, isEmpty);
          expect(_traceCount(result.trace, '|cause|protocol|status=1'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );

    test('accepted anchor disappearance freezes production action', () async {
      await _withHarness((harness) async {
        final result = await harness.run(
          mode: 'stubborn',
          timeoutValue: '20',
          parentDeadline: const Duration(seconds: 16),
          afterStart: (process, run) async {
            await run.waitForLog('descendant-started', process: process);
            await run.recordDescendants(process.pid);
            final childPgid = await run.commandPgid(process: process);
            final killed = await Process.run('/bin/kill', [
              '-KILL',
              '--',
              '-$childPgid',
            ]);
            expect(killed.exitCode, 0);
          },
        );
        expect(result.exitCode, 1);
        expect(result.trace, contains('|action|child|frozen|'));
        expect(result.trace, isNot(contains('|action|child|release|')));
        expect(result.trace, isNot(contains('|action|child|final_kill|')));
        expect(_traceCount(result.trace, '|wait_consumed|child|'), 1);
        await harness.expectNoTempOwnersOrFixtureSurvivors(result);
      });
    });

    test(
      'missing outcome and invalid loser classification fail closed',
      () async {
        await _withHarness((harness) async {
          final missing = await harness.run(
            mode: 'gated-success',
            timeoutValue: '20',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForLog('command-started', process: process);
              await run.recordDescendants(process.pid);
              expect(
                Process.killPid(process.pid, ProcessSignal.sigstop),
                isTrue,
              );
              try {
                final outcome = File('${run.activeTempOwner.path}/outcome');
                await outcome.writeAsString('temporary foreign winner\n');
                await run.commandGate.create();
                await run.waitForOwnedFile(
                  'child.protocol-error',
                  process: process,
                );
                await outcome.delete();
              } finally {
                Process.killPid(process.pid, ProcessSignal.sigcont);
              }
            },
          );
          expect(missing.exitCode, 1);
          expect(missing.stdout, 'fixture gated stdout\n');
          expect(missing.stderr, 'fixture gated stderr\n');
          expect(_traceCount(missing.trace, '|cause|protocol|status=1'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(missing);

          final invalidLoser = await harness.run(
            mode: 'gated-success',
            timeoutValue: '20',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForLog('command-started', process: process);
              await run.recordDescendants(process.pid);
              expect(
                Process.killPid(process.pid, ProcessSignal.sigstop),
                isTrue,
              );
              try {
                await File(
                  '${run.activeTempOwner.path}/outcome',
                ).writeAsString('foreign\n');
                await run.commandGate.create();
                await run.waitForOwnedFile(
                  'child.protocol-error',
                  process: process,
                );
              } finally {
                Process.killPid(process.pid, ProcessSignal.sigcont);
              }
            },
          );
          expect(invalidLoser.exitCode, 1);
          expect(invalidLoser.stdout, 'fixture gated stdout\n');
          expect(invalidLoser.stderr, 'fixture gated stderr\n');
          expect(
            _traceCount(invalidLoser.trace, '|cause|protocol|status=1'),
            1,
          );
          await harness.expectNoTempOwnersOrFixtureSurvivors(invalidLoser);
        });
      },
    );

    test(
      'both hard-link orders preserve the winning inode and private loser',
      () async {
        await _withHarness((harness) async {
          final childWinner = await harness.run(
            mode: 'gated-success',
            // Must exceed the child's setup+symbol-preflight anchor-tick
            // pacing floor (P9-050 Amendment 5) or the watchdog wins first.
            timeoutValue: '12',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForLog('command-started', process: process);
              await run.recordDescendants(process.pid);
              expect(
                Process.killPid(process.pid, ProcessSignal.sigstop),
                isTrue,
              );
              try {
                await run.commandGate.create();
                await run.waitForOwnedFile('outcome', process: process);
                await run.waitForOwnedFile(
                  'watchdog.candidate',
                  process: process,
                );
                await run.waitForOwnedNonEmptyFile(
                  'watchdog.ln.stderr',
                  process: process,
                );
              } finally {
                Process.killPid(process.pid, ProcessSignal.sigcont);
              }
            },
          );
          expect(childWinner.exitCode, 0);
          final childCandidate = _fsRecord(
            childWinner.trace,
            'child.candidate',
          );
          final childOutcome = _fsRecord(childWinner.trace, 'outcome');
          expect(childCandidate['inode'], childOutcome['inode']);
          expect(childOutcome['line'], 'child:0');
          final losingWatchdog = _fsRecord(
            childWinner.trace,
            'watchdog.candidate',
          );
          expect(losingWatchdog, isNotEmpty);
          expect(losingWatchdog['inode'], isNot(childOutcome['inode']));
          expect(_linkStderrSize(childWinner.trace, 'child.ln.stderr'), 0);
          expect(
            _linkStderrSize(childWinner.trace, 'watchdog.ln.stderr'),
            greaterThan(0),
          );
          expect(childWinner.stderr, 'fixture gated stderr\n');
          await harness.expectNoTempOwnersOrFixtureSurvivors(childWinner);

          final watchdogWinner = await harness.run(
            mode: 'race-late127',
            timeoutValue: '3',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForLog('descendant-started', process: process);
              await run.recordDescendants(process.pid);
              expect(
                Process.killPid(process.pid, ProcessSignal.sigstop),
                isTrue,
              );
              try {
                await run.waitForOwnedFile(
                  'watchdog.candidate',
                  process: process,
                );
                await run.waitForOwnedFile('child.candidate', process: process);
                await run.waitForOwnedNonEmptyFile(
                  'child.ln.stderr',
                  process: process,
                );
              } finally {
                Process.killPid(process.pid, ProcessSignal.sigcont);
              }
            },
          );
          expect(watchdogWinner.exitCode, 124);
          final watchdogCandidate = _fsRecord(
            watchdogWinner.trace,
            'watchdog.candidate',
          );
          final watchdogOutcome = _fsRecord(watchdogWinner.trace, 'outcome');
          expect(watchdogCandidate['inode'], watchdogOutcome['inode']);
          expect(watchdogOutcome['line'], 'timeout');
          final losingChild = _fsRecord(
            watchdogWinner.trace,
            'child.candidate',
          );
          expect(losingChild, isNotEmpty);
          expect(losingChild['inode'], isNot(watchdogOutcome['inode']));
          expect(
            _linkStderrSize(watchdogWinner.trace, 'child.ln.stderr'),
            greaterThan(0),
          );
          expect(
            watchdogWinner.stderr,
            'fixture race-late127 stderr\n${_timeoutDiagnosticFor(3)}',
          );
          await harness.expectNoTempOwnersOrFixtureSurvivors(watchdogWinner);
        });
      },
    );

    test(
      'child and watchdog post-claim holds are bounded and consumed once',
      () async {
        await _withHarness((harness) async {
          final childClaim = await harness.run(mode: 'success');
          expect(childClaim.exitCode, 0);
          expect(_traceCount(childClaim.trace, '|held|child|'), 1);
          expect(_traceCount(childClaim.trace, '|wait_consumed|child|'), 1);
          expect(_traceCount(childClaim.trace, '|wait_consumed|watchdog|'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(childClaim);

          final watchdogClaim = await harness.run(
            mode: 'stubborn',
            timeoutValue: '2',
            parentDeadline: const Duration(seconds: 12),
          );
          expect(watchdogClaim.exitCode, 124);
          expect(_traceCount(watchdogClaim.trace, '|held|watchdog|'), 1);
          expect(_traceCount(watchdogClaim.trace, '|wait_consumed|child|'), 1);
          expect(
            _traceCount(watchdogClaim.trace, '|wait_consumed|watchdog|'),
            1,
          );
          await harness.expectNoTempOwnersOrFixtureSurvivors(watchdogClaim);
        });
      },
    );

    test(
      'accepted identity mismatch freezes and eventually leaves no survivor',
      () async {
        await _withHarness(fakePsMode: 'mismatch-child', (harness) async {
          final result = await harness.run(
            mode: 'success',
            timeoutValue: '20',
            // Identity freezes before any cleanup signal, so the anchor owns
            // its full 30-slot self-exit rather than the signalled fast path.
            parentDeadline: const Duration(seconds: 40),
            streamDeadline: const Duration(seconds: 45),
            afterStart: (process, run) async {
              await run.waitForLog('command-started', process: process);
              await run.recordDescendants(process.pid);
            },
          );
          await harness.waitForAssertionPidsToExit(
            result,
            const Duration(seconds: 35),
          );
          expect(result.exitCode, 1);
          expect(_traceCount(result.trace, '|action|child|frozen|'), 1);
          expect(result.trace, isNot(contains('|action|child|release|')));
          expect(result.trace, isNot(contains('|signal|child|')));
          expect(harness.tempOwners, hasLength(1));
          await harness.expectNoOwnedSurvivors(result);
        });
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'timeout diagnostic precedes visible command TERM-handler stderr',
      () async {
        await _withHarness((harness) async {
          final result = await harness.run(
            mode: 'stubborn-visible-term',
            timeoutValue: '4',
            parentDeadline: const Duration(seconds: 12),
            afterStart: (process, run) async {
              await run.waitForLog('descendant-started', process: process);
              await run.recordDescendants(process.pid);
            },
          );
          expect(result.exitCode, 124);
          expect(result.stdout, 'fixture visible stdout\n');
          expect(
            result.stderr,
            'fixture visible stderr\n'
            '${_timeoutDiagnosticFor(4)}'
            'fixture TERM handler stderr\n',
          );
          expect(_traceCount(result.trace, '|signal|child|TERM|'), 1);
          expect(_traceCount(result.trace, '|action|child|final_kill|'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );

    test(
      'unexpected EXIT and cleanup re-entry preserve the selected status',
      () async {
        await _withHarness((harness) async {
          final unexpected = await harness.run(
            mode: 'stubborn',
            timeoutValue: '20',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForLog('descendant-started', process: process);
              await run.recordDescendants(process.pid);
              expect(
                Process.killPid(process.pid, ProcessSignal.sighup),
                isTrue,
              );
            },
          );
          expect(unexpected.exitCode, 129);
          expect(
            _traceCount(unexpected.trace, '|cause|protocol|status=129'),
            1,
          );
          expect(_traceCount(unexpected.trace, '|cleanup|start|'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(unexpected);

          final reentry = await harness.run(
            mode: 'nonzero',
            fakeRmMode: 'signal-final-term',
            parentDeadline: const Duration(seconds: 16),
          );
          expect(reentry.exitCode, 23);
          expect(reentry.stdout, 'fixture nonzero stdout\n');
          expect(reentry.stderr, 'fixture nonzero stderr\n');
          expect(_traceCount(reentry.trace, '|cause|child|status=23'), 1);
          expect(_traceCount(reentry.trace, 'INJECT|final_rm|TERM'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(reentry);
        });
      },
    );

    test(
      'cleanup failure under inherited errexit preserves nonzero causes',
      () async {
        await _withHarness((harness) async {
          final success = await harness.run(
            mode: 'success',
            bashArguments: const ['-e'],
            fakeRmMode: 'fail-final',
            parentDeadline: const Duration(seconds: 16),
          );
          expect(success.exitCode, 1);
          expect(success.stderr, contains('retained temporary directory:'));
          expect(_traceCount(success.trace, '|cause|child|status=0'), 1);
          await harness.expectNoOwnedSurvivors(success);

          final nonzero = await harness.run(
            mode: 'nonzero',
            bashArguments: const ['-e'],
            fakeRmMode: 'fail-final',
            parentDeadline: const Duration(seconds: 16),
          );
          expect(nonzero.exitCode, 23);
          expect(nonzero.stderr, contains('retained temporary directory:'));
          expect(_traceCount(nonzero.trace, '|cause|child|status=23'), 1);
          await harness.expectNoOwnedSurvivors(nonzero);
        });
      },
    );

    test(
      'Bash interrupted wait is not terminal consumption; cached wait is',
      () async {
        final bashPaths = <String>{
          File('/bin/bash').resolveSymbolicLinksSync(),
          File(await _executablePath('bash')).resolveSymbolicLinksSync(),
        };
        for (final bashPath in bashPaths) {
          final probe = await _runInterruptedWaitProbe(bashPath);
          expect(probe.exitCode, 0, reason: bashPath);
          expect(probe.stderr, isEmpty, reason: bashPath);
          expect(
            probe.stdout,
            'attempt\n'
            'handled\n'
            'interrupted=143\n'
            'present_after_interrupt=true\n'
            'absent\n'
            'cached=23\n',
            reason: bashPath,
          );
        }
      },
    );

    test(
      'kills rather than releases a verified stopped child anchor',
      () async {
        await _withHarness((harness) async {
          final result = await harness.run(
            mode: 'success',
            parentDeadline: const Duration(seconds: 12),
            afterStart: (process, run) async {
              await run.waitForOwnedFile('child.anchor-held', process: process);
              final pgid = await run.commandPgid(process: process);
              run.recordOwnedPid(pgid);
              expect(Process.killPid(pgid, ProcessSignal.sigstop), isTrue);
              await run.waitForProcessState(pgid, 'T', process: process);
            },
          );

          expect(result.exitCode, 0);
          expect(result.stdout, 'fixture stdout\n');
          expect(result.stderr, 'fixture stderr\n');
          expect(_traceCount(result.trace, '|action|child|final_kill|'), 1);
          expect(_traceCount(result.trace, '|action|child|release|'), 0);
          expect(_traceCount(result.trace, '|signal|child|KILL|'), 1);
          expect(_signalsAfterAction(result.trace, 'child'), isEmpty);
          expect(_traceCount(result.trace, '|pid_absent|child|'), 1);
          expect(_traceCount(result.trace, '|wait_consumed|child|'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );

    test(
      'kills rather than releases a verified stopped watchdog anchor',
      () async {
        await _withHarness((harness) async {
          final result = await harness.run(
            mode: 'success',
            parentDeadline: const Duration(seconds: 12),
            afterStart: (process, run) async {
              await run.waitForOwnedFile(
                'watchdog.anchor-held',
                process: process,
              );
              final childPgid = await run.commandPgid(process: process);
              final leaders = await run.directGroupLeaders(process.pid);
              final watchdog = leaders.singleWhere(
                (pid) => pid != childPgid,
                orElse: () => -1,
              );
              expect(watchdog, greaterThan(0));
              run.recordOwnedPid(watchdog);
              expect(Process.killPid(watchdog, ProcessSignal.sigstop), isTrue);
              await run.waitForProcessState(watchdog, 'T', process: process);
            },
          );

          expect(result.exitCode, 0);
          expect(result.stdout, 'fixture stdout\n');
          expect(result.stderr, 'fixture stderr\n');
          expect(_traceCount(result.trace, '|action|watchdog|final_kill|'), 1);
          expect(_traceCount(result.trace, '|action|watchdog|release|'), 0);
          expect(_traceCount(result.trace, '|signal|watchdog|KILL|'), 1);
          expect(_signalsAfterAction(result.trace, 'watchdog'), isEmpty);
          expect(_traceCount(result.trace, '|pid_absent|watchdog|'), 1);
          expect(_traceCount(result.trace, '|wait_consumed|watchdog|'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );

    test('supports two disjoint concurrent successful supervisors', () async {
      final first = await _Harness.create();
      final second = await _Harness.create();
      try {
        final results = await Future.wait([
          first.run(mode: 'success'),
          second.run(mode: 'success'),
        ]);
        expect(results.map((result) => result.exitCode), everyElement(0));
        await first.expectNoTempOwnersOrFixtureSurvivors(results[0]);
        await second.expectNoTempOwnersOrFixtureSurvivors(results[1]);
      } finally {
        await first.dispose();
        await second.dispose();
      }
    });

    test('source keeps signal, descriptor, and command boundaries closed', () {
      final source = File(_scriptPath).readAsStringSync();

      expect(source, contains('exec 3>&2'));
      expect(source, contains('exec 2>/dev/null'));
      expect(source, contains('2>&3 3>&-'));
      expect(source, contains('exec 3>&-'));
      expect(source, isNot(contains('exec go')));
      expect(source, contains('[[ ! -x /bin/ln || ! -x /bin/sleep ]]'));

      for (final forbidden in <String>[
        'kill -0',
        'wait -n',
        r'$PPID',
        'USR1',
        'pkill',
        'killall',
        'eval ',
        r'$SECONDS',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }

      final killLines = const LineSplitter()
          .convert(source)
          .where((line) => RegExp(r'(^|\s)kill\s').hasMatch(line))
          .map((line) => line.trim())
          .toList();
      expect(
        killLines,
        const <String>[
          r'if ! kill "-$signal_name" -- "-$pgid" 3>&-; then',
          r'if ! kill -KILL -- "-$pgid" 3>&-; then',
        ],
        reason:
            'every signal command must be an enumerated accepted-group site',
      );

      expect(source, isNot(contains('trap - INT TERM')));
      expect(source, isNot(contains('trap - EXIT INT TERM')));
      final afterTrapInstall = source.substring(
        source.indexOf('trap unexpected_exit EXIT'),
      );
      expect(
        RegExp(
          r'^\s*(cause|causal_status)=',
          multiLine: true,
        ).allMatches(afterTrapInstall),
        isEmpty,
        reason: 'post-trap cause selection must use the atomic commit helper',
      );
      expect(
        RegExp(
          r'^\s*(cause|causal_status)=',
          multiLine: true,
        ).allMatches(source),
        isEmpty,
      );
      expect(
        RegExp(
          r'^\s*cause_record=',
          multiLine: true,
        ).allMatches(source).map((match) => match.group(0)).length,
        2,
        reason: 'one initialization plus one atomic cause commit are allowed',
      );

      final signalBody = _shellFunction(source, 'send_group_signal');
      expect(
        signalBody.indexOf('anchor_identity_is_live'),
        lessThan(signalBody.indexOf(r'kill "-$signal_name"')),
      );
      expect(
        signalBody.indexOf('trace_event "signal|'),
        lessThan(signalBody.indexOf(r'kill "-$signal_name"')),
      );
      final actionBody = _shellFunction(source, 'choose_final_anchor_action');
      expect(
        actionBody.indexOf('snapshot_group'),
        lessThan(actionBody.indexOf('kill -KILL')),
      );
      expect(
        actionBody.indexOf('kill -KILL'),
        lessThan(actionBody.indexOf('final_kill_attempted')),
      );
      expect(_occurrences(actionBody, r': >"$release"'), 1);
      expect(_occurrences(source, r'wait "$pid"'), 2);
      expect(source, contains('trace_event "pid_absent|'));
      expect(source, contains('trace_event "wait_consumed|'));
      expect(source, contains(r'expected_path="/$TMP_BASENAME"'));
    });
  }, timeout: const Timeout(Duration(minutes: 8)));

  group('P9-042 nonspinning anchor hold', () {
    test('source freezes the FIFO/read/state topology', () {
      final source = File(_scriptPath).readAsStringSync();

      expect(RegExp(r'\bSECONDS\b').hasMatch(source), isFalse);
      expect(source.indexOf('exec 8>&-'), greaterThanOrEqualTo(0));
      expect(source.indexOf('exec 9>&-'), greaterThanOrEqualTo(0));
      expect(
        source.indexOf('exec 8>&-'),
        lessThan(source.indexOf('parse_timeout')),
      );
      expect(
        source.indexOf('exec 9>&-'),
        lessThan(source.indexOf('parse_timeout')),
      );
      expect(
        source,
        contains(
          'for required_tool in go pkg-config uname tr mktemp mkdir rm ps stat mkfifo',
        ),
      );
      expect(source, contains('readonly MKFIFO_TOOL'));
      expect(_occurrences(source, r'"$MKFIFO_TOOL" -m 600'), 2);

      final hold = _shellFunction(source, 'hold_anchor_fifo');
      expect(hold, contains(r'IFS= read -r -t 1 -u "$fd" value'));
      expect(hold, isNot(contains('/bin/sleep')));
      expect(hold, isNot(contains('date ')));
      expect(hold, isNot(contains('SECONDS')));
      expect(hold, contains(r'[[ "$slot" -lt 30 ]]'));
      expect(hold, contains('result=unexpected-data'));
      expect(hold, contains('ceiling|slot=30'));

      final failureHold = _shellFunction(source, 'hold_failed_anchor');
      expect(failureHold, contains("trap '' INT TERM HUP"));
      expect(failureHold, contains('/bin/sleep 30 3>&- 8>&- 9>&-'));
      expect(_occurrences(failureHold, '/bin/sleep 30'), 1);
      expect(failureHold, isNot(contains('while ')));

      final transitions = _shellFunction(source, 'transition_fifo_setup');
      for (final transition in <String>[
        'unstarted:waiting_deadline',
        'waiting_deadline:deadline_owned',
        'deadline_owned:setup_running',
        'setup_running:setup_held',
        'setup_held:authorized',
        'authorized:child_closed',
        'unstarted:failed',
        'waiting_deadline:failed',
        'deadline_owned:failed',
        'setup_running:failed',
        'setup_held:failed',
        'authorized:failed',
      ]) {
        expect(transitions, contains(transition), reason: transition);
      }
      expect(transitions, isNot(contains('child_closed:')));
      expect(transitions, isNot(contains('failed:')));
    });

    test('normal setup is ordered, private, and traced', () async {
      await _withHarness((harness) async {
        FileSystemEntityType? childType;
        FileSystemEntityType? watchdogType;
        final result = await harness.run(
          mode: 'success',
          afterStart: (process, run) async {
            await run.waitForLog('command-started', process: process);
            final owner = run.activeTempOwner;
            childType = FileSystemEntity.typeSync(
              '${owner.path}/child.anchor-control.fifo',
              followLinks: false,
            );
            watchdogType = FileSystemEntity.typeSync(
              '${owner.path}/watchdog.anchor-control.fifo',
              followLinks: false,
            );
          },
        );

        expect(result.exitCode, 0, reason: result.stderr);
        expect(childType, FileSystemEntityType.pipe);
        expect(watchdogType, FileSystemEntityType.pipe);
        final mkfifoRows = const LineSplitter()
            .convert(result.log)
            .where((line) => line.startsWith('mkfifo-invoked|'))
            .toList();
        expect(mkfifoRows, hasLength(2), reason: result.log);
        expect(mkfifoRows[0], contains('|watchdog|'));
        expect(mkfifoRows[1], contains('|child|'));
        final childPgid = const LineSplitter()
            .convert(result.log)
            .firstWhere((line) => line.startsWith('command-started|'))
            .split('|')[2];
        expect(mkfifoRows, everyElement(contains('|$childPgid|')));
        expect(result.log, contains('fixed-fds|'));
        expect(result.log, contains('fd8=closed,fd9=closed'));
        expect(
          result.trace,
          contains('|fifo_state|unstarted|waiting_deadline'),
        );
        expect(result.trace, contains('|fifo_state|authorized|child_closed'));
        expect(result.trace, contains('|fifo|child|setup-opened|fd=8'));
        expect(result.trace, contains('|fifo|child|setup-closed|fd=8'));
        expect(result.trace, contains('|fifo|child|post-opened|fd=8'));
        expect(result.trace, contains('|fifo|child|post-closed|fd=8'));
        expect(result.trace, contains('|fifo|watchdog|post-opened|fd=9'));
        expect(result.trace, contains('|fifo|watchdog|post-closed|fd=9'));
        await harness.expectNoTempOwnersOrFixtureSurvivors(result);
      });
    });

    test('ordinary delayed cleanup stays below the CPU ceiling', () async {
      final source = File(_scriptPath).readAsStringSync();
      final bashPaths = <String>{
        File('/bin/bash').resolveSymbolicLinksSync(),
        File(await _executablePath('bash')).resolveSymbolicLinksSync(),
      };
      for (final bashPath in bashPaths) {
        final result = await _runAnchorHoldCpuProbe(source, bashPath);
        expect(result.exitCode, 0, reason: result.stderr);
        expect(result.stdout, 'released\n');
        expect(
          result.wall.inMilliseconds,
          inInclusiveRange(2500, 5000),
          reason: '$bashPath\n${result.stderr}',
        );
        expect(
          _cpuUsageSeconds(result.stderr),
          lessThanOrEqualTo(0.25),
          reason: '$bashPath\n${result.stderr}',
        );
      }
    });
  });

  group('P9-042 fake ps uses owned events', () {
    test('setup and accepted-child mismatch selection is not ordinal', () {
      final source = File('$_fixtureDirectory/fake_ps.sh').readAsStringSync();

      expect(source, contains('fifo.setup-held'));
      expect(source, contains('child.anchor-held'));
      expect(source, contains('watchdog.anchor-held'));
      expect(source, contains(r'command-started\|'));
      expect(source, isNot(contains(r'"$count" -ge 4')));
      final postSelector = _shellFunction(source, 'select_post_target');
      expect(postSelector, contains('supervisor.shell.stderr'));
      expect(postSelector, contains(r'TRACE\|signal\|"$label"\|TERM\|pgid=*'));
      expect(postSelector, contains(r'[[ "$signal_rows" -eq 1 ]]'));
      expect(postSelector, contains(r'[[ "$anchor_rows" -eq 1'));
      expect(postSelector, contains(r'"$members" -eq 1 ]]'));

      final wrapper = File(_scriptPath).readAsStringSync();
      for (final label in <String>['child', 'watchdog']) {
        final start = wrapper.indexOf(
          label == 'child'
              ? r'if [[ ! -p "$child_anchor_fifo"'
              : r'if [[ ! -p "$watchdog_anchor_fifo"',
        );
        final end = wrapper.indexOf('\n) &\n${label}_pid=', start);
        expect(start, greaterThanOrEqualTo(0), reason: '$label post start');
        expect(end, greaterThan(start), reason: '$label post end');
        final postBranch = wrapper.substring(start, end);
        expect(postBranch, isNot(contains('commit_cause')));
        expect(postBranch, isNot(contains('owned_diagnostic')));
        expect(postBranch, isNot(contains('cause_record=')));
      }
    });

    test('setup snapshot selector requires setup-held transition', () {
      final source = File('$_fixtureDirectory/fake_ps.sh').readAsStringSync();
      final predicate = _shellFunction(source, 'setup_transition_is_latest');
      expect(predicate, contains('supervisor.shell.stderr'));
      expect(predicate, contains(r'TRACE\|fifo_state\|*'));
      expect(
        predicate,
        contains("'TRACE|fifo_state|setup_running|setup_held'"),
      );
      expect(
        predicate,
        contains(r'[[ -f "$trace_file" && ! -L "$trace_file" ]]'),
      );
      final claim = source.indexOf('setup_transition_is_latest; then');
      final gate = source.indexOf(r': >"$setup_gate_once"', claim);
      final snapshot = source.indexOf(r'snapshot="$($real_ps "$@")"', gate);
      expect(claim, greaterThanOrEqualTo(0));
      expect(gate, greaterThan(claim));
      expect(snapshot, greaterThan(gate));
      expect(_occurrences(source, r': >"$setup_gate_once"'), 1);
      final setupBranch = source.substring(
        claim,
        source.indexOf('\nidentity_snapshot=', snapshot),
      );
      expect(setupBranch, isNot(contains(r'$count')));
    });
  });

  group('P9-042 setup identity fence', () {
    test(
      'sole identity authorizes but mismatch and nonsole withhold Go',
      () async {
        await _withHarness((harness) async {
          String? controlPayload;
          final control = await harness.run(
            mode: 'success',
            runFakePsMode: 'passthrough',
            gateSetupSnapshot: true,
            afterStart: (process, run) async {
              final identity = await run.waitForSetupSnapshotIdentity(
                process: process,
              );
              _expectSetupIdentityMatchesMkfifoRows(run, identity);
              expect(run.setupGateOnce.existsSync(), isTrue);
              controlPayload = run.setupSnapshotMarker
                  .readAsStringSync()
                  .trim();
              await run.releaseSetupSnapshot();
            },
          );
          expect(control.exitCode, 0, reason: control.trace);
          expect(
            _occurrences(control.trace, 'MARKER|fifo.setup-authorized|'),
            1,
          );
          expect(_occurrences(control.trace, 'MARKER|fifo.setup-closed|'), 1);
          expect(
            controlPayload,
            matches(RegExp(r'^[1-9][0-9]*\|[1-9][0-9]*\|setup-held$')),
          );
          expect(
            control.trace.indexOf('|fifo_state|setup_running|setup_held'),
            lessThan(
              control.trace.indexOf('|fifo_state|setup_held|authorized'),
            ),
          );
          expect(
            control.trace.indexOf('|fifo_state|setup_held|authorized'),
            lessThan(
              control.trace.indexOf('|fifo_state|authorized|child_closed'),
            ),
          );
          expect(control.log, contains('command-started'));
          await harness.expectNoTempOwnersOrFixtureSurvivors(control);

          for (final mode in <String>['setup-mismatch', 'setup-nonsole']) {
            final result = await harness.run(
              mode: 'success',
              runFakePsMode: mode,
              gateSetupSnapshot: true,
              parentDeadline: const Duration(seconds: 14),
              afterStart: (process, run) async {
                final identity = await run.waitForSetupSnapshotIdentity(
                  process: process,
                );
                expect(identity.$1, greaterThan(0));
                expect(identity.$2, greaterThan(0));
                _expectSetupIdentityMatchesMkfifoRows(run, identity);
                expect(run.setupGateOnce.existsSync(), isTrue);
                await run.releaseSetupSnapshot();
              },
            );
            expect(result.exitCode, 1, reason: '$mode\n${result.trace}');
            expect(result.stdout, isEmpty);
            expect(
              result.stderr,
              'could not verify Go snapshot FIFO setup quiescence\n',
            );
            expect(result.log, isNot(contains('command-started')));
            expect(
              result.trace,
              isNot(contains('MARKER|fifo.setup-authorized|')),
            );
            expect(result.trace, isNot(contains('MARKER|fifo.setup-closed|')));
            expect(result.trace, contains('|fifo_state|setup_held|failed'));
            expect(
              result.trace.indexOf('|fifo_state|setup_running|setup_held'),
              lessThan(result.trace.indexOf('|fifo_state|setup_held|failed')),
            );
            expect(_traceCount(result.trace, '|wait_consumed|child|'), 1);
            await harness.expectNoTempOwnersOrFixtureSurvivors(result);
          }
        });
      },
    );
  });

  group('P9-042 post-work FIFO evidence is silent', () {
    test(
      'child and watchdog unexpected data preserve their earlier owner',
      () async {
        await _withHarness((harness) async {
          for (final entry in <(String, String, String, int, String, String)>[
            (
              'child',
              'nonzero',
              'post-child-data',
              23,
              'fixture nonzero stdout\n',
              'fixture nonzero stderr\n',
            ),
            (
              'watchdog',
              'stubborn',
              'post-watchdog-data',
              124,
              'fixture stubborn stdout\n',
              'fixture stubborn stderr\n${_timeoutDiagnosticFor(4)}',
            ),
          ]) {
            final result = await harness.run(
              mode: entry.$2,
              runFakePsMode: entry.$3,
              timeoutValue: entry.$1 == 'watchdog' ? '4' : '20',
              parentDeadline: const Duration(seconds: 16),
              gatePostWorkLabel: entry.$1,
              afterStart: (process, run) async {
                await run.waitForPostWorkSnapshot(process: process);
                await run.writeOwnedFifo(
                  '${entry.$1}.anchor-control.fifo',
                  'unexpected post data\n',
                );
                await run.waitForOwnedFile(
                  '${entry.$1}.protocol-error',
                  process: process,
                );
                await run.releasePostWorkSnapshot();
              },
            );
            expect(result.exitCode, entry.$4, reason: result.trace);
            expect(result.stdout, entry.$5);
            expect(result.stderr, entry.$6, reason: result.trace);
            _expectContiguousUnexpectedData(result.trace, entry.$1);
            expect(
              _traceCount(
                result.trace,
                '|failure_hold|${entry.$1}|phase=post|reason=unexpected-data|start',
              ),
              1,
            );
            expect(
              _traceCount(result.trace, '|action|${entry.$1}|final_kill|'),
              1,
            );
            expect(_traceCount(result.trace, '|wait_consumed|${entry.$1}|'), 1);
            await harness.expectNoTempOwnersOrFixtureSurvivors(result);
          }
        });
      },
    );

    test(
      'post-work FIFO open failures preserve child and timeout results',
      () async {
        await _withHarness((harness) async {
          final child = await harness.run(
            mode: 'gated-success',
            timeoutValue: '20',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForLog('command-started', process: process);
              await run.deleteOwnedFifo('child.anchor-control.fifo');
              await run.commandGate.create();
            },
          );
          expect(child.exitCode, 0, reason: child.trace);
          expect(child.stdout, 'fixture gated stdout\n');
          expect(child.stderr, 'fixture gated stderr\n');
          expect(child.trace, isNot(contains('|fifo|child|post-opened|')));
          expect(
            child.trace,
            contains('|failure_hold|child|phase=post|reason=open|start'),
          );
          expect(_traceCount(child.trace, '|action|child|final_kill|'), 1);
          expect(_traceCount(child.trace, '|wait_consumed|child|'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(child);

          final watchdog = await harness.run(
            mode: 'stubborn',
            timeoutValue: '4',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForLog('command-started', process: process);
              await run.deleteOwnedFifo('watchdog.anchor-control.fifo');
            },
          );
          expect(watchdog.exitCode, 124, reason: watchdog.trace);
          expect(watchdog.stdout, 'fixture stubborn stdout\n');
          expect(
            watchdog.stderr,
            'fixture stubborn stderr\n${_timeoutDiagnosticFor(4)}',
          );
          expect(
            watchdog.trace,
            isNot(contains('|fifo|watchdog|post-opened|')),
          );
          expect(
            watchdog.trace,
            contains('|failure_hold|watchdog|phase=post|reason=open|start'),
          );
          expect(
            _traceCount(watchdog.trace, '|action|watchdog|final_kill|'),
            1,
          );
          expect(_traceCount(watchdog.trace, '|wait_consumed|watchdog|'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(watchdog);
        });
      },
    );

    Future<void> expectRetainedCeiling({
      required String label,
      required String mode,
      required String fakePsMode,
      required String timeoutValue,
      required int exitCode,
      required String stdout,
      required String stderrBeforeRetention,
    }) async {
      await _withHarness((harness) async {
        Directory? retainedOwner;
        var anchorPid = -1;
        final elapsed = Stopwatch()..start();
        final result = await harness.run(
          mode: mode,
          runFakePsMode: fakePsMode,
          timeoutValue: timeoutValue,
          parentDeadline: const Duration(seconds: 16),
          streamDeadline: const Duration(seconds: 4),
          gatePostWorkLabel: label,
          afterStart: (process, run) async {
            await run.waitForPostWorkSnapshot(process: process);
            retainedOwner = run.activeTempOwner;
            await run.releasePostWorkSnapshot();
            anchorPid = await run.waitForPostWorkSelection(process: process);
            run.recordOwnedPid(anchorPid);
          },
        );
        elapsed.stop();

        final owner = retainedOwner!;
        final retainedLine =
            'cleanup could not prove terminal consumption; '
            'retained temporary directory: ${owner.path}\n';
        expect(result.exitCode, exitCode, reason: result.trace);
        expect(result.stdout, stdout);
        expect(
          result.stderr,
          '$stderrBeforeRetention$retainedLine'
          'Go snapshot cleanup did not complete safely.\n',
          reason: result.trace,
        );
        expect(elapsed.elapsed, lessThan(const Duration(seconds: 20)));
        expect(owner.existsSync(), isTrue);
        expect(_traceCount(result.trace, '|action|$label|frozen|'), 1);
        expect(
          result.trace,
          contains('|action|$label|frozen|pid=$anchorPid|pgid=$anchorPid'),
        );
        expect(result.trace, isNot(contains('|action|$label|release|')));
        expect(_signalsAfterAction(result.trace, label), isEmpty);
        expect(_traceCount(result.trace, '|wait_cached|$label|'), 0);
        expect(_traceCount(result.trace, '|wait_consumed|$label|'), 0);

        await harness.waitForAssertionPidsToExit(
          result,
          const Duration(seconds: 35),
        );
        expect(await _pidExists(anchorPid), isFalse);
        final privateTrace = File(
          '${owner.path}/$label.shell.stderr',
        ).readAsStringSync();
        expect(
          _traceCount(privateTrace, '|anchor_tick|$label|phase=post|'),
          30,
        );
        expect(
          _traceCount(privateTrace, '|hold|$label|phase=post|ceiling|slot=30'),
          1,
        );
        expect(_traceCount(privateTrace, '|fifo|$label|post-closed|'), 1);
        expect(
          privateTrace,
          isNot(contains('|failure_hold|$label|phase=post|')),
        );
        expect(owner.existsSync(), isTrue);
        await owner.delete(recursive: true);
        expect(harness.tempOwners, isEmpty);
        for (final pid in result.assertionPids) {
          expect(await _pidExists(pid), isFalse, reason: 'PID $pid survived');
        }
      });
    }

    test(
      'post-work ceilings retain owner until bounded self-exit: child',
      () => expectRetainedCeiling(
        label: 'child',
        mode: 'nonzero',
        fakePsMode: 'post-child-ceiling',
        timeoutValue: '20',
        exitCode: 23,
        stdout: 'fixture nonzero stdout\n',
        stderrBeforeRetention: 'fixture nonzero stderr\n',
      ),
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'post-work ceilings retain owner until bounded self-exit: watchdog',
      () => expectRetainedCeiling(
        label: 'watchdog',
        mode: 'stubborn',
        fakePsMode: 'post-watchdog-ceiling',
        timeoutValue: '4',
        exitCode: 124,
        stdout: 'fixture stubborn stdout\n',
        stderrBeforeRetention:
            'fixture stubborn stderr\n${_timeoutDiagnosticFor(4)}',
      ),
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test('first INT remains owner after child post-work data', () async {
      await _withHarness((harness) async {
        final result = await harness.run(
          mode: 'gated-success',
          runFakePsMode: 'post-child-data',
          timeoutValue: '20',
          parentDeadline: const Duration(seconds: 16),
          gatePostWorkLabel: 'child',
          afterStart: (process, run) async {
            await run.waitForLog('command-started', process: process);
            expect(Process.killPid(process.pid, ProcessSignal.sigint), isTrue);
            await run.waitForPostWorkSnapshot(process: process);
            await run.writeOwnedFifo(
              'child.anchor-control.fifo',
              'unexpected signal-owned post data\n',
            );
            await run.waitForOwnedFile(
              'child.protocol-error',
              process: process,
            );
            await run.releasePostWorkSnapshot();
          },
        );
        expect(result.exitCode, 130, reason: result.trace);
        expect(result.stdout, isEmpty);
        expect(result.stderr, isEmpty);
        expect(_traceCount(result.trace, '|cause|signal|status=130'), 1);
        _expectContiguousUnexpectedData(result.trace, 'child');
        expect(_traceCount(result.trace, '|action|child|final_kill|'), 1);
        expect(_traceCount(result.trace, '|wait_consumed|child|'), 1);
        await harness.expectNoTempOwnersOrFixtureSurvivors(result);
      });
    });
  });

  group('P9-042 signal after authorization aborts child', () {
    test(
      'release wins over authorization at the next child boundary',
      () async {
        await _withHarness((harness) async {
          var sawAuthorization = false;
          var sawRelease = false;
          final result = await harness.run(
            mode: 'success',
            runFakePsMode: 'setup-abort-boundary',
            timeoutValue: '20',
            gateSetupSnapshot: true,
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              final identity = await run.waitForSetupSnapshotIdentity(
                process: process,
              );
              run.recordOwnedPid(identity.$1);
              expect(
                Process.killPid(identity.$1, ProcessSignal.sigstop),
                isTrue,
              );
              await run.waitForProcessState(identity.$1, 'T', process: process);
              await run.releaseSetupSnapshot();
              await run.waitForOwnedFile(
                'fifo.setup-authorized',
                process: process,
              );
              final owner = run.activeTempOwner;
              sawAuthorization =
                  FileSystemEntity.typeSync(
                    '${owner.path}/fifo.setup-authorized',
                    followLinks: false,
                  ) ==
                  FileSystemEntityType.file;
              expect(
                Process.killPid(process.pid, ProcessSignal.sigint),
                isTrue,
              );
              await run.waitForOwnedFile('child.release', process: process);
              sawRelease =
                  FileSystemEntity.typeSync(
                    '${owner.path}/child.release',
                    followLinks: false,
                  ) ==
                  FileSystemEntityType.file;
              await run.waitForProcessState(identity.$1, 'T', process: process);
              expect(
                Process.killPid(identity.$1, ProcessSignal.sigcont),
                isTrue,
              );
            },
          );
          expect(result.exitCode, 130, reason: result.trace);
          expect(result.stdout, isEmpty);
          expect(result.stderr, isEmpty);
          expect(
            _occurrences(result.trace, 'MARKER|fifo.setup-authorized|'),
            1,
          );
          expect(sawAuthorization, isTrue);
          expect(sawRelease, isTrue);
          expect(result.trace, contains('|hold|child|phase=setup|aborted|'));
          expect(result.trace, contains('|fifo|child|setup-closed|fd=8'));
          expect(result.trace, isNot(contains('MARKER|fifo.setup-closed|')));
          expect(result.log, isNot(contains('command-started')));
          expect(_traceCount(result.trace, '|wait_consumed|child|'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );
  });

  group('FIFO setup is fail-closed', () {
    test('mkfifo is mandatory before temp or anchor acquisition', () async {
      await _withHarness((harness) async {
        final result = await harness.run(
          mode: 'success',
          missingTool: 'mkfifo',
        );
        expect(result.exitCode, 1);
        expect(result.stdout, isEmpty);
        expect(result.stderr, 'missing required Go snapshot tool: mkfifo\n');
        expect(result.log, isEmpty);
        expect(harness.tempEntries, isEmpty);
        await harness.expectNoOwnedSurvivors(result);
      });
    });

    test('preexisting private state is rejected before anchors', () async {
      await _withHarness((harness) async {
        final result = await harness.run(
          mode: 'success',
          fakeMktempMode: 'preexisting-fifo-state',
        );
        expect(result.exitCode, 1);
        expect(result.stdout, isEmpty);
        expect(result.stderr, 'invalid Go snapshot private FIFO setup state\n');
        expect(result.log, isEmpty);
        await harness.expectNoTempOwnersOrFixtureSurvivors(result);
      });
    });

    test(
      'tool failures and invalid outputs stop before Go',
      () async {
        await _withHarness((harness) async {
          final cases = <(String, String, String)>[
            (
              'fail',
              'watchdog',
              'could not create Go snapshot watchdog anchor FIFO\n',
            ),
            (
              'no-create',
              'watchdog',
              'invalid Go snapshot watchdog anchor FIFO\n',
            ),
            (
              'regular-file',
              'watchdog',
              'invalid Go snapshot watchdog anchor FIFO\n',
            ),
            (
              'symlink',
              'watchdog',
              'invalid Go snapshot watchdog anchor FIFO\n',
            ),
            (
              'public-mode',
              'watchdog',
              'invalid Go snapshot watchdog anchor FIFO\n',
            ),
            (
              'wrong-path',
              'watchdog',
              'invalid Go snapshot watchdog anchor FIFO\n',
            ),
            (
              'success-output',
              'watchdog',
              'invalid Go snapshot watchdog anchor FIFO\n',
            ),
            (
              'fail',
              'child',
              'could not create Go snapshot child anchor FIFO\n',
            ),
          ];
          for (final testCase in cases) {
            final result = await harness.run(
              mode: 'success',
              fakeMkfifoMode: testCase.$1,
              fakeMkfifoApplyTo: testCase.$2,
              parentDeadline: const Duration(seconds: 14),
            );
            expect(result.exitCode, 1, reason: '${testCase.$1}:${testCase.$2}');
            expect(result.stdout, isEmpty);
            expect(
              result.stderr,
              testCase.$3,
              reason: '${testCase.$1}:${testCase.$2}\n${result.trace}',
            );
            expect(result.stderr, isNot(contains('fake mkfifo')));
            expect(result.log, isNot(contains('command-started')));
            final calls = _occurrences(result.log, 'mkfifo-invoked|');
            expect(calls, testCase.$2 == 'child' ? 2 : 1);
            if (testCase.$1 == 'wrong-path') {
              expect(
                File(
                  '${harness.sandbox.path}/outside-fifo-${harness._runSequence}',
                ).existsSync(),
                isTrue,
              );
            }
            await harness.expectNoTempOwnersOrFixtureSurvivors(result);
          }
        });
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'hung and returned descendants remain owned by the child group',
      () async {
        await _withHarness((harness) async {
          for (final mode in <String>['hang', 'fork-hang', 'fork-return']) {
            final result = await harness.run(
              mode: 'success',
              fakeMkfifoMode: mode,
              // Below the file's established minimum (P9-050 Amendment 5)
              // loses the live-member snapshot race before fifo_setup_begin.
              timeoutValue: '4',
              parentDeadline: const Duration(seconds: 14),
            );
            expect(result.exitCode, mode == 'fork-return' ? 1 : 124);
            expect(result.log, isNot(contains('command-started')));
            if (mode == 'fork-return') {
              expect(
                result.stderr,
                'could not verify Go snapshot FIFO setup quiescence\n',
              );
            } else {
              expect(result.stderr, _timeoutDiagnosticFor(4));
            }
            await harness.expectNoTempOwnersOrFixtureSurvivors(result);
          }
        });
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });

  group('FIFO fd is private', () {
    test('caller-open fd 8 and 9 are closed before every workload', () async {
      await _withHarness((harness) async {
        final result = await harness.run(
          mode: 'success',
          openCallerFixedFds: true,
        );
        expect(result.exitCode, 0, reason: result.stderr);
        expect(result.log, contains('fd8=closed,fd9=closed'));
        expect(result.log, isNot(contains('fd8=open')));
        expect(result.log, isNot(contains('fd9=open')));
        await harness.expectNoTempOwnersOrFixtureSurvivors(result);
      });
    });

    test('validation-to-open loss fails with one private diagnostic', () async {
      await _withHarness((harness) async {
        final result = await harness.run(
          mode: 'success',
          fakeStatMode: 'gated-child-fifo',
          parentDeadline: const Duration(seconds: 14),
          afterStart: (process, run) async {
            await run.waitForChildFifoStat(process: process);
            await File(
              '${run.activeTempOwner.path}/child.anchor-control.fifo',
            ).delete();
            await run.statRelease.create();
          },
        );
        expect(result.exitCode, 1);
        expect(result.stdout, isEmpty);
        expect(result.stderr, 'could not complete Go snapshot FIFO setup\n');
        expect(result.log, isNot(contains('command-started')));
        await harness.expectNoTempOwnersOrFixtureSurvivors(result);
      });
    });
  });

  group('FIFO authorization is fenced', () {
    test(
      'a sole child is authorized exactly once and closes before Go',
      () async {
        await _withHarness((harness) async {
          final result = await harness.run(
            mode: 'success',
            gateSetupSnapshot: true,
            afterStart: (process, run) async {
              await run.waitForSetupSnapshot(process: process);
              await run.releaseSetupSnapshot();
            },
          );
          expect(result.exitCode, 0, reason: result.stderr);
          expect(
            _occurrences(result.trace, 'MARKER|fifo.setup-authorized|'),
            1,
          );
          expect(_occurrences(result.trace, 'MARKER|fifo.setup-closed|'), 1);
          expect(result.log, contains('command-started'));
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );

    test(
      'INT and TERM published inside the snapshot gate withhold Go',
      () async {
        await _withHarness((harness) async {
          for (final signal in <ProcessSignal>[
            ProcessSignal.sigint,
            ProcessSignal.sigterm,
          ]) {
            final result = await harness.run(
              mode: 'success',
              timeoutValue: '20',
              gateSetupSnapshot: true,
              parentDeadline: const Duration(seconds: 14),
              afterStart: (process, run) async {
                await run.waitForSetupSnapshot(process: process);
                expect(Process.killPid(process.pid, signal), isTrue);
                await run.releaseSetupSnapshot();
              },
            );
            expect(result.exitCode, signal == ProcessSignal.sigint ? 130 : 143);
            expect(result.stdout, isEmpty);
            expect(result.stderr, isEmpty);
            expect(result.log, isNot(contains('command-started')));
            expect(
              result.trace,
              isNot(contains('MARKER|fifo.setup-authorized|')),
            );
            await harness.expectNoTempOwnersOrFixtureSurvivors(result);
          }
        });
      },
    );

    test(
      'timeout and FIFO data inside the snapshot gate withhold Go',
      () async {
        await _withHarness((harness) async {
          final timeout = await harness.run(
            mode: 'success',
            timeoutValue: '1',
            gateSetupSnapshot: true,
            parentDeadline: const Duration(seconds: 14),
            afterStart: (process, run) async {
              await run.waitForSetupSnapshot(process: process);
              await run.waitForOwnedFile('outcome', process: process);
              await run.releaseSetupSnapshot();
            },
          );
          expect(timeout.exitCode, 124);
          expect(timeout.stdout, isEmpty);
          expect(timeout.stderr, _timeoutDiagnostic);
          expect(timeout.log, isNot(contains('command-started')));
          expect(
            timeout.trace,
            isNot(contains('MARKER|fifo.setup-authorized|')),
          );
          await harness.expectNoTempOwnersOrFixtureSurvivors(timeout);

          final data = await harness.run(
            mode: 'success',
            timeoutValue: '20',
            gateSetupSnapshot: true,
            parentDeadline: const Duration(seconds: 14),
            afterStart: (process, run) async {
              await run.waitForSetupSnapshot(process: process);
              final sink = File(
                '${run.activeTempOwner.path}/child.anchor-control.fifo',
              ).openWrite()..write('unexpected setup data\n');
              await sink.flush();
              await sink.close();
              await run.waitForOwnedFile(
                'fifo.setup.protocol-error',
                process: process,
              );
              await run.releaseSetupSnapshot();
            },
          );
          expect(data.exitCode, 1);
          expect(data.stdout, isEmpty);
          expect(data.stderr, 'could not complete Go snapshot FIFO setup\n');
          expect(data.log, isNot(contains('command-started')));
          expect(data.trace, isNot(contains('MARKER|fifo.setup-authorized|')));
          await harness.expectNoTempOwnersOrFixtureSurvivors(data);
        });
      },
    );
  });

  group('FIFO setup diagnostics are exact', () {
    test('specific and completion diagnostics are mutually exclusive', () {
      final source = File(_scriptPath).readAsStringSync();
      for (final diagnostic in <String>[
        'missing required Go snapshot tool: mkfifo',
        'invalid Go snapshot private FIFO setup state',
        'could not create Go snapshot child anchor FIFO',
        'could not create Go snapshot watchdog anchor FIFO',
        'invalid Go snapshot child anchor FIFO',
        'invalid Go snapshot watchdog anchor FIFO',
        'could not establish Go snapshot FIFO setup deadline owner',
        'could not verify Go snapshot FIFO setup quiescence',
        'could not complete Go snapshot FIFO setup',
      ]) {
        expect(source, contains(diagnostic), reason: diagnostic);
      }
      expect(
        source,
        contains('fifo_setup_diagnostic_emitted'),
        reason: 'one supervisor selector must own setup diagnostics',
      );
    });
  });

  group('P9-043 anchored selected-artifact symbol preflight', () {
    test('the temporary C seam defines only the pending exact three', () async {
      final sandbox = await Directory.systemTemp.createTemp('p9-043-c-set.');
      try {
        final object = '${sandbox.path}/textbuffer_stubs.o';
        final compile = await Process.run('/usr/bin/clang', <String>[
          '-std=c11',
          '-c',
          'tools/parity/go_snapshot/textbuffer_stubs.c',
          '-o',
          object,
        ]);
        expect(
          compile.exitCode,
          0,
          reason: 'fixture compile failed:\n${compile.stderr}',
        );
        final inventory = await Process.run('/usr/bin/nm', <String>[
          if (Platform.isMacOS) '-gU' else ...<String>['-g', '--defined-only'],
          object,
        ]);
        expect(inventory.exitCode, 0, reason: inventory.stderr as String);
        final definitions = const LineSplitter()
            .convert(inventory.stdout as String)
            .map((line) => line.trim().split(RegExp(r'\s+')).last)
            .map(
              (symbol) => symbol.startsWith('_') ? symbol.substring(1) : symbol,
            )
            .where((symbol) => symbol.startsWith('textBuffer'))
            .toSet();
        expect(definitions, <String>{
          'textBufferConcat',
          'textBufferResize',
          'textBufferGetCapacity',
        });
      } finally {
        await sandbox.delete(recursive: true);
      }
    });

    test(
      'each pending stub is fail-fast rather than a returning no-op',
      () async {
        final sandbox = await Directory.systemTemp.createTemp('p9-043-c-call.');
        try {
          final probe = '${sandbox.path}/stub-probe';
          final compile = await Process.run('/usr/bin/clang', <String>[
            '-std=c11',
            'tools/parity/go_snapshot/textbuffer_stubs.c',
            'test/fixtures/go_snapshot/textbuffer_stub_probe.c',
            '-o',
            probe,
          ]);
          expect(
            compile.exitCode,
            0,
            reason: 'typed probe compile failed:\n${compile.stderr}',
          );
          for (final symbol in <String>[
            'textBufferConcat',
            'textBufferResize',
            'textBufferGetCapacity',
          ]) {
            final result = await Process.run(probe, <String>[symbol]);
            expect(result.exitCode, isNot(0), reason: symbol);
            expect(
              result.stderr,
              'unexpected OpenTUI parity-link stub call: $symbol\n',
              reason: symbol,
            );
          }
        } finally {
          await sandbox.delete(recursive: true);
        }
      },
      skip: File('external/opentui/packages/go/opentui.h').existsSync()
          ? false
          : 'OpenTUI submodule is not materialized in this checkout.',
    );

    test('source freezes the anchored empty-environment preflight order', () {
      final source = File(_scriptPath).readAsStringSync();
      expect(source, contains('run_child_precommands() {'));
      expect(source, contains('symbol-preflight.quiescence-authorized'));
      expect(source, contains('symbol-preflight.quiescence-closed'));
      expect(source, contains('symbol-preflight.result'));
      expect(source, contains('exec -c'));
      expect(source, contains('run_selected_artifact_symbol_preflight'));
      expect(source, contains('readonly -a symbol_nm_argv'));
      expect(source, contains('symbol_preflight_quiescence_state'));
      expect(source, isNot(contains('symbol_quiescence_processed')));
      final stateBody = _shellFunction(
        source,
        'transition_symbol_preflight_quiescence',
      );
      for (final transition in <String>[
        'not_reached:waiting_held',
        'waiting_held:snapshotting',
        'waiting_held:aborted',
        'waiting_held:protocol_failed',
        'snapshotting:authorized',
        'snapshotting:rejected',
        'snapshotting:aborted',
        'snapshotting:protocol_failed',
      ]) {
        expect(stateBody, contains(transition), reason: transition);
      }
      final childPrecommands = source.indexOf('\n  run_child_precommands\n');
      final setupClosed = source.indexOf(r': >"$fifo_setup_closed"');
      final goInvocation = source.indexOf(r'"${command[@]}" 2>&3');
      expect(setupClosed, greaterThanOrEqualTo(0));
      expect(childPrecommands, greaterThan(setupClosed));
      expect(goInvocation, greaterThan(childPrecommands));
      expect(_occurrences(source, r'! exec 8<>"$child_anchor_fifo"'), 3);
      final preflightBody = _shellFunction(
        source,
        'run_selected_artifact_symbol_preflight',
      );
      final holdCall = preflightBody.indexOf(
        'hold_anchor_fifo symbol-preflight-quiescence child 8',
      );
      final successfulClose = preflightBody.indexOf(
        '  exec 8>&-\n  close_status=\$?',
        holdCall,
      );
      final decision = preflightBody.indexOf(
        r'case "$hold_result"',
        successfulClose,
      );
      final authorized = preflightBody.indexOf('    authorized)', decision);
      final fdAbsence = preflightBody.indexOf(
        '-e /dev/fd/8 || -e /dev/fd/9',
        authorized,
      );
      final closedMarker = preflightBody.indexOf(
        r'! : >"$symbol_preflight_quiescence_closed"',
        fdAbsence,
      );
      final closedValidation = preflightBody.indexOf(
        r'! private_marker_valid "$symbol_preflight_quiescence_closed"',
        closedMarker,
      );
      final parseStart = preflightBody.indexOf(
        'symbol_preflight|parse-start',
        closedValidation,
      );
      expect(holdCall, greaterThanOrEqualTo(0));
      expect(successfulClose, greaterThan(holdCall));
      expect(decision, greaterThan(successfulClose));
      expect(authorized, greaterThan(decision));
      expect(fdAbsence, greaterThan(authorized));
      expect(closedMarker, greaterThan(fdAbsence));
      expect(closedValidation, greaterThan(closedMarker));
      expect(parseStart, greaterThan(closedValidation));
    });

    test('added and lost symbols fail before the fake Go command', () async {
      await _withHarness((harness) async {
        for (final mode in <String>['added', 'lost', 'added-and-lost']) {
          final result = await harness.run(mode: 'success', fakeNmMode: mode);
          expect(result.exitCode, 1, reason: 'nm mode $mode\n${result.trace}');
          expect(result.stdout, isEmpty, reason: mode);
          expect(result.nmEvents, contains('invoked|'), reason: mode);
          expect(result.log, isNot(contains('command-started|')), reason: mode);
          expect(
            result.stderr,
            contains('OpenTUI symbol preflight failed for '),
            reason: mode,
          );
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        }
      });
    });

    test('invalid resolved nm path is distinct from a missing tool', () async {
      await _withHarness((harness) async {
        final result = await harness.run(
          mode: 'success',
          fakeNmMode: 'exact-seven',
          invalidNmPath: true,
        );
        expect(result.exitCode, 1);
        expect(result.stdout, isEmpty);
        expect(result.stderr, 'invalid resolved Go snapshot tool path: nm\n');
        expect(result.nmEvents, isEmpty);
        expect(result.log, isEmpty);
        await harness.expectNoTempOwnersOrFixtureSurvivors(result);
      });
    });

    test(
      'tool errors are normalized without replaying private stderr',
      () async {
        await _withHarness((harness) async {
          final result = await harness.run(
            mode: 'success',
            fakeNmMode: 'tool-error',
          );
          expect(result.exitCode, 1, reason: result.trace);
          expect(result.stdout, isEmpty);
          expect(
            result.stderr,
            startsWith('OpenTUI symbol preflight failed for '),
          );
          expect(result.stderr, endsWith(': host nm inspection failed.\n'));
          expect(result.stderr, isNot(contains('private nm failure secret')));
          expect(result.log, isNot(contains('command-started|')));
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );

    test('gated tool errors start only after both anchors are ready', () async {
      await _withHarness((harness) async {
        final result = await harness.run(
          mode: 'success',
          fakeNmMode: 'gated-tool-error',
          timeoutValue: '20',
          parentDeadline: const Duration(seconds: 16),
          afterStart: (process, run) async {
            await run.waitForNmEvent('invoked|', process: process);
            final owner = run.activeTempOwner;
            expect(File('${owner.path}/child.ready').existsSync(), isTrue);
            expect(File('${owner.path}/watchdog.ready').existsSync(), isTrue);
            await run.releaseNmTool();
          },
        );
        expect(result.exitCode, 1, reason: result.trace);
        expect(result.stderr, endsWith(': host nm inspection failed.\n'));
        expect(result.log, isNot(contains('command-started|')));
        expect(_traceCount(result.trace, '|wait_consumed|child|'), 1);
        expect(_traceCount(result.trace, '|wait_consumed|watchdog|'), 1);
        await harness.expectNoTempOwnersOrFixtureSurvivors(result);
      });
    });

    test('forking tool errors kill and reap the stubborn descendant', () async {
      await _withHarness((harness) async {
        final result = await harness.run(
          mode: 'success',
          fakeNmMode: 'forking-tool-error',
          timeoutValue: '20',
          parentDeadline: const Duration(seconds: 16),
          afterStart: (process, run) async {
            await run.waitForNmEvent('descendant|pid=', process: process);
          },
        );
        expect(result.exitCode, 1, reason: result.trace);
        expect(result.stderr, endsWith(': host nm inspection failed.\n'));
        expect(result.stderr, isNot(contains('private nm failure secret')));
        expect(result.log, isNot(contains('command-started|')));
        expect(_traceCount(result.trace, '|signal|child|KILL|'), 1);
        await harness.expectNoTempOwnersOrFixtureSurvivors(result);
      });
    });

    test('exact seven runs once, closes quiescence, then reaches Go', () async {
      await _withHarness((harness) async {
        final result = await harness.run(
          mode: 'success',
          fakeNmMode: 'exact-seven',
          fakeRmMode: 'capture-symbol-raw',
        );
        expect(result.exitCode, 0, reason: result.trace);
        expect(_occurrences(result.nmEvents, 'invoked|'), 1);
        for (final poison in <String>[
          'HOME',
          'TMPDIR',
          'PKG_CONFIG_PATH',
          'PKG_CONFIG_LIBDIR',
          'DYLD_INSERT_LIBRARIES',
          'DYLD_LIBRARY_PATH',
          'LD_PRELOAD',
          'LD_LIBRARY_PATH',
          'LOADER_EVENTS',
          'FAKE_SECRET',
        ]) {
          expect(result.nmEvents, contains('poison|$poison=absent'));
        }
        expect(result.trace, contains('symbol-preflight-quiescence-closed'));
        expect(result.log, contains('command-started|'));
        _expectStableSymbolRawCapture(result);
        await harness.expectNoTempOwnersOrFixtureSurvivors(result);
      });
    });

    test('status-zero delayed writers are rejected before parsing', () async {
      await _withHarness((harness) async {
        final result = await harness.run(
          mode: 'success',
          fakeNmMode: 'forking-success-delayed-append',
          fakeRmMode: 'capture-symbol-raw',
          gateSymbolSnapshot: true,
          afterStart: (process, run) async {
            await run.waitForNmEvent('descendant|pid=', process: process);
            await run.waitForSymbolSnapshot(process: process);
            await run.releaseNmAppend();
            await run.waitForNmAppend(process: process);
            await run.releaseSymbolSnapshot();
          },
        );
        expect(result.exitCode, 1, reason: result.trace);
        expect(result.stderr, contains('host nm inspection failed'));
        expect(
          result.stderr,
          isNot(contains('pending symbol(s) now exported')),
        );
        expect(result.log, isNot(contains('command-started|')));
        final parentCandidate = _fsRecord(
          result.trace,
          'symbol-preflight.quiescence-parent.candidate',
        );
        final disposition = _fsRecord(
          result.trace,
          'symbol-preflight.quiescence-disposition',
        );
        expect(parentCandidate['line'], 'reject:snapshot');
        expect(disposition['line'], 'reject:snapshot');
        expect(disposition['inode'], parentCandidate['inode']);
        expect(
          result.trace,
          contains('P9_STATE|symbol-preflight.quiescence-rejected|present'),
        );
        _expectStableSymbolRawCapture(result);
        await harness.expectNoTempOwnersOrFixtureSurvivors(result);
      });
    });

    test(
      'status-zero descriptor holders are rejected without byte drift',
      () async {
        await _withHarness((harness) async {
          final result = await harness.run(
            mode: 'success',
            fakeNmMode: 'forking-success-descriptor-holder',
            fakeRmMode: 'capture-symbol-raw',
            gateSymbolSnapshot: true,
            afterStart: (process, run) async {
              await run.waitForNmEvent('descendant|pid=', process: process);
              await run.waitForSymbolSnapshot(process: process);
              await run.releaseSymbolSnapshot();
            },
          );
          expect(result.exitCode, 1, reason: result.trace);
          expect(result.stderr, contains('host nm inspection failed'));
          expect(result.log, isNot(contains('command-started|')));
          final parentCandidate = _fsRecord(
            result.trace,
            'symbol-preflight.quiescence-parent.candidate',
          );
          final disposition = _fsRecord(
            result.trace,
            'symbol-preflight.quiescence-disposition',
          );
          expect(parentCandidate['line'], 'reject:snapshot');
          expect(disposition['line'], 'reject:snapshot');
          expect(disposition['inode'], parentCandidate['inode']);
          expect(
            result.trace,
            contains('P9_STATE|symbol-preflight.quiescence-rejected|present'),
          );
          _expectStableSymbolRawCapture(result);
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );

    test('unexpected quiescence FIFO data is a tool rejection', () async {
      await _withHarness((harness) async {
        final result = await harness.run(
          mode: 'success',
          fakeNmMode: 'exact-seven',
          gateSymbolSnapshot: true,
          timeoutValue: '20',
          parentDeadline: const Duration(seconds: 16),
          afterStart: (process, run) async {
            await run.waitForSymbolSnapshot(process: process);
            await run.writeOwnedFifo(
              'child.anchor-control.fifo',
              'unexpected symbol-preflight data\n',
            );
            await run.releaseSymbolSnapshot();
          },
        );
        expect(result.exitCode, 1, reason: result.trace);
        expect(result.stderr, endsWith(': host nm inspection failed.\n'));
        expect(
          result.trace,
          contains(
            'phase=symbol-preflight-quiescence|slot=1|'
            'result=unexpected-data',
          ),
        );
        expect(result.trace, isNot(contains('|cause|protocol|')));
        expect(result.log, isNot(contains('command-started|')));
        await harness.expectNoTempOwnersOrFixtureSurvivors(result);
      });
    });

    test(
      'quiescence slot ceiling is a bounded tool rejection',
      () async {
        await _withHarness((harness) async {
          final result = await harness.run(
            mode: 'success',
            fakeNmMode: 'exact-seven',
            gateSymbolSnapshot: true,
            symbolGateTicks: 6000,
            timeoutValue: '90',
            parentDeadline: const Duration(seconds: 60),
            afterStart: (process, run) async {
              await run.waitForSymbolSnapshot(process: process);
              await run.waitForPrivateTrace(
                'child.shell.stderr',
                'hold|child|phase=symbol-preflight-quiescence|ceiling|slot=30',
                process: process,
                timeout: const Duration(seconds: 50),
              );
              await run.releaseSymbolSnapshot();
            },
          );
          expect(result.exitCode, 1, reason: result.trace);
          expect(result.stderr, endsWith(': host nm inspection failed.\n'));
          expect(
            result.trace,
            contains(
              'hold|child|phase=symbol-preflight-quiescence|ceiling|slot=30',
            ),
          );
          expect(result.trace, isNot(contains('|cause|protocol|')));
          expect(result.log, isNot(contains('command-started|')));
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
      timeout: const Timeout(Duration(seconds: 70)),
    );

    group('P9-043 lifecycle correction DEBUG portability', () {
      test('parent gate uses only the harness-recorded positive PID', () {
        final source = File(
          '$_fixtureDirectory/p9_043_debug_gate.bash',
        ).readAsStringSync();
        final start = source.indexOf(
          r'if [[ "$BASH_COMMAND" == "$expected_parent_command"',
        );
        final end = source.indexOf(
          r'[[ "$BASH_COMMAND" == "$expected_command"',
          start,
        );
        expect(start, greaterThanOrEqualTo(0));
        expect(end, greaterThan(start));
        final parentBranch = source.substring(start, end);
        for (final forbidden in <String>[
          r'$$',
          'BASHPID',
          r'$PPID',
          'kill -STOP 0',
          'kill -KILL 0',
        ]) {
          expect(parentBranch, isNot(contains(forbidden)), reason: forbidden);
        }
        expect(
          parentBranch,
          contains(r'builtin kill -STOP "$P9_043_DEBUG_SUPERVISOR_PID"'),
        );
      });

      test(
        'zero and nonzero statuses stop only the exact supervisor',
        () async {
          if (Platform.isWindows) return;
          final sandbox = await Directory.systemTemp.createTemp(
            'p9-043-parent-debug-probe.',
          );
          final startFifo = File('${sandbox.path}/start.fifo');
          final supervisorPidFile = File('${sandbox.path}/supervisor.pid');
          final started = File('${sandbox.path}/started');
          final stopped = File('${sandbox.path}/stopped');
          final continued = File('${sandbox.path}/continued');
          final secondStopped = File('${sandbox.path}/second-stopped');
          final secondContinued = File('${sandbox.path}/second-continued');
          final hookFailed = File('${sandbox.path}/hook-failed');
          final status = File('${sandbox.path}/status');
          final secondStatus = File('${sandbox.path}/second-status');
          final childPidFile = File('${sandbox.path}/child.pid');
          final watchdogPidFile = File('${sandbox.path}/watchdog.pid');
          Process? process;
          int? childPid;
          int? watchdogPid;
          try {
            final mkfifo = await Process.run(await _executablePath('mkfifo'), [
              startFifo.path,
            ]);
            expect(mkfifo.exitCode, 0, reason: mkfifo.stderr as String);
            process = await Process.start(
              '/bin/bash',
              <String>[
                File('$_fixtureDirectory/p9_043_debug_probe.sh').absolute.path,
              ],
              environment: <String, String>{
                ...Platform.environment,
                'BASH_ENV': File(
                  '$_fixtureDirectory/p9_043_debug_gate.bash',
                ).absolute.path,
                'P9_043_DEBUG_START_FIFO': startFifo.path,
                'P9_043_DEBUG_SUPERVISOR_PID_FILE': supervisorPidFile.path,
                'P9_043_DEBUG_STARTED': started.path,
                'P9_043_DEBUG_POSTLINK_STOPPED': stopped.path,
                'P9_043_DEBUG_POSTLINK_CONTINUED': continued.path,
                'P9_043_DEBUG_SECOND_POSTLINK_STOPPED': secondStopped.path,
                'P9_043_DEBUG_SECOND_POSTLINK_CONTINUED': secondContinued.path,
                'P9_043_DEBUG_HOOK_FAILED': hookFailed.path,
                'P9_043_DEBUG_EXPECT_PARENT_STATUS': '0',
                'P9_043_DEBUG_EXPECT_PARENT_RECORD': 'authorize',
                'P9_043_DEBUG_PROBE_MODE': 'parent',
                'P9_043_DEBUG_PROBE_LINK_MODE': 'both',
                'P9_043_DEBUG_PROBE_DIR': sandbox.path,
                'P9_043_DEBUG_PROBE_LINK_STATUS': status.path,
                'P9_043_DEBUG_PROBE_SECOND_LINK_STATUS': secondStatus.path,
                'P9_043_DEBUG_PROBE_CHILD_PID': childPidFile.path,
                'P9_043_DEBUG_PROBE_WATCHDOG_PID': watchdogPidFile.path,
              },
            );
            final stdout = process.stdout.transform(utf8.decoder).join();
            final stderr = process.stderr.transform(utf8.decoder).join();
            await supervisorPidFile.writeAsString(
              '${process.pid}\n',
              flush: true,
            );
            _writeStartFifoToken(startFifo);

            Future<void> waitFor(File file) async {
              final deadline = DateTime.now().add(const Duration(seconds: 8));
              while (!file.existsSync() && DateTime.now().isBefore(deadline)) {
                await Future<void>.delayed(const Duration(milliseconds: 5));
              }
              expect(file.existsSync(), isTrue, reason: file.path);
              expect(hookFailed.existsSync(), isFalse);
            }

            Future<void> expectIdentities() async {
              final realPs = await _executablePath('ps');
              for (final identity in <(int, bool)>[
                (process!.pid, true),
                (childPid!, false),
                (watchdogPid!, false),
              ]) {
                final ps = await Process.run(realPs, <String>[
                  '-o',
                  'pid=,pgid=,stat=',
                  '-p',
                  '${identity.$1}',
                ]);
                expect(ps.exitCode, 0, reason: ps.stderr as String);
                final fields = (ps.stdout as String).trim().split(
                  RegExp(r'\s+'),
                );
                expect(fields[0], '${identity.$1}');
                if (!identity.$2) expect(fields[1], '${identity.$1}');
                expect(
                  fields[2],
                  identity.$2
                      ? anyOf(startsWith('T'), startsWith('t'))
                      : isNot(anyOf(startsWith('T'), startsWith('t'))),
                );
              }
            }

            await waitFor(started);
            await waitFor(stopped);
            await waitFor(childPidFile);
            await waitFor(watchdogPidFile);
            childPid = int.parse(childPidFile.readAsStringSync().trim());
            watchdogPid = int.parse(watchdogPidFile.readAsStringSync().trim());
            expect(stopped.readAsStringSync(), 'ready|authorize|status=0\n');
            await expectIdentities();
            expect(Process.killPid(process.pid, ProcessSignal.sigcont), isTrue);

            await waitFor(secondStopped);
            expect(status.readAsStringSync(), '0\n');
            expect(
              continued.readAsStringSync(),
              'continued|authorize|status=0\n',
            );
            expect(
              secondStopped.readAsStringSync(),
              'ready|reject:unexpected-data|status=1\n',
            );
            await expectIdentities();
            expect(Process.killPid(process.pid, ProcessSignal.sigcont), isTrue);

            expect(
              await process.exitCode.timeout(const Duration(seconds: 8)),
              0,
              reason: 'stdout=${await stdout}\nstderr=${await stderr}',
            );
            expect(secondStatus.readAsStringSync(), '1\n');
            expect(
              secondContinued.readAsStringSync(),
              'continued|reject:unexpected-data|status=1\n',
            );
            expect(hookFailed.existsSync(), isFalse);
          } finally {
            if (process != null) {
              Process.killPid(process.pid, ProcessSignal.sigcont);
              Process.killPid(process.pid, ProcessSignal.sigkill);
            }
            for (final pid in <int?>[childPid, watchdogPid]) {
              if (pid != null) Process.killPid(pid, ProcessSignal.sigkill);
            }
            if (sandbox.existsSync()) await sandbox.delete(recursive: true);
          }
        },
      );
    });

    group('P9-043 atomic child-rejection disposition', () {
      test(
        'source owns one immutable quiescence election',
        _expectAtomicDispositionSurface,
      );

      test('DEBUG prelink bootstrap preserves status and child PGID', () async {
        if (Platform.isWindows) return;
        final sandbox = await Directory.systemTemp.createTemp(
          'p9-043-debug-probe.',
        );
        final prelink = File('${sandbox.path}/prelink');
        final continued = File('${sandbox.path}/continued');
        final hookFailed = File('${sandbox.path}/hook-failed');
        final status = File('${sandbox.path}/status');
        final linkStatus = File('${sandbox.path}/link-status');
        final childPidFile = File('${sandbox.path}/child-pid');
        int? childPid;
        Process? process;
        try {
          process = await Process.start(
            '/bin/bash',
            <String>[
              File('$_fixtureDirectory/p9_043_debug_probe.sh').absolute.path,
            ],
            environment: <String, String>{
              ...Platform.environment,
              'BASH_ENV': File(
                '$_fixtureDirectory/p9_043_debug_gate.bash',
              ).absolute.path,
              'P9_043_DEBUG_PRELINK_STOPPED': prelink.path,
              'P9_043_DEBUG_CONTINUED': continued.path,
              'P9_043_DEBUG_HOOK_FAILED': hookFailed.path,
              'P9_043_DEBUG_PROBE_DIR': sandbox.path,
              'P9_043_DEBUG_PROBE_STATUS': status.path,
              'P9_043_DEBUG_PROBE_LINK_STATUS': linkStatus.path,
              'P9_043_DEBUG_PROBE_CHILD_PID': childPidFile.path,
            },
          );
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (DateTime.now().isBefore(deadline) &&
              (!prelink.existsSync() || !childPidFile.existsSync())) {
            if (await _futureCompleted(process.exitCode)) break;
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(hookFailed.existsSync(), isFalse);
          expect(prelink.readAsStringSync(), 'ready|reject:unexpected-data\n');
          expect(status.readAsStringSync(), '1\n');
          childPid = int.parse(childPidFile.readAsStringSync().trim());
          final identity = await Process.run('/bin/ps', <String>[
            '-o',
            'pid=,pgid=,stat=',
            '-p',
            '$childPid',
          ]);
          expect(identity.exitCode, 0);
          final fields = (identity.stdout as String).trim().split(
            RegExp(r'\s+'),
          );
          expect(fields[0], '$childPid');
          expect(fields[1], '$childPid');
          expect(fields[2], anyOf(startsWith('T'), startsWith('t')));

          final parentCandidate = File(
            '${sandbox.path}/symbol-preflight.quiescence-parent.candidate',
          )..writeAsStringSync('authorize\n');
          final disposition = File(
            '${sandbox.path}/symbol-preflight.quiescence-disposition',
          );
          final link = await Process.run('/bin/ln', <String>[
            parentCandidate.path,
            disposition.path,
          ]);
          expect(link.exitCode, 0, reason: link.stderr as String);
          File(
            '${sandbox.path}/symbol-preflight.quiescence-authorized',
          ).createSync();
          expect(Process.killPid(childPid, ProcessSignal.sigcont), isTrue);

          expect(await process.exitCode.timeout(const Duration(seconds: 5)), 0);
          expect(continued.readAsStringSync(), 'continued\n');
          expect(hookFailed.existsSync(), isFalse);
          expect(int.parse(linkStatus.readAsStringSync().trim()), isNot(0));
          expect(
            await FileSystemEntity.identical(
              parentCandidate.path,
              disposition.path,
            ),
            isTrue,
          );
        } finally {
          if (childPid != null) {
            Process.killPid(childPid, ProcessSignal.sigcont);
            Process.killPid(childPid, ProcessSignal.sigkill);
          }
          if (process != null && await _pidExists(process.pid)) {
            Process.killPid(process.pid, ProcessSignal.sigkill);
          }
          if (sandbox.existsSync()) await sandbox.delete(recursive: true);
        }
      });

      test('child-first unexpected data wins rejection disposition', () async {
        _expectAtomicDispositionSurface();
        await _withHarness((harness) async {
          final result = await harness.run(
            mode: 'success',
            fakeNmMode: 'exact-seven',
            gateSymbolSnapshot: true,
            timeoutValue: '20',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForSymbolSnapshot(process: process);
              await run.writeOwnedFifo(
                'child.anchor-control.fifo',
                'unexpected symbol-preflight data\n',
              );
              await run.waitForOwnedExactFile(
                'symbol-preflight.quiescence-child.candidate',
                'reject:unexpected-data\n',
                process: process,
              );
              await run.waitForOwnedExactFile(
                'symbol-preflight.quiescence-disposition',
                'reject:unexpected-data\n',
                process: process,
              );
              expect(
                await run.ownedInode(
                  'symbol-preflight.quiescence-child.candidate',
                ),
                await run.ownedInode('symbol-preflight.quiescence-disposition'),
              );
              expect(
                File(
                  '${run.activeTempOwner.path}/'
                  'symbol-preflight.quiescence-authorized',
                ).existsSync(),
                isFalse,
              );
              await run.releaseSymbolSnapshot();
            },
          );
          expect(result.exitCode, 1, reason: result.trace);
          expect(result.stderr, endsWith(': host nm inspection failed.\n'));
          expect(
            result.trace,
            contains('P9_STATE|symbol-preflight.quiescence-closed|absent'),
          );
          expect(result.trace, isNot(contains('symbol_preflight|parse-start')));
          expect(result.log, isNot(contains('command-started|')));
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      });

      test(
        'child-first slot ceiling wins rejection disposition',
        () async {
          _expectAtomicDispositionSurface();
          await _withHarness((harness) async {
            final result = await harness.run(
              mode: 'success',
              fakeNmMode: 'exact-seven',
              gateSymbolSnapshot: true,
              symbolGateTicks: 6000,
              timeoutValue: '90',
              parentDeadline: const Duration(seconds: 60),
              afterStart: (process, run) async {
                await run.waitForSymbolSnapshot(process: process);
                await run.waitForOwnedExactFile(
                  'symbol-preflight.quiescence-child.candidate',
                  'reject:ceiling\n',
                  process: process,
                  timeout: const Duration(seconds: 50),
                );
                await run.waitForOwnedExactFile(
                  'symbol-preflight.quiescence-disposition',
                  'reject:ceiling\n',
                  process: process,
                  timeout: const Duration(seconds: 50),
                );
                expect(
                  await run.ownedInode(
                    'symbol-preflight.quiescence-child.candidate',
                  ),
                  await run.ownedInode(
                    'symbol-preflight.quiescence-disposition',
                  ),
                );
                await run.releaseSymbolSnapshot();
              },
            );
            expect(result.exitCode, 1, reason: result.trace);
            expect(result.stderr, endsWith(': host nm inspection failed.\n'));
            expect(
              result.trace,
              contains('P9_STATE|symbol-preflight.quiescence-closed|absent'),
            );
            expect(
              result.trace,
              isNot(contains('symbol_preflight|parse-start')),
            );
            expect(result.log, isNot(contains('command-started|')));
            await harness.expectNoTempOwnersOrFixtureSurvivors(result);
          });
        },
        timeout: const Timeout(Duration(seconds: 70)),
      );

      test(
        'parent snapshot rejection owns disposition and descendant cleanup',
        () async {
          _expectAtomicDispositionSurface();
          await _withHarness((harness) async {
            final result = await harness.run(
              mode: 'success',
              fakeNmMode: 'forking-success-descriptor-holder',
              fakeRmMode: 'capture-symbol-raw',
              gateSymbolSnapshot: true,
              parentDeadline: const Duration(seconds: 16),
              afterStart: (process, run) async {
                await run.waitForNmEvent('descendant|pid=', process: process);
                await run.waitForSymbolSnapshot(process: process);
                await run.releaseSymbolSnapshot();
              },
            );
            expect(result.exitCode, 1, reason: result.trace);
            expect(result.stderr, endsWith(': host nm inspection failed.\n'));
            final parent = _fsRecord(
              result.trace,
              'symbol-preflight.quiescence-parent.candidate',
            );
            final disposition = _fsRecord(
              result.trace,
              'symbol-preflight.quiescence-disposition',
            );
            expect(parent['line'], 'reject:snapshot');
            expect(disposition['line'], 'reject:snapshot');
            expect(disposition['inode'], parent['inode']);
            expect(
              result.trace,
              contains('P9_STATE|symbol-preflight.quiescence-rejected|present'),
            );
            expect(
              result.trace,
              contains(
                'P9_STATE|symbol-preflight.quiescence-authorized|absent',
              ),
            );
            expect(
              result.trace,
              contains(
                'P9_STATE|symbol-preflight.quiescence-child.candidate|absent',
              ),
            );
            expect(
              result.trace,
              isNot(
                contains(
                  'LINK_STDERR|'
                  'symbol-preflight.quiescence-child.ln.stderr|',
                ),
              ),
            );
            expect(
              result.trace,
              contains('P9_STATE|symbol-preflight.quiescence-closed|absent'),
            );
            expect(
              result.trace,
              isNot(contains('symbol_preflight|parse-start')),
            );
            expect(result.log, isNot(contains('command-started|')));
            _expectStableSymbolRawCapture(result);
            await harness.expectNoTempOwnersOrFixtureSurvivors(result);
          });
        },
      );

      test('parent authorization wins before consumed FIFO data', () async {
        _expectAtomicDispositionSurface();
        await _withHarness((harness) async {
          int? childPid;
          var stopped = false;
          final result = await harness.run(
            mode: 'success',
            fakeNmMode: 'exact-seven',
            runFakePsMode: 'symbol-authorize-before-data',
            gateSymbolSnapshot: true,
            gateAtomicPrelink: true,
            symbolGateTicks: 6000,
            timeoutValue: '30',
            parentDeadline: const Duration(seconds: 24),
            afterStart: (process, run) async {
              final identity = await run.waitForSymbolSnapshotIdentity(
                process: process,
              );
              childPid = identity.$1;
              expect(identity.$2, childPid);
              expect(identity.$3, anyOf('R', 'S'));
              run.recordOwnedPid(childPid!);
              try {
                await run.writeOwnedFifo(
                  'child.anchor-control.fifo',
                  'unexpected symbol-preflight data\n',
                );
                await run.waitForDebugPrelinkStop(process: process);
                stopped = true;
                await run.expectSoleGroupMember(
                  childPid!,
                  identity.$2,
                  const <String>['T', 't'],
                );
                await run.waitForOwnedExactFile(
                  'symbol-preflight.quiescence-child.candidate',
                  'reject:unexpected-data\n',
                  process: process,
                );
                await run.releaseSymbolSnapshot();
                await run.waitForOwnedExactFile(
                  'symbol-preflight.quiescence-parent.candidate',
                  'authorize\n',
                  process: process,
                );
                await run.waitForOwnedExactFile(
                  'symbol-preflight.quiescence-disposition',
                  'authorize\n',
                  process: process,
                );
                await run.waitForOwnedExactFile(
                  'symbol-preflight.quiescence-authorized',
                  '',
                  process: process,
                );
                final parentInode = await run.ownedInode(
                  'symbol-preflight.quiescence-parent.candidate',
                );
                expect(
                  await run.ownedInode(
                    'symbol-preflight.quiescence-disposition',
                  ),
                  parentInode,
                );
                expect(
                  await run.ownedInode(
                    'symbol-preflight.quiescence-child.candidate',
                  ),
                  isNot(parentInode),
                );
                expect(
                  Process.killPid(childPid!, ProcessSignal.sigcont),
                  isTrue,
                );
                stopped = false;
                await run.waitForDebugContinuation(process: process);
              } finally {
                if (stopped && childPid != null) {
                  Process.killPid(childPid!, ProcessSignal.sigcont);
                }
              }
            },
          );
          expect(result.exitCode, 1, reason: result.trace);
          expect(result.stderr, isEmpty);
          expect(result.trace, contains('|cause|protocol|status=1'));
          expect(
            result.trace,
            contains(
              'P9_STATE|symbol-preflight.quiescence-child.candidate|present',
            ),
          );
          expect(
            result.trace,
            contains('P9_STATE|symbol-preflight.result|absent'),
          );
          expect(result.trace, isNot(contains('FS|child.candidate|')));
          expect(
            result.trace,
            contains('P9_STATE|symbol-preflight.quiescence-closed|absent'),
          );
          expect(result.trace, isNot(contains('symbol_preflight|parse-start')));
          expect(result.log, isNot(contains('command-started|')));
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      });

      test(
        'trailing bytes in the elected record cannot authorize parsing',
        () async {
          _expectAtomicDispositionSurface();
          await _withHarness((harness) async {
            int? childPid;
            var stopped = false;
            final result = await harness.run(
              mode: 'success',
              fakeNmMode: 'exact-seven',
              runFakePsMode: 'symbol-authorize-before-data',
              gateSymbolSnapshot: true,
              gateAtomicPrelink: true,
              symbolGateTicks: 6000,
              timeoutValue: '30',
              parentDeadline: const Duration(seconds: 24),
              afterStart: (process, run) async {
                final identity = await run.waitForSymbolSnapshotIdentity(
                  process: process,
                );
                childPid = identity.$1;
                run.recordOwnedPid(childPid!);
                try {
                  await run.writeOwnedFifo(
                    'child.anchor-control.fifo',
                    'unexpected symbol-preflight data\n',
                  );
                  await run.waitForDebugPrelinkStop(process: process);
                  stopped = true;
                  await run.waitForOwnedExactFile(
                    'symbol-preflight.quiescence-child.candidate',
                    'reject:unexpected-data\n',
                    process: process,
                  );
                  await run.releaseSymbolSnapshot();
                  await run.waitForOwnedExactFile(
                    'symbol-preflight.quiescence-disposition',
                    'authorize\n',
                    process: process,
                  );
                  await run.waitForOwnedExactFile(
                    'symbol-preflight.quiescence-authorized',
                    '',
                    process: process,
                  );
                  File(
                    '${run.activeTempOwner.path}/'
                    'symbol-preflight.quiescence-disposition',
                  ).writeAsStringSync('trailing', mode: FileMode.append);
                  expect(
                    Process.killPid(childPid!, ProcessSignal.sigcont),
                    isTrue,
                  );
                  stopped = false;
                  await run.waitForDebugContinuation(process: process);
                } finally {
                  if (stopped && childPid != null) {
                    Process.killPid(childPid!, ProcessSignal.sigcont);
                  }
                }
              },
            );
            expect(result.exitCode, 1, reason: result.trace);
            expect(result.stderr, isEmpty);
            expect(result.trace, contains('|cause|protocol|status=1'));
            final disposition = _fsRecord(
              result.trace,
              'symbol-preflight.quiescence-disposition',
            );
            final parent = _fsRecord(
              result.trace,
              'symbol-preflight.quiescence-parent.candidate',
            );
            expect(disposition['inode'], parent['inode']);
            expect(disposition['line'], 'authorize');
            expect(disposition['size'], isNot('10'));
            expect(
              result.trace,
              contains('P9_STATE|symbol-preflight.result|absent'),
            );
            expect(
              result.trace,
              contains('P9_STATE|symbol-preflight.quiescence-closed|absent'),
            );
            expect(
              result.trace,
              isNot(contains('symbol_preflight|parse-start')),
            );
            expect(result.log, isNot(contains('command-started|')));
            await harness.expectNoTempOwnersOrFixtureSurvivors(result);
          });
        },
      );

      test(
        'adjacent contenders leave exactly one disposition inode',
        _expectAdjacentContenderWinnerOracle,
      );

      for (final scenario in const <(String, _PostElectionCause)>[
        ('INT', _PostElectionCause.interrupt),
        ('TERM', _PostElectionCause.terminate),
        ('timeout', _PostElectionCause.timeout),
      ]) {
        test(
          '${scenario.$1} after election preserves the immutable disposition',
          () => _expectPostElectionPrecedence(scenario.$2),
          timeout: Timeout(
            Duration(
              seconds: scenario.$2 == _PostElectionCause.timeout ? 50 : 45,
            ),
          ),
        );
      }
    });

    group('P9-043 lifecycle correction production', () {
      test(
        'nonzero preflight closes caller stderr before a frozen child exits',
        () async {
          await _withHarness((harness) async {
            Directory? retainedOwner;
            var childPid = -1;
            final result = await harness.run(
              mode: 'success',
              fakeNmMode: 'tool-error',
              runFakePsMode: 'post-child-ceiling',
              gatePostWorkLabel: 'child',
              timeoutValue: '20',
              parentDeadline: const Duration(seconds: 16),
              streamDeadline: const Duration(seconds: 4),
              afterStart: (process, run) async {
                await run.waitForPostWorkSnapshot(process: process);
                retainedOwner = run.activeTempOwner;
                await run.releasePostWorkSnapshot();
                childPid = await run.waitForPostWorkSelection(process: process);
                run.recordOwnedPid(childPid);
              },
            );

            final owner = retainedOwner!;
            final stderrLines = const LineSplitter().convert(result.stderr);
            expect(result.exitCode, 1, reason: result.trace);
            expect(result.stderrClosed, isTrue, reason: result.trace);
            expect(await _pidExists(childPid), isTrue, reason: result.trace);
            expect(stderrLines, hasLength(3), reason: result.stderr);
            expect(
              stderrLines[0],
              matches(
                RegExp(
                  '^OpenTUI symbol preflight failed for .+/native/'
                  '(macos|linux)/(arm64|x64)/libopentui[.](dylib|so): '
                  r'host nm inspection failed[.]$',
                ),
              ),
            );
            expect(
              stderrLines[1],
              'cleanup could not prove terminal consumption; '
              'retained temporary directory: ${owner.path}',
            );
            expect(
              stderrLines[2],
              'Go snapshot cleanup did not complete safely.',
            );
            expect(result.stderr, isNot(contains('private nm failure secret')));
            expect(result.log, isNot(contains('command-started|')));
            expect(_traceCount(result.trace, '|action|child|frozen|'), 1);

            await harness.waitForAssertionPidsToExit(
              result,
              const Duration(seconds: 35),
            );
            await result.stdoutDone.timeout(const Duration(seconds: 2));
            expect(await _pidExists(childPid), isFalse);
            final privateTrace = File(
              '${owner.path}/child.shell.stderr',
            ).readAsStringSync();
            expect(
              _traceCount(privateTrace, '|anchor_tick|child|phase=post|'),
              30,
            );
            expect(
              _traceCount(
                privateTrace,
                '|hold|child|phase=post|ceiling|slot=30',
              ),
              1,
            );
            expect(_traceCount(privateTrace, '|fifo|child|post-closed|'), 1);
            await owner.delete(recursive: true);
            expect(harness.tempOwners, isEmpty);
          });
        },
        timeout: const Timeout(Duration(minutes: 1)),
      );

      test(
        'complete child winner before parent snapshot keeps tool semantics',
        () async {
          await _withHarness((harness) async {
            int? childPid;
            var parentStopped = false;
            var childStopped = false;
            final result = await harness.run(
              mode: 'success',
              fakeNmMode: 'exact-seven',
              gateAtomicPreAdmission: true,
              gateAtomicChildPostlink: true,
              timeoutValue: '30',
              parentDeadline: const Duration(seconds: 24),
              afterStart: (process, run) async {
                try {
                  await run.waitForDebugPreAdmissionStop(process: process);
                  parentStopped = true;
                  final childRow = const LineSplitter()
                      .convert(run.log.readAsStringSync())
                      .singleWhere(
                        (line) =>
                            line.startsWith('mkfifo-invoked|') &&
                            line.contains('|child|'),
                      )
                      .split('|');
                  childPid = int.parse(childRow[2]);
                  run.recordOwnedPid(childPid!);
                  await run.writeOwnedFifo(
                    'child.anchor-control.fifo',
                    'unexpected symbol-preflight data\n',
                  );
                  await run.waitForDebugChildPostlinkStop(process: process);
                  childStopped = true;
                  await run.waitForOwnedExactFile(
                    'symbol-preflight.quiescence-disposition',
                    'reject:unexpected-data\n',
                    process: process,
                  );
                  expect(
                    Process.killPid(process.pid, ProcessSignal.sigcont),
                    isTrue,
                  );
                  parentStopped = false;
                  await run.waitForOwnedExactFile(
                    'symbol-preflight.quiescence-parent.candidate',
                    'authorize\n',
                    process: process,
                  );
                  await run.waitForOwnedExactFile(
                    'symbol-preflight.quiescence-rejected',
                    '',
                    process: process,
                  );
                  expect(
                    Process.killPid(childPid!, ProcessSignal.sigcont),
                    isTrue,
                  );
                  childStopped = false;
                } finally {
                  if (parentStopped) {
                    Process.killPid(process.pid, ProcessSignal.sigcont);
                  }
                  if (childStopped && childPid != null) {
                    Process.killPid(childPid!, ProcessSignal.sigcont);
                  }
                }
              },
            );
            expect(result.exitCode, 1, reason: result.trace);
            expect(result.stderr, endsWith(': host nm inspection failed.\n'));
            expect(result.trace, isNot(contains('|cause|protocol|')));
            final disposition = _fsRecord(
              result.trace,
              'symbol-preflight.quiescence-disposition',
            );
            final child = _fsRecord(
              result.trace,
              'symbol-preflight.quiescence-child.candidate',
            );
            expect(disposition['line'], 'reject:unexpected-data');
            expect(disposition['inode'], child['inode']);
            expect(
              result.trace,
              contains('P9_STATE|symbol-preflight.quiescence-rejected|present'),
            );
            expect(
              result.trace,
              contains(
                'P9_STATE|symbol-preflight.quiescence-authorized|absent',
              ),
            );
            expect(
              result.trace,
              contains('P9_STATE|symbol-preflight.quiescence-closed|absent'),
            );
            expect(result.log, isNot(contains('command-started|')));
            await harness.expectNoTempOwnersOrFixtureSurvivors(result);
          });
        },
      );

      test(
        'stable admission contradictions fail closed',
        _expectStableAdmissionContradictions,
        // Composes two serialized harness runs; measured clean runtime is 64s
        // against the file's 60s default, exceeding it outright (P9-050
        // Amendment 4).
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'malformed terminal winner cannot authorize parsing',
        _expectMalformedTerminalWinner,
      );

      test(
        'real candidate-only prefix reaches the one parent election',
        _expectCandidateOnlyAdmission,
      );

      test(
        'link-in-flight prefix and terminal overlap have one winner',
        _expectLinkInFlightCoverage,
      );

      test(
        'source guards admission asymmetry and both authorized fences',
        _expectLifecycleCorrectionSourceGuards,
      );
    });

    test('INT while the quiescence snapshot is gated remains causal', () async {
      await _withHarness((harness) async {
        final result = await harness.run(
          mode: 'success',
          fakeNmMode: 'exact-seven',
          gateSymbolSnapshot: true,
          afterStart: (process, run) async {
            await run.waitForSymbolSnapshot(process: process);
            Process.killPid(process.pid, ProcessSignal.sigint);
            await run.releaseSymbolSnapshot();
          },
        );
        expect(result.exitCode, 130, reason: result.trace);
        expect(result.stderr, isNot(contains('OpenTUI symbol preflight')));
        expect(result.log, isNot(contains('command-started|')));
        _expectQuiescenceAbortState(result);
        await harness.expectNoTempOwnersOrFixtureSurvivors(result);
      });
    });

    test(
      'TERM while the quiescence snapshot is gated remains causal',
      () async {
        await _withHarness((harness) async {
          final result = await harness.run(
            mode: 'success',
            fakeNmMode: 'exact-seven',
            gateSymbolSnapshot: true,
            timeoutValue: '20',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForSymbolSnapshot(process: process);
              expect(Process.killPid(process.pid), isTrue);
              await run.releaseSymbolSnapshot();
            },
          );
          expect(result.exitCode, 143, reason: result.trace);
          expect(result.stdout, isEmpty);
          expect(result.stderr, isEmpty);
          expect(result.log, isNot(contains('command-started|')));
          _expectQuiescenceAbortState(result);
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );

    test(
      'timeout while the quiescence snapshot is gated remains causal',
      () async {
        await _withHarness((harness) async {
          final result = await harness.run(
            mode: 'success',
            fakeNmMode: 'exact-seven',
            gateSymbolSnapshot: true,
            timeoutValue: '6',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForSymbolSnapshot(process: process);
              await Future<void>.delayed(const Duration(milliseconds: 6500));
              await run.releaseSymbolSnapshot();
            },
          );
          expect(result.exitCode, 124, reason: result.trace);
          expect(result.stderr, _timeoutDiagnosticFor(6));
          expect(result.log, isNot(contains('command-started|')));
          _expectQuiescenceAbortState(result);
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );

    test('native loader tool-error is bounded through wrapper exit', () async {
      final result = await _runP9043LoaderRedProbe();
      expect(
        result.exitCode,
        1,
        reason:
            'wrapper did not normalize native nm status 9\n'
            'stdout=${result.stdout}\nstderr=${result.stderr}\n'
            'events=${result.events}',
      );
      expect(result.stdout, isEmpty);
      expect(
        result.stderr,
        'OpenTUI symbol preflight failed for ${result.selectedPath}: '
        'host nm inspection failed.\n',
      );
      expect(
        result.nmPoison,
        'inherited-poison|HOME=absent|TMPDIR=absent|'
        'PKG_CONFIG_PATH=absent|PKG_CONFIG_LIBDIR=absent|'
        'DYLD_INSERT_LIBRARIES=absent|DYLD_LIBRARY_PATH=absent|'
        'LD_PRELOAD=absent|LD_LIBRARY_PATH=absent|'
        'LOADER_EVENTS=absent|FAKE_SECRET=absent\n',
      );
      expect(result.goLaunched, isFalse);
      expect(result.pkgConfigLaunched, isFalse);
      expect(result.events, startsWith('load|pid=${result.controlPid}|'));
      expect(result.events, isNot(contains('pid=${result.bootstrapPid}|')));
      expect(result.events, isNot(contains('pid=${result.nmPid}|')));
    });

    test('native loader topology rejects scripts and unsafe paths', () async {
      final bootstrap = File(
        'test/fixtures/go_snapshot/clean_bash_bootstrap.sh',
      ).readAsStringSync();
      expect(
        bootstrap,
        contains(
          'for tool in uname tr mktemp mkdir rm ps stat mkfifo nm go pkg-config',
        ),
      );
      expect(bootstrap, contains(r'resolved="$(builtin type -P "$tool")"'));
      expect(bootstrap, contains(r'[[ "$resolved" == "$dispatch/$tool" ]]'));
      expect(bootstrap, contains('[[ -f /bin/ln && -x /bin/ln'));
      expect(bootstrap, contains('[[ -f /bin/sleep && -x /bin/sleep'));
      final sandbox = await Directory.systemTemp.createTemp('p9-043-native.');
      try {
        final uname = await _executablePath('uname');
        final script = File('${sandbox.path}/script')
          ..writeAsStringSync('#!/bin/sh\nexit 0\n');
        await Process.run('chmod', <String>['700', script.path]);
        expect(
          () => _canonicalNativeImage(script.path),
          throwsA(isA<TestFailure>()),
        );
        expect(
          () => _canonicalNativeImage('$uname|bad'),
          throwsA(isA<TestFailure>()),
        );
        final native = _canonicalNativeImage(uname);
        expect(
          FileSystemEntity.typeSync(native, followLinks: false),
          FileSystemEntityType.file,
        );
      } finally {
        await sandbox.delete(recursive: true);
      }
    });

    for (final signalCase in <(String, ProcessSignal, int)>[
      ('INT', ProcessSignal.sigint, 130),
      ('TERM', ProcessSignal.sigterm, 143),
    ]) {
      test(
        'hung forking inspector preserves ${signalCase.$1} ownership',
        () async {
          await _withHarness((harness) async {
            final result = await harness.run(
              mode: 'success',
              fakeNmMode: 'hung-forking',
              timeoutValue: '20',
              parentDeadline: const Duration(seconds: 16),
              afterStart: (process, run) async {
                await run.waitForNmEvent('descendant|pid=', process: process);
                Process.killPid(process.pid, signalCase.$2);
              },
            );
            expect(result.exitCode, signalCase.$3, reason: result.trace);
            expect(result.stdout, isEmpty);
            expect(result.stderr, isEmpty);
            expect(result.log, isNot(contains('command-started|')));
            expect(_traceCount(result.trace, '|wait_consumed|child|'), 1);
            expect(_traceCount(result.trace, '|wait_consumed|watchdog|'), 1);
            await harness.expectNoTempOwnersOrFixtureSurvivors(result);
          });
        },
      );
    }

    test(
      'hung forking inspector preserves watchdog timeout ownership',
      () async {
        await _withHarness((harness) async {
          final result = await harness.run(
            mode: 'success',
            fakeNmMode: 'hung-forking',
            timeoutValue: '6',
            parentDeadline: const Duration(seconds: 16),
            afterStart: (process, run) async {
              await run.waitForNmEvent('descendant|pid=', process: process);
            },
          );
          expect(result.exitCode, 124, reason: result.trace);
          expect(result.stdout, isEmpty);
          expect(result.stderr, _timeoutDiagnosticFor(6));
          expect(result.log, isNot(contains('command-started|')));
          expect(_traceCount(result.trace, '|wait_consumed|child|'), 1);
          expect(_traceCount(result.trace, '|wait_consumed|watchdog|'), 1);
          await harness.expectNoTempOwnersOrFixtureSurvivors(result);
        });
      },
    );
  });

  test(
    'repo-owned Go snapshot wrapper produces a real snapshot for S1',
    () async {
      if (Platform.isWindows) {
        return;
      }
      if (!await _hasExecutable('go')) {
        markTestSkipped('go is required to run local parity snapshots.');
        return;
      }
      if (!await _hasExecutable('pkg-config')) {
        markTestSkipped(
          'pkg-config is required to run local parity snapshots.',
        );
        return;
      }

      final script = File(_scriptPath);
      expect(script.existsSync(), isTrue, reason: 'Missing $_scriptPath');

      final result = await Process.run('/bin/bash', [
        script.absolute.path,
        '--scene',
        'S1',
        '--width',
        '20',
        '--height',
        '5',
      ]).timeout(const Duration(seconds: 110));

      expect(
        result.exitCode,
        0,
        reason:
            'Wrapper failed.\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}',
      );

      final decoded =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(decoded['version'], '1');
      expect(decoded['width'], 20);
      expect(decoded['height'], 5);
      final cells = decoded['cells'] as List<dynamic>;
      expect(cells, isNotEmpty);
      expect((cells.first as Map<String, dynamic>)['ch'], 'H');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

enum _PostElectionCause { interrupt, terminate, timeout }

Future<void> _expectStableAdmissionContradictions() async {
  for (final contradiction in <String>[
    'parent-residue',
    'orphan-destination',
  ]) {
    await _withHarness((harness) async {
      var parentStopped = false;
      final result = await harness.run(
        mode: 'success',
        fakeNmMode: 'exact-seven',
        gateAtomicPreAdmission: true,
        timeoutValue: '20',
        parentDeadline: const Duration(seconds: 24),
        afterStart: (process, run) async {
          try {
            await run.waitForDebugPreAdmissionStop(process: process);
            parentStopped = true;
            final owner = run.activeTempOwner.path;
            switch (contradiction) {
              case 'parent-residue':
                File(
                  '$owner/symbol-preflight.quiescence-parent.candidate',
                ).writeAsStringSync('authorize\n');
              case 'orphan-destination':
                File(
                  '$owner/symbol-preflight.quiescence-disposition',
                ).writeAsStringSync('reject:unexpected-data\n');
            }
            expect(Process.killPid(process.pid, ProcessSignal.sigcont), isTrue);
            parentStopped = false;
          } finally {
            if (parentStopped) {
              Process.killPid(process.pid, ProcessSignal.sigcont);
            }
          }
        },
      );
      expect(result.exitCode, 1, reason: '$contradiction\n${result.trace}');
      expect(result.stderr, isEmpty, reason: contradiction);
      expect(result.trace, contains('|cause|protocol|status=1'));
      expect(
        result.trace,
        contains('P9_STATE|symbol-preflight.quiescence-authorized|absent'),
      );
      expect(
        result.trace,
        contains('P9_STATE|symbol-preflight.quiescence-rejected|absent'),
      );
      expect(result.trace, contains('P9_STATE|symbol-preflight.result|absent'));
      expect(result.trace, isNot(contains('symbol_preflight|parse-start')));
      expect(result.log, isNot(contains('command-started|')));
      await harness.expectNoTempOwnersOrFixtureSurvivors(result);
    });
  }
}

Future<void> _expectMalformedTerminalWinner() async {
  await _withHarness((harness) async {
    int? childPid;
    var childStopped = false;
    final result = await harness.run(
      mode: 'success',
      fakeNmMode: 'exact-seven',
      runFakePsMode: 'symbol-authorize-before-data',
      gateSymbolSnapshot: true,
      gateAtomicPrelink: true,
      symbolGateTicks: 6000,
      timeoutValue: '30',
      parentDeadline: const Duration(seconds: 24),
      afterStart: (process, run) async {
        final identity = await run.waitForSymbolSnapshotIdentity(
          process: process,
        );
        childPid = identity.$1;
        run.recordOwnedPid(childPid!);
        try {
          await run.writeOwnedFifo(
            'child.anchor-control.fifo',
            'unexpected symbol-preflight data\n',
          );
          await run.waitForDebugPrelinkStop(process: process);
          childStopped = true;
          await run.releaseSymbolSnapshot();
          await run.waitForOwnedExactFile(
            'symbol-preflight.quiescence-disposition',
            'authorize\n',
            process: process,
          );
          await run.waitForOwnedExactFile(
            'symbol-preflight.quiescence-authorized',
            '',
            process: process,
          );
          File(
            '${run.activeTempOwner.path}/'
            'symbol-preflight.quiescence-disposition',
          ).writeAsStringSync('trailing', mode: FileMode.append);
          expect(Process.killPid(childPid!, ProcessSignal.sigcont), isTrue);
          childStopped = false;
          await run.waitForDebugContinuation(process: process);
        } finally {
          if (childStopped && childPid != null) {
            Process.killPid(childPid!, ProcessSignal.sigcont);
          }
        }
      },
    );
    expect(result.exitCode, 1, reason: result.trace);
    expect(result.stderr, isEmpty);
    expect(result.trace, contains('|cause|protocol|status=1'));
    expect(result.trace, contains('P9_STATE|symbol-preflight.result|absent'));
    expect(result.trace, isNot(contains('symbol_preflight|parse-start')));
    expect(result.log, isNot(contains('command-started|')));
    await harness.expectNoTempOwnersOrFixtureSurvivors(result);
  });
}

Future<void> _expectCandidateOnlyAdmission() async {
  await _withHarness((harness) async {
    int? childPid;
    var parentStopped = false;
    var childStopped = false;
    final result = await harness.run(
      mode: 'success',
      fakeNmMode: 'exact-seven',
      gateAtomicPrelink: true,
      gateAtomicPreAdmission: true,
      timeoutValue: '30',
      parentDeadline: const Duration(seconds: 24),
      afterStart: (process, run) async {
        try {
          await run.waitForDebugPreAdmissionStop(process: process);
          parentStopped = true;
          final childRow = const LineSplitter()
              .convert(run.log.readAsStringSync())
              .singleWhere(
                (line) =>
                    line.startsWith('mkfifo-invoked|') &&
                    line.contains('|child|'),
              )
              .split('|');
          childPid = int.parse(childRow[2]);
          run.recordOwnedPid(childPid!);
          await run.writeOwnedFifo(
            'child.anchor-control.fifo',
            'unexpected symbol-preflight data\n',
          );
          await run.waitForDebugPrelinkStop(process: process);
          childStopped = true;
          await run.waitForOwnedExactFile(
            'symbol-preflight.quiescence-child.candidate',
            'reject:unexpected-data\n',
            process: process,
          );
          expect(
            File(
              '${run.activeTempOwner.path}/'
              'symbol-preflight.quiescence-disposition',
            ).existsSync(),
            isFalse,
          );
          expect(Process.killPid(process.pid, ProcessSignal.sigcont), isTrue);
          parentStopped = false;
          await run.waitForOwnedExactFile(
            'symbol-preflight.quiescence-disposition',
            'authorize\n',
            process: process,
          );
          await run.waitForOwnedExactFile(
            'symbol-preflight.quiescence-authorized',
            '',
            process: process,
          );
          expect(Process.killPid(childPid!, ProcessSignal.sigcont), isTrue);
          childStopped = false;
          await run.waitForDebugContinuation(process: process);
        } finally {
          if (parentStopped) {
            Process.killPid(process.pid, ProcessSignal.sigcont);
          }
          if (childStopped && childPid != null) {
            Process.killPid(childPid!, ProcessSignal.sigcont);
          }
        }
      },
    );
    expect(result.exitCode, 1, reason: result.trace);
    expect(result.stderr, isEmpty);
    expect(result.trace, contains('|cause|protocol|status=1'));
    final disposition = _fsRecord(
      result.trace,
      'symbol-preflight.quiescence-disposition',
    );
    final parent = _fsRecord(
      result.trace,
      'symbol-preflight.quiescence-parent.candidate',
    );
    final child = _fsRecord(
      result.trace,
      'symbol-preflight.quiescence-child.candidate',
    );
    expect(disposition['line'], 'authorize');
    expect(disposition['inode'], parent['inode']);
    expect(disposition['inode'], isNot(child['inode']));
    expect(result.trace, isNot(contains('symbol_preflight|parse-start')));
    expect(result.log, isNot(contains('command-started|')));
    await harness.expectNoTempOwnersOrFixtureSurvivors(result);
  });
}

Future<void> _expectLinkInFlightCoverage() async {
  final source = File(_scriptPath).readAsStringSync();
  final admission = _shellFunction(
    source,
    'admit_symbol_preflight_child_election_prefix',
  );
  final sinkBranch = admission.indexOf(
    r'elif [[ -e "$symbol_preflight_quiescence_child_ln_stderr"',
  );
  final sinkValidation = admission.indexOf(
    r'private_marker_valid "$symbol_preflight_quiescence_child_ln_stderr"',
    sinkBranch,
  );
  final candidateRevalidation = admission.indexOf(
    r'private_marker_valid "$symbol_preflight_quiescence_child_candidate"',
    sinkValidation,
  );
  expect(sinkBranch, greaterThanOrEqualTo(0));
  expect(sinkValidation, greaterThan(sinkBranch));
  expect(candidateRevalidation, greaterThan(sinkValidation));
  expect(
    admission.indexOf('return 0', candidateRevalidation),
    greaterThan(candidateRevalidation),
  );

  final election = _shellFunction(
    source,
    'elect_symbol_preflight_quiescence_disposition',
  );
  final candidateClose = election.indexOf(
    r'symbol_preflight_quiescence_record_is "$candidate" "$value"',
  );
  final sinkRedirection = election.indexOf(
    r'2>"$symbol_preflight_quiescence_child_ln_stderr"',
  );
  final literalLink = election.indexOf(
    r'/bin/ln "$symbol_preflight_quiescence_child_candidate"',
  );
  expect(candidateClose, greaterThanOrEqualTo(0));
  expect(sinkRedirection, greaterThan(candidateClose));
  expect(literalLink, greaterThan(candidateClose));

  await _expectVisibleSinkAdmissionMicroprobe(source);
  await _expectAdjacentContenderWinnerOracle();
}

Future<void> _expectVisibleSinkAdmissionMicroprobe(String source) async {
  final sandbox = await Directory.systemTemp.createTemp(
    'p9-043-visible-sink-admission.',
  );
  try {
    final candidate = File('${sandbox.path}/child.candidate')
      ..writeAsStringSync('reject:unexpected-data\n');
    final sink = File('${sandbox.path}/child.ln.stderr')..createSync();
    final disposition = File('${sandbox.path}/disposition');
    final script = <String>[
      'set -e',
      r'symbol_preflight_quiescence_child_candidate="$1"',
      r'symbol_preflight_quiescence_child_ln_stderr="$2"',
      r'symbol_preflight_quiescence_disposition="$3"',
      _shellFunction(source, 'private_marker_valid'),
      _shellFunction(source, 'admit_symbol_preflight_child_election_prefix'),
      'admit_symbol_preflight_child_election_prefix',
      r'[[ ! -e "$symbol_preflight_quiescence_disposition" && ! -L "$symbol_preflight_quiescence_disposition" ]]',
    ].join('\n');
    final result = await Process.run('/bin/bash', <String>[
      '-c',
      script,
      'p9-043-visible-sink-admission',
      candidate.path,
      sink.path,
      disposition.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(disposition.existsSync(), isFalse);
    expect(candidate.readAsStringSync(), 'reject:unexpected-data\n');
    expect(sink.lengthSync(), 0);
  } finally {
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  }
}

Future<void> _expectAdjacentContenderWinnerOracle() async {
  _expectAtomicDispositionSurface();
  await _withHarness((harness) async {
    final result = await harness.run(
      mode: 'success',
      fakeNmMode: 'exact-seven',
      gateSymbolSnapshot: true,
      timeoutValue: '20',
      parentDeadline: const Duration(seconds: 16),
      afterStart: (process, run) async {
        await run.waitForSymbolSnapshot(process: process);
        await Future.wait(<Future<void>>[
          run.releaseSymbolSnapshot(),
          run.writeOwnedFifo(
            'child.anchor-control.fifo',
            'unexpected symbol-preflight data\n',
          ),
        ]);
      },
    );
    expect(result.exitCode, 1, reason: result.trace);
    final disposition = _fsRecord(
      result.trace,
      'symbol-preflight.quiescence-disposition',
    );
    final parent = _fsRecord(
      result.trace,
      'symbol-preflight.quiescence-parent.candidate',
    );
    final child = _fsRecord(
      result.trace,
      'symbol-preflight.quiescence-child.candidate',
    );
    expect(disposition, isNotEmpty);
    expect(child['line'], 'reject:unexpected-data');
    final parentWon = parent['inode'] == disposition['inode'];
    final childWon = child['inode'] == disposition['inode'];
    expect(parentWon ^ childWon, isTrue, reason: result.trace);
    switch (disposition['line']) {
      case 'authorize':
        expect(parent['line'], 'authorize');
        expect(parentWon, isTrue, reason: result.trace);
        expect(childWon, isFalse, reason: result.trace);
        expect(result.stderr, isEmpty);
        expect(result.trace, contains('|cause|protocol|status=1'));
        expect(
          result.trace,
          contains('P9_STATE|symbol-preflight.quiescence-authorized|present'),
        );
        expect(
          result.trace,
          contains('P9_STATE|symbol-preflight.quiescence-rejected|absent'),
        );
        expect(
          result.trace,
          contains('P9_STATE|symbol-preflight.result|absent'),
        );
        expect(result.trace, isNot(contains('FS|child.candidate|')));
      case 'reject:unexpected-data':
        expect(parentWon, isFalse, reason: result.trace);
        expect(childWon, isTrue, reason: result.trace);
        if (parent.isNotEmpty) {
          expect(parent['line'], 'authorize');
          expect(parent['inode'], isNot(disposition['inode']));
        }
        expect(result.stderr, endsWith(': host nm inspection failed.\n'));
        expect(result.trace, isNot(contains('|cause|protocol|')));
        expect(
          result.trace,
          contains('P9_STATE|symbol-preflight.quiescence-authorized|absent'),
        );
        final parentDerivedRejection = result.trace.contains(
          'symbol_preflight|quiescence-snapshot|decision=reject',
        );
        expect(
          result.trace.contains(
            'P9_STATE|symbol-preflight.quiescence-rejected|present',
          ),
          parentDerivedRejection,
          reason: result.trace,
        );
        expect(
          result.trace,
          contains('P9_STATE|symbol-preflight.result|present'),
        );
        expect(result.trace, contains('FS|child.candidate|'));
      default:
        fail(
          'unknown atomic disposition ${disposition['line']}\n${result.trace}',
        );
    }
    expect(
      result.trace,
      contains('P9_STATE|symbol-preflight.quiescence-closed|absent'),
    );
    expect(result.trace, isNot(contains('symbol_preflight|parse-start')));
    expect(result.log, isNot(contains('command-started|')));
    await harness.expectNoTempOwnersOrFixtureSurvivors(result);
  });
}

Future<void> _expectLifecycleCorrectionSourceGuards() async {
  _expectAtomicDispositionSurface();
  final source = File(_scriptPath).readAsStringSync();
  final holdBoundary = _shellFunction(source, 'evaluate_hold_boundary');
  final authorizedBranch = holdBoundary.substring(
    holdBoundary.indexOf(r'if [[ -e "$authorized" || -L "$authorized" ]]'),
    holdBoundary.indexOf(r'if [[ -e "$rejected" || -L "$rejected" ]]'),
  );
  for (final localPath in <String>[
    r'$symbol_preflight_quiescence_child_candidate',
    r'$symbol_preflight_quiescence_child_ln_stderr',
  ]) {
    expect(authorizedBranch, contains(localPath));
  }

  final parser = _shellFunction(
    source,
    'run_selected_artifact_symbol_preflight',
  );
  final holdCase = parser.substring(
    parser.indexOf(r'case "$hold_result" in'),
    parser.indexOf(r'if [[ "$close_status" -ne 0'),
  );
  final preParserFence = parser.substring(
    parser.indexOf(r'if [[ "$close_status" -ne 0'),
    parser.indexOf('trace_event "symbol_preflight|parse-start"'),
  );
  for (final localPath in <String>[
    r'$symbol_preflight_quiescence_child_candidate',
    r'$symbol_preflight_quiescence_child_ln_stderr',
  ]) {
    expect(holdCase, contains(localPath));
    expect(preParserFence, contains(localPath));
  }
}

Future<void> _expectPostElectionPrecedence(_PostElectionCause cause) async {
  await _withHarness((harness) async {
    int? childPid;
    int? electedInode;
    var causeTriggered = false;
    var parentStopped = false;
    final result = await harness.run(
      mode: 'success',
      fakeNmMode: 'exact-seven',
      runFakePsMode: 'symbol-authorize-before-data',
      gateSymbolSnapshot: true,
      gateAtomicPrelink: true,
      gateAtomicPostlink: true,
      symbolGateTicks: 6000,
      timeoutValue: cause == _PostElectionCause.timeout ? '30' : '20',
      parentDeadline: cause == _PostElectionCause.timeout
          ? const Duration(seconds: 40)
          : const Duration(seconds: 16),
      afterStart: (process, run) async {
        final identity = await run.waitForSymbolSnapshotIdentity(
          process: process,
        );
        childPid = identity.$1;
        run.recordOwnedPid(childPid!);
        try {
          await run.writeOwnedFifo(
            'child.anchor-control.fifo',
            'unexpected symbol-preflight data\n',
          );
          await run.waitForDebugPrelinkStop(process: process);
          await run.expectSoleGroupMember(
            childPid!,
            identity.$2,
            const <String>['T', 't'],
          );
          await run.waitForOwnedExactFile(
            'symbol-preflight.quiescence-child.candidate',
            'reject:unexpected-data\n',
            process: process,
          );
          await run.releaseSymbolSnapshot();
          await run.waitForDebugPostlinkStop(process: process);
          parentStopped = true;
          await run.waitForOwnedExactFile(
            'symbol-preflight.quiescence-disposition',
            'authorize\n',
            process: process,
          );
          expect(
            File(
              '${run.activeTempOwner.path}/'
              'symbol-preflight.quiescence-authorized',
            ).existsSync(),
            isFalse,
          );
          electedInode = await run.ownedInode(
            'symbol-preflight.quiescence-disposition',
          );
          expect(
            electedInode,
            await run.ownedInode(
              'symbol-preflight.quiescence-parent.candidate',
            ),
          );
          expect(
            electedInode,
            isNot(
              await run.ownedInode(
                'symbol-preflight.quiescence-child.candidate',
              ),
            ),
          );
          switch (cause) {
            case _PostElectionCause.interrupt:
              causeTriggered = Process.killPid(
                process.pid,
                ProcessSignal.sigint,
              );
            case _PostElectionCause.terminate:
              causeTriggered = Process.killPid(process.pid);
            case _PostElectionCause.timeout:
              causeTriggered = true;
              await run.waitForOwnedExactFile(
                'outcome',
                'timeout\n',
                process: process,
                timeout: const Duration(seconds: 35),
              );
          }
          expect(causeTriggered, isTrue);
          expect(Process.killPid(process.pid, ProcessSignal.sigcont), isTrue);
          parentStopped = false;
          await run.waitForDebugPostlinkContinuation(process: process);
        } catch (_) {
          if (parentStopped) {
            Process.killPid(process.pid, ProcessSignal.sigcont);
          }
          if (!causeTriggered && childPid != null) {
            Process.killPid(childPid!, ProcessSignal.sigcont);
          }
          rethrow;
        }
      },
    );
    final expectedStatus = switch (cause) {
      _PostElectionCause.interrupt => 130,
      _PostElectionCause.terminate => 143,
      _PostElectionCause.timeout => 124,
    };
    expect(result.exitCode, expectedStatus, reason: result.trace);
    if (cause == _PostElectionCause.timeout) {
      expect(result.stderr, _timeoutDiagnosticFor(30));
    } else {
      expect(result.stderr, isEmpty);
    }
    expect(result.stderr, isNot(contains('OpenTUI symbol preflight')));
    final disposition = _fsRecord(
      result.trace,
      'symbol-preflight.quiescence-disposition',
    );
    final parent = _fsRecord(
      result.trace,
      'symbol-preflight.quiescence-parent.candidate',
    );
    final child = _fsRecord(
      result.trace,
      'symbol-preflight.quiescence-child.candidate',
    );
    expect(disposition['line'], 'authorize');
    expect(disposition['size'], '10');
    expect(disposition['inode'], '$electedInode');
    expect(parent['inode'], disposition['inode']);
    expect(parent['line'], 'authorize');
    expect(child['inode'], isNot(disposition['inode']));
    expect(child['line'], 'reject:unexpected-data');
    expect(
      result.trace,
      contains('P9_STATE|symbol-preflight.quiescence-authorized|absent'),
    );
    expect(
      result.trace,
      contains('P9_STATE|symbol-preflight.quiescence-rejected|absent'),
    );
    expect(result.trace, contains('P9_STATE|symbol-preflight.result|absent'));
    expect(result.trace, isNot(contains('FS|child.candidate|')));
    expect(
      result.trace,
      contains('P9_STATE|symbol-preflight.quiescence-closed|absent'),
    );
    expect(result.trace, isNot(contains('symbol_preflight|parse-start')));
    expect(result.log, isNot(contains('command-started|')));
    await harness.expectNoTempOwnersOrFixtureSurvivors(result);
  });
}

Future<void> _withHarness(
  Future<void> Function(_Harness harness) body, {
  String? fakePsMode,
}) async {
  final harness = await _Harness.create(fakePsMode: fakePsMode);
  try {
    await body(harness);
  } finally {
    await harness.dispose();
  }
}

final class _Harness {
  _Harness._({
    required this.sandbox,
    required this.tempRoot,
    required this.binDirectory,
    required this.realPs,
    required this.realStat,
    required this.realMkfifo,
    required this.fakePsMode,
  });

  final Directory sandbox;
  final Directory tempRoot;
  final Directory binDirectory;
  final String realPs;
  final String realStat;
  final String realMkfifo;
  final String? fakePsMode;
  final Set<int> _emergencyPids = <int>{};
  int _runSequence = 0;

  static Future<_Harness> create({String? fakePsMode}) async {
    final createdSandbox = await Directory.systemTemp.createTemp(
      'p9-042-wrapper.',
    );
    final sandbox = Directory(createdSandbox.resolveSymbolicLinksSync());
    final tempRoot = await Directory('${sandbox.path}/tmp').create();
    final binDirectory = await Directory('${sandbox.path}/bin').create();
    final realPs = await _executablePath('ps');
    final realStat = await _executablePath('stat');
    final realMkfifo = await _executablePath('mkfifo');

    final fakeGo = await File(
      '$_fixtureDirectory/fake_go.sh',
    ).copy('${binDirectory.path}/go');
    await Process.run('chmod', ['700', fakeGo.path]);
    final fakeMktemp = await File(
      '$_fixtureDirectory/fake_mktemp.sh',
    ).copy('${binDirectory.path}/mktemp');
    await Process.run('chmod', ['700', fakeMktemp.path]);
    final fakePs = await File(
      '$_fixtureDirectory/fake_ps.sh',
    ).copy('${binDirectory.path}/ps');
    await Process.run('chmod', ['700', fakePs.path]);
    final fakeRm = await File(
      '$_fixtureDirectory/fake_rm.sh',
    ).copy('${binDirectory.path}/rm');
    await Process.run('chmod', ['700', fakeRm.path]);
    final fakeMkfifo = await File(
      '$_fixtureDirectory/fake_mkfifo.sh',
    ).copy('${binDirectory.path}/mkfifo');
    await Process.run('chmod', ['700', fakeMkfifo.path]);
    final fakeStat = await File(
      '$_fixtureDirectory/fake_stat.sh',
    ).copy('${binDirectory.path}/stat');
    await Process.run('chmod', ['700', fakeStat.path]);

    return _Harness._(
      sandbox: sandbox,
      tempRoot: tempRoot,
      binDirectory: binDirectory,
      realPs: realPs,
      realStat: realStat,
      realMkfifo: realMkfifo,
      fakePsMode: fakePsMode,
    );
  }

  String get goToolDirectory =>
      Directory('tools/parity/go_snapshot').absolute.path;

  List<Directory> get tempOwners => tempRoot
      .listSync()
      .whereType<Directory>()
      .where(
        (entry) => entry.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('opentui-go-snapshot.'),
      )
      .toList();

  List<FileSystemEntity> get tempEntries => tempRoot.listSync();

  Future<_RunResult> run({
    required String mode,
    List<String> arguments = const <String>[],
    List<String> bashArguments = const <String>[],
    String? timeoutValue = '10',
    String? runFakePsMode,
    String fakeMktempMode = 'normal',
    String fakeRmMode = 'normal',
    String fakeMkfifoMode = 'normal',
    String fakeMkfifoApplyTo = 'all',
    String fakeStatMode = 'passthrough',
    String? fakeNmMode,
    bool invalidNmPath = false,
    bool gateSetupSnapshot = false,
    bool gateSymbolSnapshot = false,
    bool gateAtomicPrelink = false,
    bool gateAtomicPostlink = false,
    bool gateAtomicPreAdmission = false,
    bool gateAtomicChildPostlink = false,
    int symbolGateTicks = 1000,
    String? gatePostWorkLabel,
    bool openCallerFixedFds = false,
    String? missingTool,
    Map<String, String> extraEnvironment = const <String, String>{},
    Duration parentDeadline = const Duration(seconds: 15),
    Duration streamDeadline = const Duration(seconds: 2),
    Future<void> Function(Process process, _RunObservation run)? afterStart,
  }) async {
    _runSequence += 1;
    final log = File('${sandbox.path}/run-$_runSequence.log');
    final observation = File(
      '${sandbox.path}/run-$_runSequence.observation.log',
    );
    final counter = File('${sandbox.path}/ps-$_runSequence.count');
    final commandGate = File('${sandbox.path}/run-$_runSequence.command-gate');
    final psMarker = File('${sandbox.path}/run-$_runSequence.ps-marker');
    final psGate = File('${sandbox.path}/run-$_runSequence.ps-gate');
    final setupSnapshotMarker = File(
      '${sandbox.path}/run-$_runSequence.setup-snapshot-marker',
    );
    final setupSnapshotGate = File(
      '${sandbox.path}/run-$_runSequence.setup-snapshot-gate',
    );
    final symbolSnapshotMarker = File(
      '${sandbox.path}/run-$_runSequence.symbol-snapshot-marker',
    );
    final symbolSnapshotGate = File(
      '${sandbox.path}/run-$_runSequence.symbol-snapshot-gate',
    );
    final symbolSnapshotCapture = File(
      '${sandbox.path}/run-$_runSequence.symbol-snapshot-capture',
    );
    final debugBootstrap = File(
      '${sandbox.path}/run-$_runSequence.p9_043_debug_gate.bash',
    );
    final debugPrelinkStopped = File(
      '${sandbox.path}/run-$_runSequence.prelink-stopped',
    );
    final debugContinued = File('${sandbox.path}/run-$_runSequence.continued');
    final debugPostlinkStopped = File(
      '${sandbox.path}/run-$_runSequence.postlink-stopped',
    );
    final debugPostlinkContinued = File(
      '${sandbox.path}/run-$_runSequence.postlink-continued',
    );
    final debugPreAdmissionStopped = File(
      '${sandbox.path}/run-$_runSequence.pre-admission-stopped',
    );
    final debugPreAdmissionContinued = File(
      '${sandbox.path}/run-$_runSequence.pre-admission-continued',
    );
    final debugChildPostlinkStopped = File(
      '${sandbox.path}/run-$_runSequence.child-postlink-stopped',
    );
    final debugChildPostlinkContinued = File(
      '${sandbox.path}/run-$_runSequence.child-postlink-continued',
    );
    final debugStartFifo = File(
      '${sandbox.path}/run-$_runSequence.debug-start.fifo',
    );
    final debugSupervisorPid = File(
      '${sandbox.path}/run-$_runSequence.debug-supervisor.pid',
    );
    final debugStarted = File(
      '${sandbox.path}/run-$_runSequence.debug-started',
    );
    final debugHookFailed = File(
      '${sandbox.path}/run-$_runSequence.hook-failed',
    );
    if (gateAtomicPrelink ||
        gateAtomicPostlink ||
        gateAtomicPreAdmission ||
        gateAtomicChildPostlink) {
      await File(
        '$_fixtureDirectory/p9_043_debug_gate.bash',
      ).copy(debugBootstrap.path);
    }
    if (gateAtomicPostlink || gateAtomicPreAdmission) {
      final mkfifo = await Process.run(realMkfifo, <String>[
        debugStartFifo.path,
      ]);
      expect(mkfifo.exitCode, 0, reason: mkfifo.stderr as String);
      final chmod = await Process.run('chmod', <String>[
        '600',
        debugStartFifo.path,
      ]);
      expect(chmod.exitCode, 0, reason: chmod.stderr as String);
    }
    final postWorkSnapshotMarker = File(
      '${sandbox.path}/run-$_runSequence.post-work-snapshot-marker',
    );
    final postWorkSnapshotGate = File(
      '${sandbox.path}/run-$_runSequence.post-work-snapshot-gate',
    );
    final statMarker = File('${sandbox.path}/run-$_runSequence.stat-marker');
    final statRelease = File('${sandbox.path}/run-$_runSequence.stat-release');
    final nmDirectory = Directory(
      '${sandbox.path}/run-$_runSequence.nm-bin${invalidNmPath ? '\r' : ''}',
    );
    final nmEvents = File('${nmDirectory.path}/events');
    final symbolRawCapture = Directory(
      '${sandbox.path}/run-$_runSequence.symbol-raw-capture',
    );
    if (fakeRmMode == 'capture-symbol-raw') {
      await symbolRawCapture.create();
    }
    if (fakeNmMode != null) {
      await nmDirectory.create();
      await File('${nmDirectory.path}/mode').writeAsString('$fakeNmMode\n');
      await nmEvents.create();
      final fakeNm = await File(
        '$_fixtureDirectory/fake_nm.sh',
      ).copy('${nmDirectory.path}/nm');
      await Process.run('chmod', ['700', fakeNm.path]);
    }
    final outsideFifo = File('${sandbox.path}/outside-fifo-$_runSequence');
    final fifoSymlinkTarget = File(
      '${sandbox.path}/fifo-symlink-target-$_runSequence',
    );
    final outsideTemp = Directory(
      '${sandbox.path}/outside/opentui-go-snapshot.outside-$_runSequence',
    );
    if (fakeMktempMode == 'out-of-root') {
      await outsideTemp.parent.create();
    }
    final symlinkTarget = Directory(
      '${sandbox.path}/symlink-target-$_runSequence',
    );
    final symlinkPath = Link(
      '${tempRoot.path}/opentui-go-snapshot.symlink-$_runSequence',
    );
    final selectedPsMode = runFakePsMode ?? fakePsMode ?? 'passthrough';
    var path = '${binDirectory.path}:${Platform.environment['PATH'] ?? ''}';
    if (fakeNmMode != null) {
      path = '${nmDirectory.path}:$path';
    }
    if (missingTool != null) {
      path = await _isolatedPathWithout(missingTool, _runSequence);
    }
    final environment = Map<String, String>.of(Platform.environment)
      ..['PATH'] = path
      ..['TMPDIR'] = '${tempRoot.path}/'
      ..['GO_SNAPSHOT_TEST_MODE'] = mode
      ..['GO_SNAPSHOT_TEST_LOG'] = log.path
      ..['GO_SNAPSHOT_TEST_OBSERVATION'] = observation.path
      ..['GO_SNAPSHOT_REAL_PS'] = realPs
      ..['GO_SNAPSHOT_REAL_STAT'] = realStat
      ..['GO_SNAPSHOT_REAL_MKFIFO'] = realMkfifo
      ..['GO_SNAPSHOT_DESCENDANT_FIXTURE'] = File(
        '$_fixtureDirectory/fake_descendant.pl',
      ).absolute.path
      ..['GO_SNAPSHOT_VISIBLE_COMMAND_FIXTURE'] = File(
        '$_fixtureDirectory/fake_visible_command.pl',
      ).absolute.path
      ..['GO_SNAPSHOT_FAKE_PS_COUNTER'] = counter.path
      ..['GO_SNAPSHOT_FAKE_PS_MODE'] = selectedPsMode
      ..['GO_SNAPSHOT_FAKE_PS_MARKER'] = psMarker.path
      ..['GO_SNAPSHOT_FAKE_PS_GATE'] = psGate.path
      ..['GO_SNAPSHOT_FAKE_PS_SETUP_MARKER'] = gateSetupSnapshot
          ? setupSnapshotMarker.path
          : ''
      ..['GO_SNAPSHOT_FAKE_PS_SETUP_GATE'] = gateSetupSnapshot
          ? setupSnapshotGate.path
          : ''
      ..['GO_SNAPSHOT_FAKE_PS_SYMBOL_MARKER'] = gateSymbolSnapshot
          ? symbolSnapshotMarker.path
          : ''
      ..['GO_SNAPSHOT_FAKE_PS_SYMBOL_GATE'] = gateSymbolSnapshot
          ? symbolSnapshotGate.path
          : ''
      ..['GO_SNAPSHOT_FAKE_PS_SYMBOL_CAPTURE'] = gateAtomicPrelink
          ? symbolSnapshotCapture.path
          : ''
      ..['GO_SNAPSHOT_FAKE_PS_SYMBOL_GATE_TICKS'] = '$symbolGateTicks'
      ..['GO_SNAPSHOT_FAKE_PS_POST_LABEL'] = gatePostWorkLabel ?? ''
      ..['GO_SNAPSHOT_FAKE_PS_POST_MARKER'] = gatePostWorkLabel == null
          ? ''
          : postWorkSnapshotMarker.path
      ..['GO_SNAPSHOT_FAKE_PS_POST_GATE'] = gatePostWorkLabel == null
          ? ''
          : postWorkSnapshotGate.path
      ..['GO_SNAPSHOT_COMMAND_GATE'] = commandGate.path
      ..['GO_SNAPSHOT_FAKE_MKTEMP_MODE'] = fakeMktempMode
      ..['GO_SNAPSHOT_FAKE_MKTEMP_OUTSIDE'] = outsideTemp.path
      ..['GO_SNAPSHOT_FAKE_MKTEMP_LINK'] = symlinkPath.path
      ..['GO_SNAPSHOT_FAKE_MKTEMP_TARGET'] = symlinkTarget.path
      ..['GO_SNAPSHOT_FAKE_RM_MODE'] = fakeRmMode
      ..['GO_SNAPSHOT_FAKE_RM_RAW_CAPTURE'] = symbolRawCapture.path
      ..['GO_SNAPSHOT_FAKE_MKFIFO_MODE'] = fakeMkfifoMode
      ..['GO_SNAPSHOT_FAKE_MKFIFO_APPLY_TO'] = fakeMkfifoApplyTo
      ..['GO_SNAPSHOT_FAKE_MKFIFO_OUTSIDE'] = outsideFifo.path
      ..['GO_SNAPSHOT_FAKE_MKFIFO_SYMLINK_TARGET'] = fifoSymlinkTarget.path
      ..['GO_SNAPSHOT_FAKE_MKFIFO_PID_LOG'] = log.path
      ..['GO_SNAPSHOT_FAKE_STAT_MODE'] = fakeStatMode
      ..['GO_SNAPSHOT_FAKE_STAT_MARKER'] = statMarker.path
      ..['GO_SNAPSHOT_FAKE_STAT_RELEASE'] = statRelease.path
      ..addAll(extraEnvironment);
    if (gateAtomicPrelink) {
      environment
        ..['BASH_ENV'] = debugBootstrap.path
        ..['P9_043_DEBUG_PRELINK_STOPPED'] = debugPrelinkStopped.path
        ..['P9_043_DEBUG_CONTINUED'] = debugContinued.path
        ..['P9_043_DEBUG_HOOK_FAILED'] = debugHookFailed.path;
    }
    if (gateAtomicPostlink) {
      environment
        ..['BASH_ENV'] = debugBootstrap.path
        ..['P9_043_DEBUG_START_FIFO'] = debugStartFifo.path
        ..['P9_043_DEBUG_SUPERVISOR_PID_FILE'] = debugSupervisorPid.path
        ..['P9_043_DEBUG_STARTED'] = debugStarted.path
        ..['P9_043_DEBUG_POSTLINK_STOPPED'] = debugPostlinkStopped.path
        ..['P9_043_DEBUG_POSTLINK_CONTINUED'] = debugPostlinkContinued.path
        ..['P9_043_DEBUG_HOOK_FAILED'] = debugHookFailed.path;
    }
    if (gateAtomicPreAdmission) {
      environment
        ..['BASH_ENV'] = debugBootstrap.path
        ..['P9_043_DEBUG_START_FIFO'] = debugStartFifo.path
        ..['P9_043_DEBUG_SUPERVISOR_PID_FILE'] = debugSupervisorPid.path
        ..['P9_043_DEBUG_STARTED'] = debugStarted.path
        ..['P9_043_DEBUG_PRE_ADMISSION_STOPPED'] = debugPreAdmissionStopped.path
        ..['P9_043_DEBUG_PRE_ADMISSION_CONTINUED'] =
            debugPreAdmissionContinued.path
        ..['P9_043_DEBUG_HOOK_FAILED'] = debugHookFailed.path;
    }
    if (gateAtomicChildPostlink) {
      environment
        ..['BASH_ENV'] = debugBootstrap.path
        ..['P9_043_DEBUG_CHILD_POSTLINK_STOPPED'] =
            debugChildPostlinkStopped.path
        ..['P9_043_DEBUG_CHILD_POSTLINK_CONTINUED'] =
            debugChildPostlinkContinued.path
        ..['P9_043_DEBUG_HOOK_FAILED'] = debugHookFailed.path;
    }
    if (timeoutValue == null) {
      environment.remove('GO_SNAPSHOT_TIMEOUT_SECONDS');
    } else {
      environment['GO_SNAPSHOT_TIMEOUT_SECONDS'] = timeoutValue;
    }

    const executable = '/bin/bash';
    var processArguments = <String>[
      ...bashArguments,
      File(_scriptPath).absolute.path,
      ...arguments,
    ];
    if (openCallerFixedFds) {
      processArguments = <String>[
        '-c',
        r'exec 8<>/dev/null; exec 9<>/dev/null; exec /bin/bash "$@"',
        'p9-042-fixed-fds',
        ...processArguments,
      ];
    }
    final process = await Process.start(
      executable,
      processArguments,
      environment: environment,
      workingDirectory: Directory.current.path,
    );
    _emergencyPids.add(process.pid);
    if (gateAtomicPostlink || gateAtomicPreAdmission) {
      await debugSupervisorPid.writeAsString('${process.pid}\n', flush: true);
      _writeStartFifoToken(debugStartFifo);
      final startDeadline = DateTime.now().add(const Duration(seconds: 5));
      while (!debugStarted.existsSync() &&
          DateTime.now().isBefore(startDeadline)) {
        if (await _futureCompleted(process.exitCode)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      var bootstrapDiagnostics = 'DEBUG bootstrap did not start';
      if (!debugStarted.existsSync()) {
        final ps = await Process.run(realPs, <String>[
          '-o',
          'pid=,ppid=,pgid=,stat=,command=',
          '-p',
          '${process.pid}',
        ]);
        bootstrapDiagnostics =
            'DEBUG bootstrap did not start; '
            'pid=${process.pid}; ps=${ps.stdout}; '
            'pidFile=${debugSupervisorPid.existsSync() ? debugSupervisorPid.readAsStringSync() : '<missing>'}; '
            'hook=${debugHookFailed.existsSync() ? debugHookFailed.readAsStringSync() : '<missing>'}; '
            'entries=${sandbox.listSync().map((entry) => entry.path.split(Platform.pathSeparator).last).toList()}';
      }
      expect(
        debugStarted.existsSync(),
        isTrue,
        reason: debugHookFailed.existsSync()
            ? debugHookFailed.readAsStringSync()
            : bootstrapDiagnostics,
      );
    }
    final runObservation = _RunObservation(
      harness: this,
      log: log,
      observation: observation,
      counter: counter,
      commandGate: commandGate,
      psMarker: psMarker,
      psGate: psGate,
      setupSnapshotMarker: setupSnapshotMarker,
      setupSnapshotGate: setupSnapshotGate,
      symbolSnapshotMarker: symbolSnapshotMarker,
      symbolSnapshotGate: symbolSnapshotGate,
      symbolSnapshotCapture: symbolSnapshotCapture,
      debugPrelinkStopped: debugPrelinkStopped,
      debugContinued: debugContinued,
      debugPostlinkStopped: debugPostlinkStopped,
      debugPostlinkContinued: debugPostlinkContinued,
      debugPreAdmissionStopped: debugPreAdmissionStopped,
      debugPreAdmissionContinued: debugPreAdmissionContinued,
      debugChildPostlinkStopped: debugChildPostlinkStopped,
      debugChildPostlinkContinued: debugChildPostlinkContinued,
      debugHookFailed: debugHookFailed,
      postWorkSnapshotMarker: postWorkSnapshotMarker,
      postWorkSnapshotGate: postWorkSnapshotGate,
      statMarker: statMarker,
      statRelease: statRelease,
      outsideFifo: outsideFifo,
      fifoSymlinkTarget: fifoSymlinkTarget,
      outsideTemp: outsideTemp,
      symlinkPath: symlinkPath,
      symlinkTarget: symlinkTarget,
      nmDirectory: nmDirectory,
      nmEvents: nmEvents,
      process: process,
      assertionPids: <int>{process.pid},
    );
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    var stdoutClosed = false;
    var stderrClosed = false;
    process.stdout
        .transform(utf8.decoder)
        .listen(
          stdout.write,
          onDone: () {
            stdoutClosed = true;
            stdoutDone.complete();
          },
          onError: stdoutDone.completeError,
        );
    process.stderr
        .transform(utf8.decoder)
        .listen(
          stderr.write,
          onDone: () {
            stderrClosed = true;
            stderrDone.complete();
          },
          onError: stderrDone.completeError,
        );

    try {
      if (afterStart != null) {
        await afterStart(process, runObservation);
      }

      final exitCode = await process.exitCode.timeout(
        parentDeadline,
        onTimeout: () async {
          await runObservation.recordDescendants(
            process.pid,
            assertionOwned: false,
          );
          await _terminateEmergencyPids();
          throw TimeoutException(
            'wrapper exceeded hard parent deadline $parentDeadline in $mode',
            parentDeadline,
          );
        },
      );
      var streamsClosed = true;
      try {
        await Future.wait(<Future<void>>[
          stdoutDone.future,
          stderrDone.future,
        ]).timeout(streamDeadline);
      } on TimeoutException {
        streamsClosed = false;
      }
      final logText = log.existsSync() ? await log.readAsString() : '';
      var traceText = observation.existsSync()
          ? await observation.readAsString()
          : '';
      if (traceText.isEmpty) {
        for (final owner in tempOwners) {
          final privateTrace = File('${owner.path}/supervisor.shell.stderr');
          if (privateTrace.existsSync()) {
            traceText += await privateTrace.readAsString();
          }
        }
      }
      final fixturePids = _fixturePids(logText);
      final tracePids = _tracePids(traceText);
      runObservation.assertionPids.addAll(fixturePids);
      runObservation.assertionPids.addAll(tracePids);
      _emergencyPids
        ..addAll(fixturePids)
        ..addAll(tracePids);
      final nmEventsText = nmEvents.existsSync()
          ? await nmEvents.readAsString()
          : '';
      final nmPids = _nmPids(nmEventsText);
      runObservation.assertionPids.addAll(nmPids);
      _emergencyPids.addAll(nmPids);
      final result = _RunResult(
        exitCode: exitCode,
        stdout: stdout.toString(),
        stderr: stderr.toString(),
        streamsClosed: streamsClosed,
        stdoutClosed: stdoutClosed,
        stderrClosed: stderrClosed,
        stdoutDone: stdoutDone.future,
        log: logText,
        trace: traceText,
        directPid: process.pid,
        recordedPids: fixturePids,
        assertionPids: Set<int>.of(runObservation.assertionPids),
        nmEvents: nmEventsText,
        symbolRawCapture: symbolRawCapture,
      );
      return result;
    } catch (_) {
      await runObservation.recordDescendants(
        process.pid,
        assertionOwned: false,
      );
      await _terminateEmergencyPids();
      rethrow;
    }
  }

  Future<String> _isolatedPathWithout(String missingTool, int sequence) async {
    final directory = await Directory(
      '${sandbox.path}/isolated-path-$sequence',
    ).create();
    final tools = <String>[
      'bash',
      'go',
      'pkg-config',
      'uname',
      'tr',
      'mktemp',
      'mkdir',
      'rm',
      'ps',
      'stat',
      'mkfifo',
      'nm',
    ];
    for (final tool in tools.where((tool) => tool != missingTool)) {
      final source = switch (tool) {
        'bash' => '/bin/bash',
        'go' ||
        'mktemp' ||
        'rm' ||
        'ps' ||
        'stat' ||
        'mkfifo' => '${binDirectory.path}/$tool',
        _ => await _executablePath(tool),
      };
      await Link('${directory.path}/$tool').create(source);
    }
    return directory.path;
  }

  Future<void> expectNoTempOwnersOrFixtureSurvivors(_RunResult result) async {
    expect(tempRoot.listSync(), isEmpty, reason: 'wrapper temp owner remained');
    await expectNoOwnedSurvivors(result);
  }

  Future<void> expectNoFixtureSurvivors(_RunResult result) =>
      expectNoOwnedSurvivors(result);

  Future<void> expectNoOwnedSurvivors(_RunResult result) async {
    expect(
      result.streamsClosed,
      isTrue,
      reason: 'owned descendants retained caller streams after wrapper exit',
    );
    for (final pid in result.assertionPids) {
      expect(
        await _pidExists(pid),
        isFalse,
        reason: 'assertion-owned PID $pid survived wrapper exit',
      );
    }
  }

  Future<void> waitForAssertionPidsToExit(
    _RunResult result,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      var found = false;
      for (final pid in result.assertionPids) {
        if (await _pidExists(pid)) {
          found = true;
          break;
        }
      }
      if (!found) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _terminateEmergencyPids() async {
    final pids = _emergencyPids.toList().reversed;
    for (final pid in pids) {
      if (await _pidExists(pid)) {
        Process.killPid(pid, ProcessSignal.sigkill);
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }

  Future<void> dispose() async {
    await _terminateEmergencyPids();
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  }
}

final class _RunObservation {
  _RunObservation({
    required this.harness,
    required this.log,
    required this.observation,
    required this.counter,
    required this.commandGate,
    required this.psMarker,
    required this.psGate,
    required this.setupSnapshotMarker,
    required this.setupSnapshotGate,
    required this.symbolSnapshotMarker,
    required this.symbolSnapshotGate,
    required this.symbolSnapshotCapture,
    required this.debugPrelinkStopped,
    required this.debugContinued,
    required this.debugPostlinkStopped,
    required this.debugPostlinkContinued,
    required this.debugPreAdmissionStopped,
    required this.debugPreAdmissionContinued,
    required this.debugChildPostlinkStopped,
    required this.debugChildPostlinkContinued,
    required this.debugHookFailed,
    required this.postWorkSnapshotMarker,
    required this.postWorkSnapshotGate,
    required this.statMarker,
    required this.statRelease,
    required this.outsideFifo,
    required this.fifoSymlinkTarget,
    required this.outsideTemp,
    required this.symlinkPath,
    required this.symlinkTarget,
    required this.nmDirectory,
    required this.nmEvents,
    required this.process,
    required this.assertionPids,
  });

  final _Harness harness;
  final File log;
  final File observation;
  final File counter;
  final File commandGate;
  final File psMarker;
  final File psGate;
  final File setupSnapshotMarker;
  final File setupSnapshotGate;
  final File symbolSnapshotMarker;
  final File symbolSnapshotGate;
  final File symbolSnapshotCapture;
  final File debugPrelinkStopped;
  final File debugContinued;
  final File debugPostlinkStopped;
  final File debugPostlinkContinued;
  final File debugPreAdmissionStopped;
  final File debugPreAdmissionContinued;
  final File debugChildPostlinkStopped;
  final File debugChildPostlinkContinued;
  final File debugHookFailed;
  final File postWorkSnapshotMarker;
  final File postWorkSnapshotGate;
  final File statMarker;
  final File statRelease;
  final File outsideFifo;
  final File fifoSymlinkTarget;
  final Directory outsideTemp;
  final Link symlinkPath;
  final Directory symlinkTarget;
  final Directory nmDirectory;
  final File nmEvents;
  final Process process;
  final Set<int> assertionPids;

  void recordOwnedPid(int pid) {
    assertionPids.add(pid);
    harness._emergencyPids.add(pid);
  }

  Future<void> waitForPsCount(int expected, {required Process process}) async {
    await _poll(
      description: 'ps call $expected',
      process: process,
      predicate: () {
        if (!counter.existsSync()) {
          return false;
        }
        final value = int.tryParse(counter.readAsStringSync().trim()) ?? 0;
        return value >= expected;
      },
    );
  }

  Future<void> waitForPsMarker({required Process process}) async {
    await _poll(
      description: 'validation-drain ps marker',
      process: process,
      predicate: psMarker.existsSync,
    );
  }

  Future<void> waitForSetupSnapshot({required Process process}) async {
    await _poll(
      description: 'setup quiescence snapshot',
      process: process,
      predicate: setupSnapshotMarker.existsSync,
    );
  }

  Future<void> releaseSetupSnapshot() => setupSnapshotGate.create();

  Future<void> waitForSymbolSnapshot({required Process process}) async {
    await _poll(
      description: 'P9-043 symbol quiescence snapshot',
      process: process,
      predicate: () {
        if (debugHookFailed.existsSync()) {
          throw TestFailure(
            'P9-043 DEBUG hook failed: ${debugHookFailed.readAsStringSync()}',
          );
        }
        return symbolSnapshotMarker.existsSync();
      },
    );
  }

  Future<(int, int, String)> waitForSymbolSnapshotIdentity({
    required Process process,
  }) async {
    await waitForSymbolSnapshot(process: process);
    final fields = symbolSnapshotMarker.readAsStringSync().trim().split('|');
    expect(fields, hasLength(4));
    expect(fields[3], 'captured');
    return (int.parse(fields[0]), int.parse(fields[1]), fields[2]);
  }

  Future<void> releaseSymbolSnapshot() => symbolSnapshotGate.create();

  Future<void> waitForDebugPrelinkStop({required Process process}) async {
    await _poll(
      description: 'P9-043 child prelink DEBUG stop',
      process: process,
      predicate: () {
        if (debugHookFailed.existsSync()) {
          throw TestFailure(
            'P9-043 DEBUG hook failed: ${debugHookFailed.readAsStringSync()}',
          );
        }
        return debugPrelinkStopped.existsSync() &&
            debugPrelinkStopped.readAsStringSync() ==
                'ready|reject:unexpected-data\n';
      },
    );
    expect(debugHookFailed.existsSync(), isFalse);
  }

  Future<void> waitForDebugContinuation({required Process process}) async {
    await _poll(
      description: 'P9-043 child prelink DEBUG continuation',
      process: process,
      predicate: () =>
          debugContinued.existsSync() &&
          debugContinued.readAsStringSync() == 'continued\n',
    );
    expect(debugHookFailed.existsSync(), isFalse);
  }

  Future<void> waitForDebugPostlinkStop({required Process process}) async {
    await _poll(
      description: 'P9-043 parent postlink DEBUG stop',
      process: process,
      predicate: () {
        if (debugHookFailed.existsSync()) {
          throw TestFailure(
            'P9-043 DEBUG hook failed: ${debugHookFailed.readAsStringSync()}',
          );
        }
        return debugPostlinkStopped.existsSync() &&
            debugPostlinkStopped.readAsStringSync() == 'ready|authorize\n';
      },
    );
    expect(debugHookFailed.existsSync(), isFalse);
  }

  Future<void> waitForDebugPostlinkContinuation({
    required Process process,
  }) async {
    await _poll(
      description: 'P9-043 parent postlink DEBUG continuation',
      process: process,
      predicate: () =>
          debugPostlinkContinued.existsSync() &&
          debugPostlinkContinued.readAsStringSync() == 'continued|authorize\n',
    );
    expect(debugHookFailed.existsSync(), isFalse);
  }

  Future<void> waitForDebugPreAdmissionStop({required Process process}) async {
    await _poll(
      description: 'P9-043 supervisor pre-admission DEBUG stop',
      process: process,
      predicate: () =>
          debugPreAdmissionStopped.existsSync() &&
          debugPreAdmissionStopped.readAsStringSync() ==
              'ready|pre-admission\n',
    );
    expect(debugHookFailed.existsSync(), isFalse);
  }

  Future<void> waitForDebugChildPostlinkStop({required Process process}) async {
    await _poll(
      description: 'P9-043 child postlink DEBUG stop',
      process: process,
      predicate: () {
        if (debugHookFailed.existsSync()) {
          throw TestFailure(debugHookFailed.readAsStringSync());
        }
        return debugChildPostlinkStopped.existsSync() &&
            debugChildPostlinkStopped.readAsStringSync() ==
                'ready|child-winner\n';
      },
    );
  }

  Future<void> waitForOwnedExactFile(
    String basename,
    String contents, {
    required Process process,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await _poll(
      description: '$basename=$contents',
      process: process,
      predicate: () {
        final owners = harness.tempOwners;
        if (owners.length != 1) return false;
        final path = File('${owners.single.path}/$basename');
        return path.existsSync() &&
            !Link(path.path).existsSync() &&
            path.readAsStringSync() == contents;
      },
      timeout: timeout,
    );
  }

  Future<int> ownedInode(String basename) async {
    final path = '${activeTempOwner.path}/$basename';
    final result = await Process.run(
      realStatPath,
      Platform.isMacOS
          ? <String>['-f', '%i', path]
          : <String>['-c', '%i', path],
    );
    expect(result.exitCode, 0, reason: result.stderr as String);
    return int.parse((result.stdout as String).trim());
  }

  Future<void> expectSoleGroupMember(
    int pid,
    int pgid,
    Iterable<String> statePrefixes,
  ) async {
    final result = await Process.run(realPsPath, <String>[
      '-axo',
      'pid=,pgid=,stat=',
    ]);
    expect(result.exitCode, 0, reason: result.stderr as String);
    final members = <(int, int, String)>[];
    for (final line in const LineSplitter().convert(result.stdout as String)) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 3) continue;
      final rowPid = int.tryParse(fields[0]);
      final rowPgid = int.tryParse(fields[1]);
      if (rowPid != null && rowPgid != null && rowPgid == pgid) {
        members.add((rowPid, rowPgid, fields[2]));
      }
    }
    expect(members, hasLength(1));
    expect(members.single.$1, pid);
    expect(members.single.$2, pgid);
    expect(
      statePrefixes.any(members.single.$3.startsWith),
      isTrue,
      reason: 'unexpected process state ${members.single.$3}',
    );
  }

  Future<void> waitForNmEvent(String needle, {required Process process}) async {
    await _poll(
      description: 'nm event $needle',
      process: process,
      predicate: () =>
          nmEvents.existsSync() && nmEvents.readAsStringSync().contains(needle),
    );
  }

  Future<void> releaseNmAppend() =>
      File('${nmDirectory.path}/append-gate').create();

  Future<void> releaseNmTool() =>
      File('${nmDirectory.path}/release-gate').create();

  Future<void> waitForNmAppend({required Process process}) async {
    await _poll(
      description: 'nm delayed append completion',
      process: process,
      predicate: File('${nmDirectory.path}/append-complete').existsSync,
    );
  }

  File get setupGateOnce => File('${counter.path}.setup-gated');

  Future<(int, int)> waitForSetupSnapshotIdentity({
    required Process process,
  }) async {
    await waitForSetupSnapshot(process: process);
    final fields = setupSnapshotMarker.readAsStringSync().trim().split('|');
    expect(fields, hasLength(3));
    expect(fields[2], 'setup-held');
    return (int.parse(fields[0]), int.parse(fields[1]));
  }

  Future<void> waitForPostWorkSnapshot({required Process process}) async {
    await _poll(
      description: 'post-work cleanup snapshot',
      process: process,
      predicate: postWorkSnapshotMarker.existsSync,
    );
  }

  Future<void> releasePostWorkSnapshot() => postWorkSnapshotGate.create();

  Future<int> waitForPostWorkSelection({required Process process}) async {
    await _poll(
      description: 'post-work target selection',
      process: process,
      predicate: () =>
          postWorkSnapshotMarker.existsSync() &&
          postWorkSnapshotMarker.readAsStringSync().startsWith('selected|'),
    );
    return int.parse(
      postWorkSnapshotMarker.readAsStringSync().trim().split('|')[1],
    );
  }

  Future<void> writeOwnedFifo(String basename, String contents) async {
    final sink = File('${activeTempOwner.path}/$basename').openWrite()
      ..write(contents);
    await sink.flush();
    await sink.close();
  }

  Future<void> deleteOwnedFifo(String basename) =>
      File('${activeTempOwner.path}/$basename').delete();

  Future<void> waitForChildFifoStat({required Process process}) async {
    await _poll(
      description: 'child FIFO stat gate',
      process: process,
      predicate: statMarker.existsSync,
    );
  }

  Future<void> waitForObservation(
    String needle, {
    required Process process,
  }) async {
    await _poll(
      description: 'observation $needle',
      process: process,
      predicate: () =>
          observation.existsSync() &&
          observation.readAsStringSync().contains(needle),
    );
  }

  Future<void> waitForPrivateTrace(
    String basename,
    String needle, {
    required Process process,
    required Duration timeout,
  }) async {
    await _poll(
      description: '$basename trace $needle',
      process: process,
      predicate: () {
        final owners = harness.tempOwners;
        if (owners.length != 1) {
          return false;
        }
        final trace = File('${owners.single.path}/$basename');
        return trace.existsSync() && trace.readAsStringSync().contains(needle);
      },
      timeout: timeout,
    );
  }

  Directory get activeTempOwner {
    final owners = harness.tempRoot.listSync().whereType<Directory>().where(
      (entry) => entry.path
          .split(Platform.pathSeparator)
          .last
          .startsWith('opentui-go-snapshot.'),
    );
    return owners.single;
  }

  Future<void> waitForLog(String needle, {required Process process}) async {
    await _poll(
      description: 'log entry $needle',
      process: process,
      predicate: () =>
          log.existsSync() && log.readAsStringSync().contains(needle),
    );
  }

  Future<void> waitForOwnedFile(
    String basename, {
    required Process process,
  }) async {
    await _poll(
      description: basename,
      process: process,
      predicate: () => harness.tempRoot
          .listSync(recursive: true)
          .whereType<File>()
          .any((file) => file.path.endsWith('/$basename')),
    );
  }

  Future<void> waitForOwnedNonEmptyFile(
    String basename, {
    required Process process,
  }) async {
    await _poll(
      description: 'nonempty $basename',
      process: process,
      predicate: () => harness.tempRoot
          .listSync(recursive: true)
          .whereType<File>()
          .any(
            (file) => file.path.endsWith('/$basename') && file.lengthSync() > 0,
          ),
    );
  }

  Future<int> commandPgid({required Process process}) async {
    await waitForLog('command-started', process: process);
    final row = const LineSplitter()
        .convert(log.readAsStringSync())
        .firstWhere((line) => line.startsWith('command-started|'));
    return int.parse(row.split('|')[2]);
  }

  Future<List<int>> directGroupLeaders(int parentPid) async {
    final result = await Process.run(realPsPath, [
      '-axo',
      'pid=,ppid=,pgid=,stat=',
    ]);
    expect(result.exitCode, 0);
    final leaders = <int>[];
    for (final line in const LineSplitter().convert(result.stdout as String)) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 4) {
        continue;
      }
      final pid = int.tryParse(fields[0]);
      final ppid = int.tryParse(fields[1]);
      final pgid = int.tryParse(fields[2]);
      if (pid != null && ppid == parentPid && pgid == pid) {
        leaders.add(pid);
      }
    }
    return leaders;
  }

  String get realPsPath => harness.realPs;

  String get realStatPath => harness.realStat;

  Future<void> waitForProcessState(
    int pid,
    String statePrefix, {
    required Process process,
  }) async {
    await _poll(
      description: 'PID $pid state $statePrefix',
      process: process,
      predicate: () async {
        final result = await Process.run(realPsPath, [
          '-o',
          'stat=',
          '-p',
          '$pid',
        ]);
        return result.exitCode == 0 &&
            (result.stdout as String).trim().startsWith(statePrefix);
      },
    );
  }

  Future<void> recordDescendants(
    int rootPid, {
    bool assertionOwned = true,
  }) async {
    final result = await Process.run(realPsPath, ['-axo', 'pid=,ppid=']);
    if (result.exitCode != 0) {
      return;
    }
    final children = <int, List<int>>{};
    for (final line in const LineSplitter().convert(result.stdout as String)) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length != 2) {
        continue;
      }
      final pid = int.tryParse(fields[0]);
      final parent = int.tryParse(fields[1]);
      if (pid != null && parent != null) {
        children.putIfAbsent(parent, () => <int>[]).add(pid);
      }
    }
    final pending = <int>[rootPid];
    while (pending.isNotEmpty) {
      final parent = pending.removeLast();
      for (final child in children[parent] ?? const <int>[]) {
        if (assertionOwned) {
          assertionPids.add(child);
        }
        if (harness._emergencyPids.add(child)) {
          pending.add(child);
        }
      }
    }
  }

  // One shared budget for every live-wrapper marker wait. Correctness is
  // owned elsewhere: the loop breaks immediately when the wrapper exits, the
  // file-level 60-second ceiling bounds the test, and _Harness emergency
  // cleanup reaps stuck processes. Per-marker budgets (3/8/12/16 seconds)
  // were host-calibration guesses that failed stochastically during full
  // serial parity partitions — the gated symbol snapshot alone was measured
  // at ~20 seconds under ordinary load (P9-050). Waits that legitimately
  // exceed this (production timeout outcomes) pass a larger explicit budget.
  static const _pollBudget = Duration(seconds: 30);

  Future<void> _poll({
    required String description,
    required Process process,
    required FutureOr<bool> Function() predicate,
    Duration timeout = _pollBudget,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await predicate()) {
        return;
      }
      if (await _futureCompleted(process.exitCode)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final ownerDiagnostics = harness.tempOwners
        .map((owner) {
          final traces = <String>[
            for (final basename in <String>[
              'supervisor.shell.stderr',
              'child.shell.stderr',
              'watchdog.shell.stderr',
            ])
              '$basename:\n${File('${owner.path}/$basename').existsSync() ? File('${owner.path}/$basename').readAsStringSync() : '<missing>'}',
          ].join('\n');
          return '${owner.path}:\n$traces';
        })
        .join('\n');
    throw TestFailure(
      'did not observe $description before wrapper exit\n'
      'fixture log:\n${log.existsSync() ? log.readAsStringSync() : '<missing>'}\n'
      'observation:\n'
      '${observation.existsSync() ? observation.readAsStringSync() : '<missing>'}\n'
      'owners:\n$ownerDiagnostics',
    );
  }
}

final class _RunResult {
  const _RunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.streamsClosed,
    required this.stdoutClosed,
    required this.stderrClosed,
    required this.stdoutDone,
    required this.log,
    required this.trace,
    required this.directPid,
    required this.recordedPids,
    required this.assertionPids,
    required this.nmEvents,
    required this.symbolRawCapture,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool streamsClosed;
  final bool stdoutClosed;
  final bool stderrClosed;
  final Future<void> stdoutDone;
  final String log;
  final String trace;
  final int directPid;
  final Set<int> recordedPids;
  final Set<int> assertionPids;
  final String nmEvents;
  final Directory symbolRawCapture;
}

void _expectStableSymbolRawCapture(_RunResult result) {
  for (final stream in <String>['stdout', 'stderr']) {
    final first = File('${result.symbolRawCapture.path}/$stream.first');
    final second = File('${result.symbolRawCapture.path}/$stream.second');
    expect(first.existsSync(), isTrue, reason: '$stream first capture missing');
    expect(
      second.existsSync(),
      isTrue,
      reason: '$stream second capture missing',
    );
    expect(second.readAsBytesSync(), first.readAsBytesSync(), reason: stream);
    final match = RegExp(
      'SYMBOL_RAW[|]$stream[|]inode=([0-9]+)[|]size=([0-9]+)[|]'
      'inode_after=([0-9]+)[|]size_after=([0-9]+)',
    ).firstMatch(result.trace);
    expect(match, isNotNull, reason: '$stream identity row missing');
    expect(match!.group(3), match.group(1), reason: '$stream inode changed');
    expect(match.group(4), match.group(2), reason: '$stream length changed');
  }
  final childWait = result.trace.indexOf('TRACE|wait_consumed|child|');
  final watchdogWait = result.trace.indexOf('TRACE|wait_consumed|watchdog|');
  final rawCapture = result.trace.indexOf('SYMBOL_RAW|stdout|');
  expect(childWait, greaterThanOrEqualTo(0));
  expect(watchdogWait, greaterThanOrEqualTo(0));
  expect(rawCapture, greaterThan(childWait));
  expect(rawCapture, greaterThan(watchdogWait));
}

void _expectQuiescenceAbortState(_RunResult result) {
  expect(
    result.trace,
    contains('P9_STATE|symbol-preflight.quiescence-held|present'),
  );
  for (final basename in <String>[
    'symbol-preflight.result',
    'symbol-preflight.quiescence-parent.candidate',
    'symbol-preflight.quiescence-child.candidate',
    'symbol-preflight.quiescence-disposition',
    'symbol-preflight.quiescence-authorized',
    'symbol-preflight.quiescence-rejected',
    'symbol-preflight.quiescence-closed',
  ]) {
    expect(result.trace, contains('P9_STATE|$basename|absent'));
  }
  expect(
    result.trace,
    isNot(contains('symbol_preflight|quiescence-snapshot|decision=')),
  );
  expect(result.trace, isNot(contains('symbol_preflight|parse-start')));
  expect(result.trace, isNot(contains('FS|child.candidate|')));
  expect(
    result.trace,
    isNot(contains('FS|symbol-preflight.quiescence-parent.candidate|')),
  );
  expect(
    result.trace,
    isNot(contains('FS|symbol-preflight.quiescence-child.candidate|')),
  );
  expect(
    result.trace,
    isNot(contains('FS|symbol-preflight.quiescence-disposition|')),
  );
  final opened = result.trace.indexOf(
    'fifo|child|symbol-preflight-quiescence-opened|fd=8',
  );
  final aborted = result.trace.indexOf(
    'hold|child|phase=symbol-preflight-quiescence|aborted|',
  );
  final closed = result.trace.indexOf(
    'fifo|child|symbol-preflight-quiescence-closed|fd=8',
  );
  expect(opened, greaterThanOrEqualTo(0));
  expect(aborted, greaterThan(opened));
  expect(closed, greaterThan(aborted));
}

void _expectAtomicDispositionSurface() {
  final source = File(_scriptPath).readAsStringSync();
  for (final token in <String>[
    'symbol-preflight.quiescence-parent.candidate',
    'symbol-preflight.quiescence-child.candidate',
    'symbol-preflight.quiescence-disposition',
    'symbol-preflight.quiescence-parent.ln.stderr',
    'symbol-preflight.quiescence-child.ln.stderr',
    'elect_symbol_preflight_quiescence_disposition() {',
    'reject:snapshot',
    'reject:unexpected-data',
    'reject:ceiling',
  ]) {
    expect(
      source.contains(token),
      isTrue,
      reason: 'missing atomic surface: $token',
    );
  }
  expect(
    source.contains(
      r'/bin/ln "$symbol_preflight_quiescence_child_candidate" '
      r'"$symbol_preflight_quiescence_disposition"',
    ),
    isTrue,
  );

  final recordReader = _shellFunction(source, 'read_exact_line');
  expect(
    recordReader,
    contains(r'if IFS= read -r extra <&4 || [[ -n "$extra" ]]; then'),
  );

  final election = _shellFunction(
    source,
    'elect_symbol_preflight_quiescence_disposition',
  );
  const candidateWrite = r'''printf '%s\n' "$value" >"$candidate"''';
  const candidateValidation =
      r'symbol_preflight_quiescence_record_is "$candidate" "$value"';
  const childLink =
      r'/bin/ln "$symbol_preflight_quiescence_child_candidate" "$symbol_preflight_quiescence_disposition" </dev/null >/dev/null 2>"$symbol_preflight_quiescence_child_ln_stderr" 3>&- 8>&- 9>&-';
  const parentLink =
      r'/bin/ln "$symbol_preflight_quiescence_parent_candidate" "$symbol_preflight_quiescence_disposition" </dev/null >/dev/null 2>"$symbol_preflight_quiescence_parent_ln_stderr" 3>&- 8>&- 9>&-';
  final writeIndex = election.indexOf(candidateWrite);
  final validationIndex = election.indexOf(candidateValidation);
  final childLinkIndex = election.indexOf(childLink);
  final parentLinkIndex = election.indexOf(parentLink);
  expect(writeIndex, greaterThanOrEqualTo(0));
  expect(validationIndex, greaterThan(writeIndex));
  expect(childLinkIndex, greaterThan(validationIndex));
  expect(parentLinkIndex, greaterThan(validationIndex));
  expect(_occurrences(election, '/bin/ln '), 2);
  expect(
    _occurrences(election, r'"$symbol_preflight_quiescence_disposition"'),
    2,
  );
  expect(election, isNot(contains('/bin/rm')));
  expect(election, isNot(contains('unlink')));
  expect(
    election,
    isNot(contains(r'>"$symbol_preflight_quiescence_disposition"')),
  );

  final validator = _shellFunction(
    source,
    'validate_symbol_preflight_quiescence_disposition',
  );
  final destinationRead = validator.indexOf(
    r'read_exact_line "$symbol_preflight_quiescence_disposition"',
  );
  final winnerRecord = validator.indexOf(
    r'symbol_preflight_quiescence_record_is "$winner" "$value"',
  );
  final winnerInode = validator.indexOf(
    r'[[ "$symbol_preflight_quiescence_disposition" -ef "$winner" ]]',
  );
  expect(destinationRead, greaterThanOrEqualTo(0));
  expect(winnerRecord, greaterThan(destinationRead));
  expect(winnerInode, greaterThan(winnerRecord));
  expect(
    validator,
    isNot(
      contains(
        r'read_exact_line "$symbol_preflight_quiescence_child_candidate"',
      ),
    ),
  );
  expect(
    validator,
    contains(
      r'private_marker_valid "$symbol_preflight_quiescence_parent_ln_stderr"',
    ),
  );
  expect(
    validator,
    contains(
      r'private_marker_valid "$symbol_preflight_quiescence_child_ln_stderr"',
    ),
  );
  const parentLoserInode =
      r'[[ ! "$symbol_preflight_quiescence_disposition" -ef \'
      '\n'
      r'      "$symbol_preflight_quiescence_parent_candidate" ]]';
  expect(validator, contains(parentLoserInode));

  final admission = _shellFunction(
    source,
    'admit_symbol_preflight_child_election_prefix',
  );
  final destinationBranch = admission.indexOf(
    r'if [[ -e "$symbol_preflight_quiescence_disposition"',
  );
  final sinkBranch = admission.indexOf(
    r'elif [[ -e "$symbol_preflight_quiescence_child_ln_stderr"',
  );
  final candidateBranch = admission.indexOf(
    r'elif [[ -e "$symbol_preflight_quiescence_child_candidate"',
  );
  expect(destinationBranch, greaterThanOrEqualTo(0));
  expect(sinkBranch, greaterThan(destinationBranch));
  expect(candidateBranch, greaterThan(sinkBranch));
  expect(admission, isNot(contains('read_exact_line')));
  expect(admission, isNot(contains(' -ef ')));
  expect(admission, isNot(contains(' -s ')));

  final precommandStart = source.indexOf('  run_child_precommands\n');
  final postWorkOpen = source.indexOf(
    r'! exec 8<>"$child_anchor_fifo"',
    precommandStart,
  );
  final precommandBlock = source.substring(precommandStart, postWorkOpen);
  final statusCapture = precommandBlock.indexOf(r'child_precommand_status=$?');
  final nonzeroBranch = precommandBlock.indexOf('  else\n', statusCapture);
  final stderrClose = precommandBlock.indexOf(
    'if ! exec 3>&-; then',
    nonzeroBranch,
  );
  final protocolMapping = precommandBlock.indexOf(
    r'[[ "$child_precommand_status" -ne 1 ]]',
    stderrClose,
  );
  expect(statusCapture, greaterThanOrEqualTo(0));
  expect(nonzeroBranch, greaterThan(statusCapture));
  expect(stderrClose, greaterThan(nonzeroBranch));
  expect(protocolMapping, greaterThan(stderrClose));

  const parentElectionCall =
      r'    elect_symbol_preflight_quiescence_disposition \'
      '\n'
      r'      parent "$symbol_parent_disposition"';
  final parentElectionIndex = source.indexOf(parentElectionCall);
  final preElectionSignalFence = source.lastIndexOf(
    r'    if [[ "$signal_pending" != "" ]]; then',
    parentElectionIndex,
  );
  final postElectionSignalFence = source.indexOf(
    r'    if [[ "$signal_pending" != "" ]]; then',
    parentElectionIndex + parentElectionCall.length,
  );
  final postElectionValidation = source.indexOf(
    '! validate_symbol_preflight_quiescence_disposition; then',
    postElectionSignalFence,
  );
  final derivedBranch = source.indexOf(
    r'    case "$SYMBOL_PREFLIGHT_QUIESCENCE_DISPOSITION" in',
    postElectionValidation,
  );
  expect(parentElectionIndex, greaterThan(preElectionSignalFence));
  expect(postElectionSignalFence, greaterThan(parentElectionIndex));
  expect(postElectionValidation, greaterThan(postElectionSignalFence));
  expect(derivedBranch, greaterThan(postElectionValidation));
  expect(
    source.indexOf(
      r': >"$symbol_preflight_quiescence_authorized"',
      derivedBranch,
    ),
    greaterThan(derivedBranch),
  );
  expect(
    source.indexOf(
      r': >"$symbol_preflight_quiescence_rejected"',
      derivedBranch,
    ),
    greaterThan(derivedBranch),
  );

  final parser = _shellFunction(
    source,
    'run_selected_artifact_symbol_preflight',
  );
  final parseStart = parser.indexOf(
    'trace_event "symbol_preflight|parse-start"',
  );
  expect(parseStart, greaterThanOrEqualTo(0));
  for (final gate in <String>[
    r'private_marker_valid "$symbol_preflight_quiescence_closed"',
    'validate_symbol_preflight_quiescence_disposition',
    r'[[ "$SYMBOL_PREFLIGHT_QUIESCENCE_DISPOSITION" != authorize ]]',
    r'private_marker_valid "$symbol_preflight_quiescence_authorized"',
    r'-e "$symbol_preflight_quiescence_rejected"',
  ]) {
    final gateIndex = parser.lastIndexOf(gate, parseStart);
    expect(gateIndex, greaterThanOrEqualTo(0), reason: 'missing gate: $gate');
    expect(gateIndex, lessThan(parseStart), reason: 'late gate: $gate');
  }
}

Set<int> _fixturePids(String log) {
  final pids = <int>{};
  for (final line in const LineSplitter().convert(log)) {
    final fields = line.split('|');
    if (fields.length >= 3 && fields[0] != 'argv') {
      final pid = int.tryParse(fields[1]);
      if (pid != null) {
        pids.add(pid);
      }
    }
    if (fields.length == 4 && fields[0] == 'descendant-recorded') {
      final pid = int.tryParse(fields[3]);
      if (pid != null) {
        pids.add(pid);
      }
    }
  }
  return pids;
}

Set<int> _nmPids(String events) {
  final pids = <int>{};
  for (final match in RegExp(
    r'(?:^|\|)pid=([1-9][0-9]*)(?:\||$)',
  ).allMatches(events)) {
    pids.add(int.parse(match.group(1)!));
  }
  return pids;
}

Set<int> _tracePids(String trace) {
  final pids = <int>{};
  for (final match in RegExp('(^|[|=])(pid|pgid)=([0-9]+)').allMatches(trace)) {
    final pid = int.tryParse(match.group(3)!);
    if (pid != null) {
      pids.add(pid);
    }
  }
  return pids;
}

Future<_WaitProbeResult> _runInterruptedWaitProbe(String bashPath) async {
  final sandbox = await Directory.systemTemp.createTemp('p9-042-wait.');
  final ready = File('${sandbox.path}/ready');
  final signalGate = File('${sandbox.path}/signal');
  final interrupted = File('${sandbox.path}/interrupted');
  final childGate = File('${sandbox.path}/child');
  Process? process;
  try {
    process = await Process.start(bashPath, <String>[
      '-c',
      r'''
set +e
trap 'printf "handled\n"' TERM
ready=$1
signal_gate=$2
interrupted_marker=$3
child_gate=$4
( while [[ ! -f "$child_gate" ]]; do /bin/sleep 0.01; done; exit 23 ) &
owned=$!
( while [[ ! -f "$signal_gate" ]]; do /bin/sleep 0.01; done
  /bin/sleep 0.02
  kill -TERM "$$"
) &
printf 'attempt\n'
: >"$ready"
wait "$owned"
interrupted=$?
printf 'interrupted=%s\n' "$interrupted"
if /bin/ps -p "$owned" >/dev/null 2>&1; then
  printf 'present_after_interrupt=true\n'
else
  printf 'present_after_interrupt=false\n'
fi
: >"$interrupted_marker"
while /bin/ps -p "$owned" >/dev/null 2>&1; do
  /bin/sleep 0.01
done
printf 'absent\n'
wait "$owned"
cached=$?
printf 'cached=%s\n' "$cached"
exit 0
''',
      'p9-042-wait-probe',
      ready.path,
      signalGate.path,
      interrupted.path,
      childGate.path,
    ]);
    final stdout = utf8.decoder.bind(process.stdout).join();
    final stderr = utf8.decoder.bind(process.stderr).join();
    await _waitForFile(ready, process);
    await signalGate.create();
    await _waitForFile(interrupted, process);
    await childGate.create();
    final exitCode = await process.exitCode.timeout(const Duration(seconds: 5));
    return _WaitProbeResult(
      exitCode: exitCode,
      stdout: await stdout,
      stderr: await stderr,
    );
  } finally {
    if (process != null && await _pidExists(process.pid)) {
      Process.killPid(process.pid, ProcessSignal.sigkill);
    }
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  }
}

Future<_TimedProbeResult> _runAnchorHoldCpuProbe(
  String source,
  String bashPath,
) async {
  final sandbox = await Directory.systemTemp.createTemp('p9-042-fifo-read.');
  final fifo = File('${sandbox.path}/anchor.fifo');
  final release = File('${sandbox.path}/release');
  final protocol = File('${sandbox.path}/protocol');
  final script = <String>[
    'set +e',
    'HOLD_RESULT=""',
    'anchor_signal_observed=false',
    _shellFunction(source, 'private_marker_valid'),
    'trace_event() { :; }',
    _shellFunction(source, 'evaluate_hold_boundary'),
    _shellFunction(source, 'hold_anchor_fifo'),
    r'''
/usr/bin/mkfifo -m 600 "$1" || exit 70
exec 8<>"$1" || exit 71
(
  /bin/sleep 3
  : >"$2"
) 3>&- 8>&- 9>&- &
release_pid=$!
hold_anchor_fifo post child 8 "$2" "" "$3"
result="$HOLD_RESULT"
exec 8>&-
wait "$release_pid" || exit 72
printf '%s\n' "$result"
[[ "$result" == released && ! -e "$3" ]]
''',
  ].join('\n');
  final stopwatch = Stopwatch()..start();
  try {
    final result = await Process.run('/usr/bin/time', <String>[
      '-p',
      bashPath,
      '-c',
      script,
      'p9-042-fifo-read',
      fifo.path,
      release.path,
      protocol.path,
    ]).timeout(const Duration(seconds: 8));
    stopwatch.stop();
    return _TimedProbeResult(
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
      wall: stopwatch.elapsed,
    );
  } finally {
    stopwatch.stop();
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  }
}

Future<void> _waitForFile(File file, Process process) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) {
      return;
    }
    if (await _futureCompleted(process.exitCode)) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw TestFailure('wait probe did not create ${file.path}');
}

final class _WaitProbeResult {
  const _WaitProbeResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

final class _TimedProbeResult {
  const _TimedProbeResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.wall,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration wall;
}

String _canonicalNativeImage(
  String candidate, {
  bool requireExecutable = true,
}) {
  Never reject(String reason) {
    throw TestFailure('invalid native fixture target $candidate: $reason');
  }

  if (!candidate.startsWith('/') ||
      candidate.contains('\n') ||
      candidate.contains('\r') ||
      candidate.contains('|')) {
    reject('unsafe path');
  }
  late final String canonical;
  try {
    canonical = File(candidate).resolveSymbolicLinksSync();
  } on FileSystemException {
    reject('cannot resolve');
  }
  if (!canonical.startsWith('/') ||
      canonical.contains('\n') ||
      canonical.contains('\r') ||
      canonical.contains('|') ||
      FileSystemEntity.typeSync(canonical, followLinks: false) !=
          FileSystemEntityType.file) {
    reject('canonical path is not one safe regular file');
  }
  final status = FileStat.statSync(canonical);
  if (requireExecutable && status.mode & 0x49 == 0) {
    reject('not executable');
  }
  final handle = File(canonical).openSync();
  late final List<int> magic;
  try {
    magic = handle.readSync(4);
  } finally {
    handle.closeSync();
  }
  final validMagic = Platform.isMacOS
      ? const <String>{
          'feedface',
          'cefaedfe',
          'feedfacf',
          'cffaedfe',
          'cafebabe',
          'bebafeca',
          'cafebabf',
          'bfbafeca',
        }.contains(
          magic.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
        )
      : magic.length == 4 &&
            magic[0] == 0x7f &&
            magic[1] == 0x45 &&
            magic[2] == 0x4c &&
            magic[3] == 0x46;
  if (!validMagic) {
    reject('script or unrecognized image magic');
  }
  return canonical;
}

Future<_P9043LoaderProbeResult> _runP9043LoaderRedProbe() async {
  final sandbox = Directory(
    (await Directory.systemTemp.createTemp(
      'p9-043-loader.',
    )).resolveSymbolicLinksSync(),
  );
  final dispatch = await Directory('${sandbox.path}/bin').create();
  final poisonTmp = await Directory('${sandbox.path}/poison-tmp').create();
  await Directory('${sandbox.path}/poison-home').create();
  final events = await File('${sandbox.path}/loader-events.raw').create();
  await Process.run('chmod', ['600', events.path]);
  final auditLibrary =
      '${sandbox.path}/loader-audit.'
      '${Platform.isMacOS ? 'dylib' : 'so'}';
  const nativeSource = 'test/fixtures/go_snapshot/loader_native_fixture.c';
  Process? process;
  final allowedImages = <String>{};

  Future<void> compile(List<String> arguments) async {
    final result = await Process.run('/usr/bin/clang', arguments);
    if (result.exitCode != 0) {
      throw TestFailure(
        'P9-043 native fixture compile failed:\n'
        '${result.stdout}\n${result.stderr}',
      );
    }
  }

  try {
    await compile(<String>[
      if (Platform.isMacOS) '-dynamiclib' else ...<String>['-shared', '-fPIC'],
      '-std=c11',
      'test/fixtures/go_snapshot/loader_audit.c',
      '-o',
      auditLibrary,
    ]);
    _canonicalNativeImage(auditLibrary, requireExecutable: false);
    for (final role in <(String, int)>[
      ('control', 1),
      ('nm', 2),
      ('go', 3),
      ('pkg-config', 4),
    ]) {
      await compile(<String>[
        '-std=c11',
        '-DFIXTURE_ROLE=${role.$2}',
        nativeSource,
        '-o',
        '${dispatch.path}/${role.$1}',
      ]);
      expect(
        _canonicalNativeImage('${dispatch.path}/${role.$1}'),
        '${dispatch.path}/${role.$1}',
      );
    }
    for (final tool in <String>[
      'uname',
      'tr',
      'mktemp',
      'mkdir',
      'rm',
      'ps',
      'stat',
      'mkfifo',
    ]) {
      final target = _canonicalNativeImage(await _executablePath(tool));
      await Link('${dispatch.path}/$tool').create(target);
      expect(Link('${dispatch.path}/$tool').targetSync(), target);
      expect(
        FileSystemEntity.typeSync(target, followLinks: false),
        FileSystemEntityType.file,
      );
      allowedImages.add(target);
    }
    final nativeLn = _canonicalNativeImage('/bin/ln');
    final nativeSleep = _canonicalNativeImage('/bin/sleep');
    allowedImages
      ..add(nativeLn)
      ..add(nativeSleep);

    for (final path in <String>[
      File('test/fixtures/go_snapshot/clean_bash_bootstrap.sh').absolute.path,
      File(_scriptPath).absolute.path,
      sandbox.path,
      dispatch.path,
      auditLibrary,
      '${dispatch.path}/control',
    ]) {
      expect(path.startsWith('/'), isTrue);
      expect(path, isNot(anyOf(contains('\n'), contains('\r'), contains('|'))));
    }

    process = await Process.start(
      '/bin/bash',
      <String>[
        File('test/fixtures/go_snapshot/clean_bash_bootstrap.sh').absolute.path,
        File(_scriptPath).absolute.path,
        sandbox.path,
        dispatch.path,
        auditLibrary,
        '${dispatch.path}/control',
      ],
      environment: <String, String>{'PATH': dispatch.path, 'LC_ALL': 'C'},
      includeParentEnvironment: false,
      workingDirectory: Directory.current.path,
    );
    final stdoutFuture = utf8.decoder.bind(process.stdout).join();
    final stderrFuture = utf8.decoder.bind(process.stderr).join();
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        Process.killPid(process!.pid, ProcessSignal.sigkill);
        throw TimeoutException('P9-043 loader RED probe exceeded 20 seconds');
      },
    );
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    int pidFrom(String basename) {
      final file = File('${sandbox.path}/$basename');
      return file.existsSync()
          ? int.tryParse(file.readAsStringSync().trim()) ?? -1
          : -1;
    }

    final bootstrapPid = pidFrom('bootstrap.pid');
    final controlPid = pidFrom('loader-control.pid');
    final nmPid = pidFrom('nm.pid');
    expect(bootstrapPid, greaterThan(0));
    expect(controlPid, greaterThan(0));
    expect(nmPid, greaterThan(0));
    final firstEvents = await events.readAsString();
    final firstEventLength = events.lengthSync();
    final statTool = await _executablePath('stat');
    Future<String> eventInode() async {
      final result = await Process.run(
        statTool,
        Platform.isMacOS
            ? <String>['-f', '%i', events.path]
            : <String>['-c', '%i', events.path],
      );
      expect(result.exitCode, 0);
      return (result.stdout as String).trim();
    }

    final firstEventInode = await eventInode();
    expect(firstEvents, isNotEmpty);
    expect(
      firstEvents.endsWith('\n'),
      isTrue,
      reason: 'unterminated loader row',
    );
    final eventRows = const LineSplitter().convert(firstEvents);
    final eventPattern = RegExp(r'^load\|pid=([1-9][0-9]*)\|exe=(/[^|\r\n]+)$');
    final controlImage = File(
      '${dispatch.path}/control',
    ).resolveSymbolicLinksSync();
    final forbiddenImages = <String>{
      File('${dispatch.path}/nm').resolveSymbolicLinksSync(),
      File('${dispatch.path}/go').resolveSymbolicLinksSync(),
      File('${dispatch.path}/pkg-config').resolveSymbolicLinksSync(),
    };
    final eventPids = <int>{};
    for (var index = 0; index < eventRows.length; index += 1) {
      final match = eventPattern.firstMatch(eventRows[index]);
      expect(
        match,
        isNotNull,
        reason: 'malformed loader row ${eventRows[index]}',
      );
      final pid = int.parse(match!.group(1)!);
      final image = match.group(2)!;
      eventPids.add(pid);
      expect(pid, isNot(bootstrapPid), reason: 'bootstrap was loader-poisoned');
      expect(
        pid,
        isNot(nmPid),
        reason: 'empty-environment nm loaded audit DSO',
      );
      expect(forbiddenImages, isNot(contains(image)), reason: eventRows[index]);
      if (index == 0) {
        expect(pid, controlPid);
        expect(image, controlImage);
      } else {
        expect(pid, isNot(controlPid), reason: 'duplicate control event');
        expect(allowedImages, contains(image), reason: eventRows[index]);
      }
    }
    expect(
      eventRows.where((row) => row.contains('pid=$controlPid|')),
      hasLength(1),
    );
    for (final pid in <int>{bootstrapPid, nmPid, ...eventPids}) {
      expect(
        await _pidExists(pid),
        isFalse,
        reason: 'loader PID $pid survived',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final secondEvents = await events.readAsString();
    expect(secondEvents, firstEvents, reason: 'loader event suffix changed');
    expect(
      events.lengthSync(),
      firstEventLength,
      reason: 'loader length changed',
    );
    expect(await eventInode(), firstEventInode, reason: 'loader inode changed');

    final nmArgv = File('${sandbox.path}/nm.argv.raw').readAsStringSync();
    final machineResult = await Process.run(await _executablePath('uname'), [
      '-m',
    ]);
    expect(machineResult.exitCode, 0);
    final machine = (machineResult.stdout as String).trim();
    final libraryArch = switch (machine) {
      'arm64' || 'aarch64' => 'arm64',
      'x86_64' || 'amd64' => 'x64',
      _ => throw TestFailure('unsupported loader-probe architecture $machine'),
    };
    final libraryPath = File(
      'native/${Platform.isMacOS ? 'macos' : 'linux'}/'
      '$libraryArch/'
      'libopentui.${Platform.isMacOS ? 'dylib' : 'so'}',
    ).absolute.path;
    expect(
      nmArgv,
      Platform.isMacOS
          ? '0|${dispatch.path}/nm\n1|-gU\n2|$libraryPath\n'
          : '0|${dispatch.path}/nm\n1|-D\n2|--defined-only\n3|$libraryPath\n',
    );
    expect(
      poisonTmp.listSync(),
      isEmpty,
      reason: 'wrapper temp owner remained',
    );

    final controlStdout = File('${sandbox.path}/loader-control.stdout.raw');
    final controlStderr = File('${sandbox.path}/loader-control.stderr.raw');
    expect(controlStdout.readAsStringSync(), isEmpty);
    expect(controlStderr.readAsStringSync(), isEmpty);
    return _P9043LoaderProbeResult(
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      selectedPath: libraryPath,
      events: firstEvents,
      bootstrapPid: bootstrapPid,
      controlPid: controlPid,
      nmPid: nmPid,
      nmPoison: File('${sandbox.path}/nm.poison.raw').existsSync()
          ? File('${sandbox.path}/nm.poison.raw').readAsStringSync()
          : '',
      goLaunched: File('${sandbox.path}/go.launched').existsSync(),
      pkgConfigLaunched: File(
        '${sandbox.path}/pkg-config.launched',
      ).existsSync(),
    );
  } finally {
    if (process != null && await _pidExists(process.pid)) {
      Process.killPid(process.pid, ProcessSignal.sigkill);
    }
    if (poisonTmp.existsSync()) {
      for (final entry in poisonTmp.listSync()) {
        if (entry is Directory &&
            entry.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('opentui-go-snapshot.')) {
          await entry.delete(recursive: true);
        }
      }
    }
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  }
}

final class _P9043LoaderProbeResult {
  const _P9043LoaderProbeResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.selectedPath,
    required this.events,
    required this.bootstrapPid,
    required this.controlPid,
    required this.nmPid,
    required this.nmPoison,
    required this.goLaunched,
    required this.pkgConfigLaunched,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final String selectedPath;
  final String events;
  final int bootstrapPid;
  final int controlPid;
  final int nmPid;
  final String nmPoison;
  final bool goLaunched;
  final bool pkgConfigLaunched;
}

Future<bool> _pidExists(int pid) async {
  final result = await Process.run(await _executablePath('ps'), ['-p', '$pid']);
  return result.exitCode == 0;
}

int _traceCount(String trace, String needle) => _occurrences(trace, needle);

void _expectSetupIdentityMatchesMkfifoRows(
  _RunObservation run,
  (int, int) identity,
) {
  final owner = run.activeTempOwner;
  final rows = const LineSplitter()
      .convert(run.log.readAsStringSync())
      .where((line) => line.startsWith('mkfifo-invoked|'))
      .map((line) => line.split('|'))
      .toList();
  expect(rows, hasLength(2));
  expect(rows[0], hasLength(5));
  expect(rows[1], hasLength(5));
  expect(rows[0][3], 'watchdog');
  expect(rows[0][4], '${owner.path}/watchdog.anchor-control.fifo');
  expect(rows[1][3], 'child');
  expect(rows[1][4], '${owner.path}/child.anchor-control.fifo');
  final watchdogPgid = int.parse(rows[0][2]);
  final childPgid = int.parse(rows[1][2]);
  expect(watchdogPgid, greaterThan(0));
  expect(childPgid, watchdogPgid);
  expect(identity, (childPgid, childPgid));
}

void _expectContiguousUnexpectedData(String trace, String label) {
  final matcher = RegExp(
    '\\|anchor_tick\\|$label\\|phase=post\\|slot=([0-9]+)'
    r'\|result=(tick|unexpected-data)\|',
  );
  final rows = matcher.allMatches(trace).toList();
  expect(rows, isNotEmpty, reason: trace);
  final unexpected = rows
      .where((row) => row.group(2) == 'unexpected-data')
      .toList();
  expect(unexpected, hasLength(1), reason: trace);
  expect(rows.last, same(unexpected.single), reason: trace);
  final terminalSlot = int.parse(unexpected.single.group(1)!);
  expect(terminalSlot, inInclusiveRange(1, 30));
  expect(rows, hasLength(terminalSlot));
  for (var index = 0; index < rows.length; index += 1) {
    expect(int.parse(rows[index].group(1)!), index + 1, reason: trace);
    expect(
      rows[index].group(2),
      index + 1 == terminalSlot ? 'unexpected-data' : 'tick',
      reason: trace,
    );
  }

  final unexpectedIndex = trace.indexOf(unexpected.single.group(0)!);
  final closeIndex = trace.indexOf(
    '|fifo|$label|post-closed|',
    unexpectedIndex,
  );
  final helperIndex = trace.indexOf(
    '|failure_hold|$label|phase=post|reason=unexpected-data|start',
    closeIndex,
  );
  expect(unexpectedIndex, greaterThanOrEqualTo(0));
  expect(closeIndex, greaterThan(unexpectedIndex), reason: trace);
  expect(helperIndex, greaterThan(closeIndex), reason: trace);
}

int _occurrences(String value, String needle) {
  if (needle.isEmpty) {
    return 0;
  }
  var count = 0;
  var offset = 0;
  while (true) {
    final next = value.indexOf(needle, offset);
    if (next < 0) {
      return count;
    }
    count += 1;
    offset = next + needle.length;
  }
}

double _cpuUsageSeconds(String stderr) {
  final user = RegExp(
    r'^user\s+([0-9]+(?:\.[0-9]+)?)$',
    multiLine: true,
  ).firstMatch(stderr);
  final system = RegExp(
    r'^sys\s+([0-9]+(?:\.[0-9]+)?)$',
    multiLine: true,
  ).firstMatch(stderr);
  if (user == null || system == null) {
    throw TestFailure('missing portable time output:\n$stderr');
  }
  return double.parse(user.group(1)!) + double.parse(system.group(1)!);
}

Map<String, String> _fsRecord(String trace, String entry) {
  final prefix = 'FS|$entry|';
  for (final line in const LineSplitter().convert(trace)) {
    if (!line.startsWith(prefix)) {
      continue;
    }
    return <String, String>{
      for (final field in line.substring(prefix.length).split('|'))
        if (field.contains('='))
          field.substring(0, field.indexOf('=')): field.substring(
            field.indexOf('=') + 1,
          ),
    };
  }
  return const <String, String>{};
}

int _linkStderrSize(String trace, String entry) {
  final prefix = 'LINK_STDERR|$entry|size=';
  final line = const LineSplitter()
      .convert(trace)
      .where((line) => line.startsWith(prefix))
      .single;
  return int.parse(line.substring(prefix.length));
}

List<String> _signalsAfterAction(String trace, String label) {
  final lines = const LineSplitter().convert(trace);
  final actionIndex = lines.indexWhere(
    (line) => line.contains('|action|$label|'),
  );
  if (actionIndex < 0) {
    return const <String>[];
  }
  return lines
      .skip(actionIndex + 1)
      .where((line) => line.contains('|signal|$label|'))
      .toList();
}

String _shellFunction(String source, String name) {
  final start = source.indexOf('$name() {');
  if (start < 0) {
    throw TestFailure('missing shell function $name');
  }
  final end = source.indexOf('\n}\n', start);
  if (end < 0) {
    throw TestFailure('unterminated shell function $name');
  }
  return source.substring(start, end + 2);
}

Future<bool> _futureCompleted(Future<Object?> future) async {
  var completed = false;
  await Future.any<Object?>([
    future.then<Object?>((_) {
      completed = true;
      return null;
    }),
    Future<Object?>.delayed(const Duration(milliseconds: 1)),
  ]);
  return completed;
}

Future<bool> _hasExecutable(String executable) async {
  final result = await Process.run('sh', ['-c', 'command -v "$executable"']);
  return result.exitCode == 0;
}

Future<String> _executablePath(String executable) async {
  final result = await Process.run('sh', ['-c', 'command -v "$executable"']);
  if (result.exitCode != 0) {
    throw StateError('missing required executable: $executable');
  }
  return (result.stdout as String).trim();
}
