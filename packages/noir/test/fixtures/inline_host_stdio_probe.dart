import 'dart:io';

import 'package:noir/noir.dart';

/// Draws a live row on stderr through the public entry point.
///
/// An explicit width needs no terminal, so the parent test can read both
/// streams as pipes and see exactly which one the host wrote to. The process
/// must then end on its own: nothing here calls `exit`.
Future<void> main() async {
  final host = InlineHost.start(
    sink: stderr,
    columns: () => 40,
    colors: false,
    child: const Row(children: <Widget>[Spinner(), Text(' working')]),
  );
  // The first frame runs from a zero-delay timer that start() created.
  await Future<void>.delayed(Duration.zero);
  host
    ..printAbove('step done')
    ..dispose();
}
