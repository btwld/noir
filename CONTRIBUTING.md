# Contributing to Noir Framework

Thank you for your interest in contributing to Noir! This document outlines our coding standards and development practices.

## Development Setup

### Prerequisites
- Dart SDK >= 3.10.0
- Git

### Getting Started
```bash
git clone https://github.com/leoafarias/noir.git
cd noir

dart pub get

dart test --exclude-tags process-spawning --concurrency=1
```

## Coding Standards

### Code Formatting

**All Dart code must be formatted using `dart format`.**

```bash
dart format lib/ test/ example/

dart format --output=none --set-exit-if-changed lib/ test/ example/
```

### Static Analysis

**All code must pass `dart analyze` with zero errors.**

```bash
dart analyze

dart analyze --fatal-infos
```

### Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Classes | PascalCase | `StatelessWidget`, `BoxDecoration` |
| Methods/Functions | camelCase | `build()`, `createState()` |
| Variables | camelCase | `effectivePadding`, `childCount` |
| Constants | camelCase | `center`, `topLeft` |
| Private members | _camelCase | `_buildChild()`, `_state` |
| File names | snake_case | `box_decoration.dart`, `render_object.dart` |

### Import Organization

Imports should be organized in the following order, with blank lines between groups:

```dart
// 1. Dart SDK imports
import 'dart:ffi';
import 'dart:math';

// 2. Package imports (external dependencies)
import 'package:ffi/ffi.dart';

// 3. Relative imports (within this package)
import '../framework/widget.dart';
import 'container.dart';
```

**Prefer relative imports** within the `lib/` directory for better refactoring support.

### Documentation Standards

All public APIs require documentation:

```dart
/// A widget that displays text with styling.
///
/// The [Text] widget displays a string of text with a single style.
/// For rich text with multiple styles, use [RichText].
///
/// **Terminal-specific considerations:**
/// Text rendering respects terminal character cell boundaries. Wide
/// characters (CJK, emoji) occupy two cells.
///
/// Example:
/// ```dart
/// Text(
///   'Hello, Terminal!',
///   style: TextStyle(color: Color.green),
/// )
/// ```
class Text extends StatelessWidget {
  /// Creates a text widget.
  ///
  /// The [data] parameter must not be null.
  const Text(this.data, {this.style, super.key});

  /// The text to display.
  final String data;

  /// The style to use for the text.
  ///
  /// If null, the text will use the default style from the ambient
  /// [DefaultTextStyle].
  final TextStyle? style;
}
```

**Documentation requirements:**
- All public classes need a summary description
- All public methods and properties need documentation
- Include terminal-specific behavior notes where applicable
- Use `///` for documentation comments (not `/** */`)
- Add `@override` annotation on overridden methods

### Code Style

#### Prefer Expression Bodies
```dart
// Good
Widget build(BuildContext context) => Text('Hello');

// Acceptable for complex logic
Widget build(BuildContext context) {
  final decoration = _buildDecoration();
  return Container(decoration: decoration, child: child);
}
```

#### Use Trailing Commas
```dart
// Good - trailing comma enables better formatting
const Container(
  padding: EdgeInsets.all(8),
  color: Color.blue,
  child: Text('Content'),
);

// Avoid - no trailing comma
const Container(padding: EdgeInsets.all(8), color: Color.blue, child: Text('Content'));
```

#### Prefer Final Variables
```dart
// Good
final result = calculateLayout();
for (final child in children) { ... }

// Avoid
var result = calculateLayout();
for (var child in children) { ... }
```

#### Use Assertions for Validation
```dart
const Container({
  this.color,
  this.decoration,
}) : assert(
       color == null || decoration == null,
       'Cannot provide both a color and a decoration\n'
       'To provide both, use "decoration: BoxDecoration(color: color)".',
     );
```

### Widget Development Guidelines

