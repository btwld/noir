import 'dart:collection';
import 'dart:math' as math;

import 'package:noir/noir.dart';

final _reactorSurface = Color.fromHex('#070812');
final _reactorCore = Color.fromHex('#F72585');
final _reactorCorePulse = Color.fromHex('#FF70B7');
final _reactorMuted = Color.fromHex('#B7A4C1');
final _reactorPalette = <Color>[
  Color.fromHex('#FF4D9E'),
  Color.fromHex('#FF718F'),
  Color.fromHex('#F542E8'),
  Color.fromHex('#A855F7'),
  Color.fromHex('#FFD166'),
  Color.fromHex('#66E3FF'),
];

const _stageWidth = 56;
const _stageHeight = 8;
const _heartFootprintWidth = 17;
const _heartFootprintHeight = 8;
const _particlesPerBurst = 9;
const _maximumParticles = 72;
const _pulseSeconds = 0.35;

const _compactHeart = <String>[
  '███   ███',
  '█████ █████',
  '█████████████',
  '███████████',
  '███████',
  '█',
];
const _mediumHeart = <String>[
  '█████   █████',
  '██████ ██████',
  '███████████████',
  '███████████████',
  '█████████████',
  '███████',
  '█',
];
const _fullHeart = <String>[
  '█████   █████',
  '███████ ███████',
  '█████████████████',
  '█████████████████',
  '███████████████',
  '███████████',
  '█████',
  '█',
];

const _launchPatterns = <_LaunchPattern>[
  _LaunchPattern(-8, -1.1, 1.4, 2.4, 0.1, 2.2, 0),
  _LaunchPattern(-6, -0.6, 2, 2, 0.8, 2.5, 1),
  _LaunchPattern(-4, -0.2, 1.2, 3.1, 1.4, 2.8, 2),
  _LaunchPattern(-2, 0.3, 1.8, 2.7, 2, 2.4, 3),
  _LaunchPattern(0, 0, 0.8, 3.6, 2.6, 3, 4),
  _LaunchPattern(2, -0.3, 1.8, 2.7, 3.2, 2.4, 5),
  _LaunchPattern(4, 0.2, 1.2, 3.1, 3.8, 2.8, 0),
  _LaunchPattern(6, 0.6, 2, 2, 4.4, 2.5, 1),
  _LaunchPattern(8, 1.1, 1.4, 2.4, 5, 2.2, 2),
];

void main() => runTuiApp(const LikeReactorApp(), enableMouse: true);

/// Deterministic particle state for the Like Reactor example.
class LikeReactorSimulation {
  LikeReactorSimulation() {
    _emitBurst(animateCore: false);
  }

  final List<LikeParticle> _particles = <LikeParticle>[];
  int _burstCount = 0;
  double _corePulse = 0;

  /// Number of bursts emitted, including the introductory burst.
  int get burstCount => _burstCount;

  /// Current heart-core activation in the inclusive range 0–1.
  double get corePulse => _corePulse;

  /// Read-only view of the live particles, ordered from oldest to newest.
  List<LikeParticle> get particles => UnmodifiableListView(_particles);

  bool get _needsFrames => _particles.isNotEmpty || _corePulse > 0;

  /// Emits one user-triggered burst and activates the heart core.
  void burst() => _emitBurst(animateCore: true);

  /// Advances all live state by [seconds].
  void advance(double seconds) {
    if (!seconds.isFinite || seconds < 0) {
      throw ArgumentError.value(
        seconds,
        'seconds',
        'must be finite and non-negative',
      );
    }
    if (seconds == 0) {
      return;
    }

    for (final particle in _particles) {
      particle._age += seconds;
    }
    _particles.removeWhere((particle) => particle._age >= particle.lifetime);
    _corePulse = math.max(0, _corePulse - seconds / _pulseSeconds);
  }

  /// Removes all particles without changing the historical burst count.
  void clear() => _particles.clear();

