/// Canonical Noir example — a minimal Flutter-like terminal app.
///
/// pub.dev surfaces this file on the package's Example tab. It reuses the
/// [HelloApp] widget from `hello.dart`; browse the other files in this
/// directory (and `example/README.md`) for focused demos of state, layout,
/// focus, scrolling, animation, and input.
///
/// Run from the package root:
///   dart run example/main.dart
library;

import 'package:noir/noir.dart';

import 'hello.dart';

void main() => runTuiApp(const HelloApp());
