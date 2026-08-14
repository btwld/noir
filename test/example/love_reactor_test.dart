import 'dart:io' as io;

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/love_reactor.dart';
import '../helpers/buffer_capture.dart';
import '../helpers/tui_test_app.dart';

final _reactorSurface = Color.fromHex('#070812');
final _reactorHeader = Color.fromHex('#45163F');
final _particlePalette = <Color>[
  Color.fromHex('#FF4D9E'),
  Color.fromHex('#FF718F'),
  Color.fromHex('#F542E8'),
  Color.fromHex('#A855F7'),
  Color.fromHex('#FFD166'),
  Color.fromHex('#66E3FF'),
];

void main() {
  test('simulation emits deterministic particles that rise and expire', () {
    final first = LoveReactorSimulation();
    final second = LoveReactorSimulation();
    final startRows = first.particles
        .map((particle) => particle.cellY(12))
        .toList();

    expect(first.burstCount, 1);
    expect(first.particles, hasLength(9));
    expect(first.corePulse, 0);
    expect(
      first.particles.map((particle) => particle.cellX(56)),
      orderedEquals(second.particles.map((particle) => particle.cellX(56))),
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

  test('initial frame renders the reactor hierarchy and solid core', () async {
    final app = createTuiTestApp(const LoveReactorApp(), width: 72);

    try {
      await _settle(app);
      final frame = app.captureFrame();
      final title = frame.findText('NOIR · LOVE REACTOR').single;

      expect(frame, BufferMatchers.containsText('BURSTS 001 · ACTIVE 09'));
      expect(frame, BufferMatchers.containsText('Space/Enter/click burst'));
      expect(frame.getForegroundColor(title.x, title.y), Color.white);
      expect(frame.getBackgroundColor(title.x, title.y), _reactorHeader);
      expect(frame.getCell(title.x, title.y).isBold, isTrue);
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < frame.width; x++) {
          expect(
            frame.getBackgroundColor(x, y),
            _reactorHeader,
            reason: 'header cell ($x, $y) must use one flat plum surface',
          );
        }
      }
      expect(frame.getBackgroundColor(0, 3), _reactorSurface);

      final core = _bottomHeart(frame);
      _expectSolidCore(frame, core, width: 9);
    } finally {
      app.dispose();
    }
  });

  test('frame pumping moves and morphs the introductory burst', () async {
    final app = createTuiTestApp(const LoveReactorApp(), width: 72);

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
      expect(morphed, BufferMatchers.containsText('BURSTS 001'));
    } finally {
      app.dispose();
    }
  });

  test('equal-age collisions paint the newest burst particle', () async {
    final simulation = LoveReactorSimulation()..burst();
    final particlesByCell = <(int, int), List<LoveParticle>>{};
    for (final particle in simulation.particles) {
      final cell = (particle.cellX(56), particle.cellY(12));
      particlesByCell.putIfAbsent(cell, () => <LoveParticle>[]).add(particle);
    }
    final collision = particlesByCell.entries.firstWhere(
      (entry) =>
          entry.value.length > 1 &&
          entry.value.first.colorIndex != entry.value.last.colorIndex,
    );
    final newest = collision.value.last;

    final app = createTuiTestApp(const LoveReactorApp(), width: 72);
    try {
      await _settle(app);
      app.mockInput.typeText(' ');
      await _settle(app);
      final frame = app.captureFrame();
      final core = _bottomHeart(frame);
      final stageLeft = (frame.width - 56) ~/ 2;
      final stageTop = core.y - 14;
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
      final app = createTuiTestApp(const LoveReactorApp(), width: 72);

      try {
        await _settle(app);
        _expectBurstCount(app, 1);

        app.mockInput
          ..typeText('x')
          ..pressKittyKey(32, eventType: 3);
        await _settle(app);
        _expectBurstCount(app, 1);

        app.mockInput.typeText(' ');
        await _settle(app);
        _expectBurstCount(app, 2);

        app.mockInput.pressEnter();
        await _settle(app);
        _expectBurstCount(app, 3);
      } finally {
        app.dispose();
      }
    },
  );

  test('only left-button down on the full core surface bursts', () async {
    final app = createTuiTestApp(const LoveReactorApp(), width: 72);

    try {
      await _settle(app);
      final core = _bottomHeart(app.captureFrame());
      final surfaceLeft = core.x - 4;
      final surfaceTop = core.y - 1;

      app.mockMouse.pressDown(surfaceLeft, surfaceTop);
      await _settle(app);
      _expectBurstCount(app, 2);

      app.mockMouse.release(surfaceLeft, surfaceTop);
      app.mockMouse
        ..click(core.x, core.y, button: MouseButton.right)
        ..click(core.x, core.y, button: MouseButton.middle)
        ..click(0, 0);
      await _settle(app);
      _expectBurstCount(app, 2);
    } finally {
      app.dispose();
    }
  });

  test('entrypoint and narrow layout preserve supported interaction', () async {
    final source = io.File('example/love_reactor.dart').readAsStringSync();

    expect(RegExp(r'app\.enableMouse\(\);').allMatches(source), hasLength(1));
    expect(source, isNot(contains('enableMouse(enableMovement: true)')));
    expect(source, contains('registerHotReloadExtension(app);'));

    final app = createTuiTestApp(const LoveReactorApp(), width: 40, height: 22);
    try {
      await _settle(app);
      final frame = app.captureFrame();
      expect(frame, BufferMatchers.containsText('NOIR · LOVE REACTOR'));
      expect(frame, BufferMatchers.containsText('Space/Enter/click burst'));
      _expectSolidCore(frame, _bottomHeart(frame), width: 9);
    } finally {
      app.dispose();
    }
  });
}

BufferPosition _bottomHeart(CapturedBuffer frame) => frame
    .findText('♥')
    .reduce((upper, lower) => lower.y > upper.y ? lower : upper);

void _expectSolidCore(
  CapturedBuffer frame,
  BufferPosition heart, {
  required int width,
}) {
  final left = heart.x - width ~/ 2;
  final top = heart.y - 1;
  final background = frame.getBackgroundColor(heart.x, heart.y);

  expect(background, isNot(_reactorSurface));
  for (var y = top; y < top + 3; y++) {
    for (var x = left; x < left + width; x++) {
      expect(
        frame.getBackgroundColor(x, y),
        background,
        reason: 'core cell ($x, $y) must be part of the solid surface',
      );
    }
  }

  final region = frame.getRegion(left, top, width, 3);
  for (final borderGlyph in ['╭', '╮', '╰', '╯', '─', '│']) {
    expect(region, isNot(contains(borderGlyph)));
  }
}

void _expectBurstCount(TuiTestApp app, int expected) {
  final frame = app.captureFrame();
  expect(
    frame,
    BufferMatchers.containsText(
      'BURSTS ${expected.toString().padLeft(3, '0')}',
    ),
  );
}

Future<void> _settle(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