  void _emitBurst({required bool animateCore}) {
    final burstIndex = burstCount;
    _burstCount++;

    for (var index = 0; index < _particlesPerBurst; index++) {
      final pattern = _launchPatterns[index];
      _particles.add(
        LikeParticle._(
          launchOffset: pattern.launchOffset,
          lateralVelocity: pattern.lateralVelocity,
          driftAmplitude: pattern.driftAmplitude,
          frequency: pattern.frequency,
          phase: pattern.phase + burstIndex * 0.41,
          lifetime: pattern.lifetime,
          colorIndex:
              (pattern.colorIndex + burstIndex) % _reactorPalette.length,
        ),
      );
    }

    if (_particles.length > _maximumParticles) {
      _particles.removeRange(0, _particles.length - _maximumParticles);
    }
    if (animateCore) {
      _corePulse = 1;
    }
  }
}

/// One deterministic Like Reactor particle.
class LikeParticle {
  LikeParticle._({
    required this.launchOffset,
    required this.lateralVelocity,
    required this.driftAmplitude,
    required this.frequency,
    required this.phase,
    required this.lifetime,
    required this.colorIndex,
  });

  /// Horizontal launch position relative to the stage center.
  final double launchOffset;

  /// Constant horizontal motion in terminal cells per second.
  final double lateralVelocity;

  /// Width of the particle's sinusoidal sway.
  final double driftAmplitude;

  /// Angular frequency of the particle's sinusoidal sway.
  final double frequency;

  /// Initial phase offset for the particle's sway.
  final double phase;

  /// Lifetime of the particle in seconds.
  final double lifetime;

  /// Index into the Like Reactor particle palette.
  final int colorIndex;

  double _age = 0;

  /// Current particle age in seconds.
  double get age => _age;

  /// Normalized lifetime progress in the inclusive range 0–1.
  double get progress => (_age / lifetime).clamp(0.0, 1.0);

  /// Glyph for the particle's current lifetime phase, fading from a solid
  /// sparkle to a faint dot. All four are narrow [Icons] members, so a
  /// particle keeps the same cell width for its whole flight.
  String get glyph {
    if (progress < 0.55) return Icons.sparkle;
    if (progress < 0.82) return Icons.sparkleOutline;
    if (progress < 0.94) return Icons.starSmall;
    return Icons.bulletSmall;
  }

  /// Projects this particle onto a horizontal terminal cell.
  int cellX(int width) {
    if (width <= 0) {
      throw RangeError.range(width, 1, null, 'width');
    }
    final center = (width - 1) / 2;
    final sway = math.sin(_age * frequency + phase) * driftAmplitude;
    final position = center + launchOffset + lateralVelocity * _age + sway;
    return position.round().clamp(0, width - 1);
  }

  /// Projects this particle onto a vertical terminal cell.
  int cellY(int height) {
    if (height <= 0) {
      throw RangeError.range(height, 1, null, 'height');
    }
    return (height - 1 - progress * (height - 1)).round().clamp(0, height - 1);
  }
}

class LikeReactorApp extends StatefulWidget {
  const LikeReactorApp({this.simulation, super.key});

  /// Optional externally owned simulation, useful for observing commands.
  final LikeReactorSimulation? simulation;

  @override
  State<LikeReactorApp> createState() => _LikeReactorAppState();
}