#### Follow Flutter Patterns
- Extend `StatelessWidget` or `StatefulWidget`
- Use `const` constructors where possible
- Prefer composition over inheritance
- Keep `build()` methods focused and readable

#### Terminal Constraints
- All dimensions are in character cells (integers)
- `Color` stores normalized RGBA channels and exposes palette constants
- No matrix transforms (rotation, skew, scale)
- No clipping masks (only rectangular bounds)

#### State Management
```dart
class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _count = 0;

  void _increment() {
    setState(() {
      _count++;
    });
  }

  @override
  Widget build(BuildContext context) => Text('Count: $_count');
}
```

## Testing

### Running Tests
```bash
dart test --exclude-tags process-spawning --concurrency=1

dart test test/architecture/

dart test test/layout_widgets_test.dart --reporter=expanded

dart test test/container_widget_test.dart --name="container"
```

Focused unit, widget, golden, and architecture tests are ordinary
repository-local validation. The standard checkpoint excludes the
`process-spawning` tag because that tag also contains isolated subprocess
checks and the parity wrapper's deliberate signal/termination lifecycle
coverage. Do not select the whole tag or the whole parity directory without
first checking the selected tests.

Memory-leak, sanitizer, resource-exhaustion, deliberate crash or fatal-signal,
real-terminal/PTY, native rebuild or artifact mutation, workflow, publication,
and release operations require exact user authorization. See `AGENTS.md` for
the authoritative validation policy and the separately authorized health and
primitive-parity commands.

### Test Types

| Type | Purpose | Location |
|------|---------|----------|
| Unit & widget | Per-area behavior | `test/<area>/` (e.g. `test/widgets/`, `test/core/`, `test/rendering/`) |
| Golden | Visual regression via buffer captures | `test/golden/` (stored captures in `test/goldens/`) |
| Architecture | Fitness functions enforcing layer boundaries | `test/architecture/` |
| Parity | Dart output vs. Go reference renderer | `test/parity/` |
| Regression | Pinned bug reproductions | `test/regression/` |

### Writing Tests
```dart
void main() {
  group('Container', () {
    test('should apply padding to child', () {
      final container = Container(
        padding: EdgeInsets.all(2),
        child: Text('Hello'),
      );

      final element = layoutWidget(container, maxWidth: 20, maxHeight: 10);
      // Assertions...
    });
  });
}
```

## Git Workflow

### Branch Naming
- Feature branches: `feature/description`
- Bug fixes: `fix/description`
- Documentation: `docs/description`

### Commit Messages

Write clear, concise commit messages:

```
feat: Add focus management to TuiApp

- Implement FocusNode and FocusScope widgets
- Add keyboard navigation between focusable elements
- Update TuiApp to track active focus
```

**Format:**
- First line: type + short description (50 chars max)
- Blank line
- Body: detailed explanation if needed (wrap at 72 chars)

**Types:** `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

### Pull Request Checklist

Before submitting a PR:

- [ ] Code passes `dart analyze` with no errors
- [ ] Code is formatted with `dart format`
- [ ] The authorized validation partitions pass (see Testing above)
- [ ] New features include tests
- [ ] Public APIs are documented
- [ ] Commit messages follow conventions

## Architecture Overview

```
lib/
├── noir.dart          # Main library export
└── src/
    ├── ffi/              # FFI bindings to OpenTUI
    ├── core/             # OpenTUI primitives (Buffer, Renderer)
    ├── framework/        # Widget/Element/BuildContext
    ├── rendering/        # RenderObject and layout
    ├── widgets/          # Widget implementations
    ├── painting/         # Styling (TextStyle, BoxDecoration)
    ├── animation/        # AnimationController, Ticker
    └── app/              # TuiApp entry point
```

### Key Concepts

- **Widget**: Immutable configuration for UI elements
- **Element**: Mutable widget instance in the tree
- **RenderObject**: Handles layout and painting
- **BuildContext**: Access to element tree and inherited widgets

## Questions?

For questions about contributing, please open a GitHub issue.
