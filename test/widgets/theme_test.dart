import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

void main() {
  group('ThemeData', () {
    test('dark tokens match the literals the built-in widgets already use', () {
      // Phase D retrofits Select/TextInput/TextArea/ScrollBox onto these
      // tokens. Byte-identical defaults are what make that retrofit invisible
      // for apps that opt into ThemeData.dark.
      const theme = ThemeData.dark;
      expect(theme.text, Color.white);
      expect(theme.textMuted, const Color(0.6, 0.6, 0.6));
      expect(theme.selectedBackground, const Color(0.2, 0.4, 0.8));
      expect(theme.selectedForeground, Color.white);
      expect(theme.cursor, Color.white);
      expect(theme.scrollbarThumb, const Color(0.7, 0.7, 0.7));
      expect(theme.scrollbarTrack, const Color(0.2, 0.2, 0.2));
    });

    test('copyWith replaces only the named tokens', () {
      const base = ThemeData.dark;
      final updated = base.copyWith(text: Color.red, accent: Color.green);

      expect(updated.text, Color.red);
      expect(updated.accent, Color.green);
      expect(updated.surface, base.surface);
      expect(updated.cursor, base.cursor);
    });

    test('equality and hashCode are field-wise', () {
      const base = ThemeData.dark;

      expect(base.copyWith(), base);
      expect(base.copyWith().hashCode, base.hashCode);
      expect(base.copyWith(info: Color.magenta), isNot(base));
    });
  });

  group('Theme', () {
    test('maybeOf returns null and of falls back without an ancestor', () {
      final owner = BuildOwner();
      final probes = <ThemeData?>[];
      final element = _ThemeProbe(onBuild: probes.add).createElement();

      element.mount(null, owner);
      owner.buildScope();

      expect(probes, hasLength(1));
      expect(probes.single, isNull);
      expect(_ThemeProbe.lastResolved, ThemeData.dark);

      element.unmount();
    });

    test('of returns the nearest ancestor data', () {
      final owner = BuildOwner();
      final probes = <ThemeData?>[];
      final element = Theme(
        data: ThemeData.dark.copyWith(text: Color.yellow),
        child: _ThemeProbe(onBuild: probes.add),
      ).createElement();

      element.mount(null, owner);
      owner.buildScope();

      expect(probes.single?.text, Color.yellow);

      element.unmount();
    });

    test('updateShouldNotify tracks data equality, not identity', () {
      const child = SizedBox.shrink();
      const theme = Theme(data: ThemeData.dark, child: child);

      expect(
        theme.updateShouldNotify(
          Theme(data: ThemeData.dark.copyWith(), child: child),
        ),
        isFalse,
      );
      expect(
        theme.updateShouldNotify(
          Theme(
            data: ThemeData.dark.copyWith(accent: Color.cyan),
            child: child,
          ),
        ),
        isTrue,
      );
    });

    test('dependents read the new palette after data changes', () {
      final owner = BuildOwner();
      final probes = <ThemeData?>[];
      final probe = _ThemeProbe(onBuild: probes.add);
      final element = Theme(data: ThemeData.dark, child: probe).createElement();

      element.mount(null, owner);
      owner.buildScope();
      expect(probes.single?.accent, ThemeData.dark.accent);

      element.update(
        Theme(
          data: ThemeData.dark.copyWith(accent: Color.cyan),
          child: probe,
        ),
      );
      owner.buildScope();
      expect(probes.last?.accent, Color.cyan);

      element.unmount();
    });

    test('a resolved token reaches painted cells', () {
      final capture = BufferCapture(width: 12, height: 3);
      try {
        final frame = capture.capture(
          Theme(
            data: ThemeData.dark.copyWith(text: Color.magenta),
            child: const _ThemedText(),
          ),
        );
        expect(frame, BufferMatchers.hasCharAt(0, 0, 'x'));
        expect(frame, BufferMatchers.hasColorAt(0, 0, Color.magenta));
      } finally {
        capture.dispose();
      }
    });

    test('the nearest enclosing Theme wins', () {
      final capture = BufferCapture(width: 12, height: 3);
      try {
        final frame = capture.capture(
          Theme(
            data: ThemeData.dark.copyWith(text: Color.magenta),
            child: Theme(
              data: ThemeData.dark.copyWith(text: Color.green),
              child: const _ThemedText(),
            ),
          ),
        );
        expect(frame, BufferMatchers.hasColorAt(0, 0, Color.green));
      } finally {
        capture.dispose();
      }
    });
  });
}

/// Paints a single cell in [ThemeData.text] so a resolved token is observable
/// in a captured buffer.
class _ThemedText extends StatelessWidget {
  const _ThemedText();

  @override
  Widget build(BuildContext context) =>
      Text('x', style: TextStyle(color: Theme.of(context).text));
}

/// Records the [Theme.maybeOf] result on every build and stashes the matching
/// [Theme.of] result so the no-ancestor fallback is observable.
class _ThemeProbe extends StatelessWidget {
  const _ThemeProbe({required this.onBuild});

  static ThemeData? lastResolved;

  final void Function(ThemeData?) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(Theme.maybeOf(context));
    lastResolved = Theme.of(context);
    return const SizedBox.shrink();
  }
}