class _LikeReactorAppState extends State<LikeReactorApp>
    with SingleTickerProviderStateMixin<LikeReactorApp> {
  LikeReactorSimulation? _ownedSimulation;
  late final AnimationController _controller;
  double _previousControllerValue = 0;

  LikeReactorSimulation get _simulation =>
      widget.simulation ?? (_ownedSimulation ??= LikeReactorSimulation());

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
      debugLabel: 'Like Reactor timeline',
    );
    _controller.addListener(_onTick);
    _controller.addStatusListener(_onStatusChanged);
    _controller.forward(from: 0);
  }

  void _onTick() {
    final value = _controller.value;
    final elapsedSeconds = (value - _previousControllerValue).abs();
    _previousControllerValue = value;
    if (!mounted || elapsedSeconds == 0) {
      return;
    }
    _simulation.advance(elapsedSeconds);
    if (!_simulation._needsFrames) {
      _controller.stop();
    }
    setState(() {});
  }

  void _onStatusChanged(AnimationStatus status) {
    if ((status != AnimationStatus.completed &&
            status != AnimationStatus.dismissed) ||
        !_simulation._needsFrames) {
      return;
    }
    if (status == AnimationStatus.completed) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  void _burst() {
    setState(_simulation.burst);
    if (_controller.isAnimating) {
      return;
    }
    _previousControllerValue = _controller.value;
    if (_controller.status == AnimationStatus.completed ||
        _controller.status == AnimationStatus.reverse) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!event.isPress) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      _burst();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _ownedSimulation?.clear();
    _controller.removeListener(_onTick);
    _controller.removeStatusListener(_onStatusChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _handleKey,
    child: Container(
      color: _reactorSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 2,
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(
                'NOIR · LIKE REACTOR',
                style: TextStyle(
                  color: _reactorMuted,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
          Expanded(
            child: Align(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ParticleStage(particles: _simulation.particles),
                  const SizedBox(height: 1),
                  _HeartReactor(
                    pulse: _simulation.corePulse,
                    onPressed: _burst,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Space/Enter/click burst · Ctrl+C exit',
              style: TextStyle(color: _reactorMuted),
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ParticleStage extends StatelessWidget {
  const _ParticleStage({required this.particles});

  final List<LikeParticle> particles;

  @override
  Widget build(BuildContext context) {
    final cells = List<List<LikeParticle?>>.generate(
      _stageHeight,
      (_) => List<LikeParticle?>.filled(_stageWidth, null),
    );

    for (final particle in particles) {
      final x = particle.cellX(_stageWidth);
      final y = particle.cellY(_stageHeight);
      final current = cells[y][x];
      if (current == null || particle.age <= current.age) {
        cells[y][x] = particle;
      }
    }

    return SizedBox(
      width: _stageWidth,
      height: _stageHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final row in cells) _ParticleRow(cells: row)],
      ),
    );
  }
}

class _ParticleRow extends StatelessWidget {
  const _ParticleRow({required this.cells});

  final List<LikeParticle?> cells;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(children: _buildSpans()),
    maxLines: 1,
    softWrap: false,
  );

  List<InlineSpan> _buildSpans() {
    final spans = <InlineSpan>[];
    var column = 0;
    while (column < cells.length) {
      final particle = cells[column];
      if (particle != null) {
        spans.add(
          TextSpan(
            text: particle.glyph,
            style: TextStyle(
              color: _reactorPalette[particle.colorIndex],
              fontWeight: particle.progress >= 0.82
                  ? FontWeight.dim
                  : FontWeight.bold,
            ),
          ),
        );
        column++;
        continue;
      }

      final blankStart = column;
      while (column < cells.length && cells[column] == null) {
        column++;
      }
      spans.add(
        TextSpan(text: List<String>.filled(column - blankStart, ' ').join()),
      );
    }
    return spans;
  }
}

class _HeartReactor extends StatelessWidget {
  const _HeartReactor({required this.pulse, required this.onPressed});

  final double pulse;
  final VoidCallback onPressed;

  void _handlePointerDown(MouseEvent event) {
    if (event.button == MouseButton.left) {
      onPressed();
    }
  }

  List<String> get _rows {
    if (pulse > 2 / 3) return _fullHeart;
    if (pulse > 1 / 3) return _mediumHeart;
    return _compactHeart;
  }

  @override
  Widget build(BuildContext context) => PointerListener(
    onPointerDown: _handlePointerDown,
    child: SizedBox(
      width: _heartFootprintWidth,
      height: _heartFootprintHeight,
      child: Align(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in _rows)
              Text(
                row,
                style: TextStyle(
                  color: Color.lerp(_reactorCore, _reactorCorePulse, pulse),
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
              ),
          ],
        ),
      ),
    ),
  );
}

class _LaunchPattern {
  const _LaunchPattern(
    this.launchOffset,
    this.lateralVelocity,
    this.driftAmplitude,
    this.frequency,
    this.phase,
    this.lifetime,
    this.colorIndex,
  );

  final double launchOffset;
  final double lateralVelocity;
  final double driftAmplitude;
  final double frequency;
  final double phase;
  final double lifetime;
  final int colorIndex;
}
