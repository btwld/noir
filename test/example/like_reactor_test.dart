import 'dart:io' as io;
import 'dart:math' as math;

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/like_reactor.dart';
import '../helpers/buffer_capture.dart';
import '../helpers/tui_test_app.dart';

final _reactorSurface = Color.fromHex('#070812');
final _reactorMuted = Color.fromHex('#B7A4C1');
final _particlePalette = <Color>[
  Color.fromHex('#FF4D9E'),
  Color.fromHex('#FF718F'),
  Color.fromHex('#F542E8'),
  Color.fromHex('#A855F7'),
  Color.fromHex('#FFD166'),
  Color.fromHex('#66E3FF'),
];

const _heartFootprintWidth = 17;
const _heartFootprintHeight = 8;
const _particleStageHeight = 8;

typedef _CellBounds = ({int left, int top, int right, int bottom});

void main() {
  test('simulation emits deterministic particles that rise and expire', () {
    final first = LikeReactorSimulation();
    final second = LikeReactorSimulation();
    final startRows = first.particles
        .map((particle) => particle.cellY(12))
        .toList();
    final startColumns = first.particles
        .map((particle) => particle.cellX(56))
        .toList();

    expect(first.burstCount, 1);
    expect(first.particles, hasLength(9));
    expect(first.corePulse, 0);
    expect(
      startColumns,
      orderedEquals(second.particles.map((particle) => particle.cellX(56))),
    );
    expect(
      startColumns.reduce(math.max) - startColumns.reduce(math.min) + 1,
      greaterThanOrEqualTo(15),
      reason: 'a burst must begin across the heart shoulders, not one slot',
    );

    first.advance(0.6);
    second.advance(0.6);
    final movedRows = first.particles
        .map((particle) => particle.cellY(12))
        .toList();
    expect(movedRows, isNot(equals(startRows)));
    expect(
      first.particles.map((particle) => particle.cellX(56)),
      orderedEquals(second.particles.map((particle) => particle.cellX(56))),
    );
    expect(first.particles.map((particle) => particle.glyph), contains('♥'));
    second.clear();
    expect(second.particles, isEmpty);

    for (var index = 0; index < 8; index++) {
      first.burst();
    }
    expect(first.burstCount, 9);
    expect(first.particles, hasLength(72));
    expect(first.corePulse, 1);
    first.advance(0.35);
    expect(first.corePulse, 0);
    expect(() => first.advance(-0.1), throwsArgumentError);
    expect(() => first.advance(double.nan), throwsArgumentError);

    first.advance(4);
    expect(first.particles, isEmpty);
  });

  test(
    'initial frame leaves spacious chrome around an open pixel heart',
    () async {
      final simulation = LikeReactorSimulation();
      final app = createTuiTestApp(
        LikeReactorApp(simulation: simulation),
        width: 72,
      );

      try {
        await _settle(app);
        final frame = app.captureFrame();
        final title = frame.findText('NOIR · LIKE REACTOR').single;
        final help = frame.findText('Space/Enter/click burst').single;
        final heart = _heartBounds(frame);
        final footprintLeft = heart.left - 2;
        final footprintTop = heart.top - 1;
        final stageTop = footprintTop - _particleStageHeight - 1;
        final particleBottom = frame
            .findText('♥')
            .map((position) => position.y)
            .reduce(math.max);

        expect(frame, BufferMatchers.containsText('Space/Enter/click burst'));
        expect(frame, isNot(BufferMatchers.containsText('BURSTS')));
        expect(frame, isNot(BufferMatchers.containsText('ACTIVE')));
        expect(frame.getForegroundColor(title.x, title.y), _reactorMuted);
        expect(frame.getBackgroundColor(title.x, title.y), _reactorSurface);
        expect(frame.getCell(title.x, title.y).isBold, isTrue);
        for (var y = 0; y < 2; y++) {
          for (var x = 0; x < frame.width; x++) {
            expect(
              frame.getBackgroundColor(x, y),
              _reactorSurface,
              reason: 'title slot cell ($x, $y) must stay on the open surface',
            );
          }
        }

        expect(_boundsWidth(heart), 13);
        expect(_boundsHeight(heart), 6);
        expect(stageTop - title.y, greaterThanOrEqualTo(2));
        expect(footprintTop - particleBottom, 2);
        expect(
          help.y - (footprintTop + _heartFootprintHeight - 1),
          greaterThanOrEqualTo(3),
        );
        _expectOpenHeartFootprint(
          frame,
          left: footprintLeft,
          top: footprintTop,
        );
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'a keyboard burst grows both heart axes without moving its center',
    () async {
      final simulation = LikeReactorSimulation();
      final app = createTuiTestApp(
        LikeReactorApp(simulation: simulation),
        width: 72,
      );

      try {
        await _settle(app);
        final compact = _heartBounds(app.captureFrame());

        app.mockInput.typeText(' ');
        app.pumpFrame();
        final full = _heartBounds(app.captureFrame());

        expect(simulation.burstCount, 2);
        expect(_boundsWidth(full), 17);
        expect(_boundsHeight(full), 8);
        expect(full.left + full.right, compact.left + compact.right);
        expect(full.top + full.bottom, compact.top + compact.bottom);

        app.pumpFrame(const Duration(milliseconds: 150));
        final medium = _heartBounds(app.captureFrame());
        expect(_boundsWidth(medium), 15);
        expect(_boundsHeight(medium), 7);

        app.pumpFrame(const Duration(milliseconds: 350));
        final settled = _heartBounds(app.captureFrame());
        expect(_boundsWidth(settled), 13);
        expect(_boundsHeight(settled), 6);
        expect(settled.left + settled.right, compact.left + compact.right);
        expect(settled.top + settled.bottom, compact.top + compact.bottom);
      } finally {
        app.dispose();
      }
    },
  );

  test('frame pumping moves and morphs the introductory burst', () async {
    final app = createTuiTestApp(const LikeReactorApp(), width: 72);

    try {
      await _settle(app);
      final initial = app.captureFrame();
      app.pumpFrame(const Duration(milliseconds: 600));
      final moved = app.captureFrame();
      app
        ..pumpFrame(const Duration(milliseconds: 1000))
        ..pumpFrame(const Duration(milliseconds: 1500))
        ..pumpFrame(const Duration(milliseconds: 2100));
      final morphed = app.captureFrame();

      expect(moved.toText(), isNot(initial.toText()));
      expect(morphed.findText('♡'), isNotEmpty);
      expect(morphed, BufferMatchers.containsText('NOIR · LIKE REACTOR'));
    } finally {
      app.dispose();
    }
  });

  test('timeline stops when idle and restarts for a new like', () async {
    final simulation = LikeReactorSimulation();
    final app = createTuiTestApp(
      LikeReactorApp(simulation: simulation),
      width: 72,
    );

    try {
      await _settle(app);
      expect(app.binding.debugHasScheduledFrame, isTrue);

      for (var seconds = 1; seconds <= 5; seconds++) {
        app.pumpFrame(Duration(seconds: seconds));
      }
      app.pumpFrame(const Duration(seconds: 6));

      expect(simulation.particles, isEmpty);
      expect(simulation.corePulse, 0);
      expect(app.binding.debugHasScheduledFrame, isFalse);

      app.mockInput.typeText(' ');
      await _settle(app);

      expect(simulation.burstCount, 2);
      expect(simulation.particles, hasLength(9));
      expect(app.binding.debugHasScheduledFrame, isTrue);
    } finally {
      app.dispose();
    }
  });

  test('equal-age collisions paint the newest burst particle', () async {
    final simulation = LikeReactorSimulation()..burst();
    final particlesByCell = <(int, int), List<LikeParticle>>{};
    for (final particle in simulation.particles) {
      final cell = (particle.cellX(56), particle.cellY(_particleStageHeight));
      particlesByCell.putIfAbsent(cell, () => <LikeParticle>[]).add(particle);
    }
    final collision = particlesByCell.entries.firstWhere(
      (entry) =>
          entry.value.length > 1 &&
          entry.value.first.colorIndex != entry.value.last.colorIndex,
    );
    final newest = collision.value.last;

    final app = createTuiTestApp(
      LikeReactorApp(simulation: simulation),
      width: 72,
    );
    try {
      await _settle(app);
      final frame = app.captureFrame();
      final heart = _heartBounds(frame);
      final stageLeft = (frame.width - 56) ~/ 2;
      final stageTop = heart.top - _particleStageHeight - 1;
      final (particleX, particleY) = collision.key;

      expect(
        frame.getChar(stageLeft + particleX, stageTop + particleY),
        newest.glyph,
      );
      expect(
        frame.getForegroundColor(stageLeft + particleX, stageTop + particleY),
        _particlePalette[newest.colorIndex],
      );
    } finally {
      app.dispose();
    }
  });

  test(
    'Space and Enter burst while unrelated input and releases do not',
    () async {
      final simulation = LikeReactorSimulation();
      final app = createTuiTestApp(
        LikeReactorApp(simulation: simulation),
        width: 72,
      );

      try {
        await _settle(app);
        expect(simulation.burstCount, 1);

        app.mockInput
          ..typeText('x')
          ..pressKittyKey(32, eventType: 3);
        await _settle(app);
        expect(simulation.burstCount, 1);

        app.mockInput.typeText(' ');
        await _settle(app);
        expect(simulation.burstCount, 2);

        app.mockInput.pressEnter();
        await _settle(app);
        expect(simulation.burstCount, 3);
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'widget updates retarget input without taking external simulation ownership',
    () async {
      final first = LikeReactorSimulation();
      final second = LikeReactorSimulation();
      final hostKey = GlobalKey<_SimulationSwapHostState>();
      final app = createTuiTestApp(
        _SimulationSwapHost(key: hostKey, initialSimulation: first),
        width: 72,
      );
      addTearDown(app.dispose);

      await _settle(app);
      app.mockInput.typeText(' ');
      await _settle(app);
      expect(first.burstCount, 2);
      expect(second.burstCount, 1);

      hostKey.currentState!.replaceSimulation(second);
      await _settle(app);
      app.mockInput.pressEnter();
      await _settle(app);
      expect(first.burstCount, 2);
      expect(second.burstCount, 2);

      final firstParticles = first.particles.length;
      final secondParticles = second.particles.length;
      app.dispose();

      expect(first.particles, hasLength(firstParticles));
      expect(second.particles, hasLength(secondParticles));
      expect(first.particles, isNotEmpty);
      expect(second.particles, isNotEmpty);
    },
  );

  test(
    'only left-button down on the invisible heart footprint bursts',
    () async {
      final simulation = LikeReactorSimulation();
      final app = createTuiTestApp(
        LikeReactorApp(simulation: simulation),
        width: 72,
      );

      try {
        await _settle(app);
        final heart = _heartBounds(app.captureFrame());
        final footprintLeft = heart.left - 2;
        final footprintTop = heart.top - 1;
        final centerX = (heart.left + heart.right) ~/ 2;
        final centerY = (heart.top + heart.bottom) ~/ 2;

        app.mockMouse.pressDown(footprintLeft, footprintTop);
        await _settle(app);
        expect(simulation.burstCount, 2);

        app.mockMouse.release(footprintLeft, footprintTop);
        app.mockMouse
          ..click(centerX, centerY, button: MouseButton.right)
          ..click(centerX, centerY, button: MouseButton.middle)
          ..click(0, 0);
        await _settle(app);
        expect(simulation.burstCount, 2);
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'entrypoint registers hot reload and narrow layout remains usable',
    () async {
      final source = io.File('example/like_reactor.dart').readAsStringSync();

      // runTuiApp registers the hot-reload extension itself.
      expect(source, isNot(contains('registerHotReloadExtension')));

      final app = createTuiTestApp(
        const LikeReactorApp(),
        width: 40,
        height: 22,
      );
      try {
        await _settle(app);
        final frame = app.captureFrame();
        expect(frame, BufferMatchers.containsText('NOIR · LIKE REACTOR'));
        expect(frame, BufferMatchers.containsText('Space/Enter/click burst'));
        final heart = _heartBounds(frame);
        expect(_boundsWidth(heart), 13);
        expect(_boundsHeight(heart), 6);
        _expectOpenHeartFootprint(
          frame,
          left: heart.left - 2,
          top: heart.top - 1,
        );
      } finally {
        app.dispose();
      }
    },
  );
}

_CellBounds _heartBounds(CapturedBuffer frame) {
  final cells = <BufferPosition>[];
  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      if (frame.getChar(x, y) == '█') {
        cells.add(BufferPosition(x, y));
      }
    }
  }
  expect(cells, isNotEmpty);
  return (
    left: cells.map((cell) => cell.x).reduce(math.min),
    top: cells.map((cell) => cell.y).reduce(math.min),
    right: cells.map((cell) => cell.x).reduce(math.max),
    bottom: cells.map((cell) => cell.y).reduce(math.max),
  );
}

int _boundsWidth(_CellBounds bounds) => bounds.right - bounds.left + 1;

int _boundsHeight(_CellBounds bounds) => bounds.bottom - bounds.top + 1;

void _expectOpenHeartFootprint(
  CapturedBuffer frame, {
  required int left,
  required int top,
}) {
  for (var y = top; y < top + _heartFootprintHeight; y++) {
    for (var x = left; x < left + _heartFootprintWidth; x++) {
      expect(
        frame.getBackgroundColor(x, y),
        _reactorSurface,
        reason: 'heart footprint cell ($x, $y) must stay transparent',
      );
    }
  }

  final region = frame.getRegion(
    left,
    top,
    _heartFootprintWidth,
    _heartFootprintHeight,
  );
  for (final borderGlyph in ['╭', '╮', '╰', '╯', '─', '│']) {
    expect(region, isNot(contains(borderGlyph)));
  }
}

class _SimulationSwapHost extends StatefulWidget {
  const _SimulationSwapHost({required this.initialSimulation, super.key});

  final LikeReactorSimulation initialSimulation;

  @override
  State<_SimulationSwapHost> createState() => _SimulationSwapHostState();
}

class _SimulationSwapHostState extends State<_SimulationSwapHost> {
  late LikeReactorSimulation _simulation;

  @override
  void initState() {
    super.initState();
    _simulation = widget.initialSimulation;
  }

  void replaceSimulation(LikeReactorSimulation simulation) {
    setState(() => _simulation = simulation);
  }

  @override
  Widget build(BuildContext context) => LikeReactorApp(simulation: _simulation);
}

Future<void> _settle(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
