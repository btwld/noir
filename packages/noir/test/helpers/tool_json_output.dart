import 'dart:convert';

/// Decodes JSON lines even when Dart prefixes the first one with hook status.
List<Map<String, Object?>> decodeToolJsonObjects(String output) {
  final objects = <Map<String, Object?>>[];
  for (final line in const LineSplitter().convert(output)) {
    final jsonStart = line.indexOf('{');
    if (jsonStart < 0) continue;
    objects.add(
      Map<String, Object?>.from(jsonDecode(line.substring(jsonStart)) as Map),
    );
  }
  return objects;
}
