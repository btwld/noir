// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:meta/meta.dart';

@immutable
final class GitPath {
  factory GitPath.fromBytes(Iterable<int> bytes) {
    final copy = bytes.toList(growable: false);
    _validateGitPathBytes(copy);
    return GitPath._(List<int>.unmodifiable(copy));
  }

  factory GitPath.utf8(String path) {
    final encoded = utf8.encode(path);
    if (utf8.decode(encoded) != path) {
      throw ArgumentError.value(path, 'path', 'Must be well-formed UTF-16.');
    }
    return GitPath.fromBytes(encoded);
  }

  const GitPath._(this._bytes);

  final List<int> _bytes;

  List<int> get bytes => List<int>.unmodifiable(_bytes);

  String get identityKey =>
      base64Url.encode(_bytes).replaceAll(RegExp(r'=+$'), '');

  String? tryDecodeUtf8() {
    try {
      return utf8.decode(_bytes);
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GitPath || other._bytes.length != _bytes.length) {
      return false;
    }
    for (var i = 0; i < _bytes.length; i++) {
      if (_bytes[i] != other._bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_bytes);

  @override
  String toString() => 'GitPath($identityKey)';
}

final class GitPathPresentation {
  factory GitPathPresentation.asciiSafe(GitPath path) {
    final components = _splitPathComponents(path._bytes);
    final presented = <List<String>>[
      for (final component in components) _presentPathComponent(component),
    ];
    final componentText = <String>[
      for (final tokens in presented) tokens.join(),
    ];
    final parentCandidates = componentText
        .take(componentText.length - 1)
        .where((component) => component.length > 1)
        .toList(growable: false);
    return GitPathPresentation._(
      full: componentText.join('/'),
      basename: componentText.last,
      parentPath: componentText.take(componentText.length - 1).join('/'),
      parentHint: parentCandidates.isEmpty ? '' : parentCandidates.last,
      basenameTokens: List<String>.unmodifiable(presented.last),
    );
  }

  const GitPathPresentation._({
    required this.full,
    required this.basename,
    required this.parentPath,
    required this.parentHint,
    required List<String> basenameTokens,
  }) : _basenameTokens = basenameTokens;

  final String full;
  final String basename;

  /// Presented parent directory path — every component except the basename
  /// joined with `/`, empty for top-level paths.
  final String parentPath;
  final String parentHint;
  final List<String> _basenameTokens;

  String truncateBasename(int maxColumns) {
    if (maxColumns < 0) {
      throw ArgumentError.value(
        maxColumns,
        'maxColumns',
        'Must be non-negative.',
      );
    }
    if (basename.length <= maxColumns) return basename;
    if (maxColumns <= 3) return '.' * maxColumns;

    var remaining = maxColumns - 3;
    final suffix = <String>[];
    for (final token in _basenameTokens.reversed) {
      if (token.length > remaining) break;
      suffix.insert(0, token);
      remaining -= token.length;
    }
    return '...${suffix.join()}';
  }
}

final class GitDiagnosticText {
  factory GitDiagnosticText.fromBytes(Iterable<int> bytes) {
    final output = StringBuffer();
    var index = 0;
    for (final byte in bytes) {
      if (byte < 0 || byte > 0xff) {
        throw RangeError.range(byte, 0, 0xff, 'bytes[$index]');
      }
      output.write(_diagnosticByte(byte));
      index++;
    }
    return GitDiagnosticText._(output.toString());
  }

  factory GitDiagnosticText.fromObject(Object value) {
    String rendered;
    try {
      rendered = value.toString();
    } on Object {
      rendered = 'Exception text unavailable.';
    }
    final compact = rendered
        .trim()
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    final nonempty = compact.isEmpty ? 'Exception text unavailable.' : compact;
    return GitDiagnosticText.fromBytes(utf8.encode(nonempty));
  }

  const GitDiagnosticText._(this.text);

  final String text;

  @override
  String toString() => text;
}

int compareGitPaths(GitPath left, GitPath right) {
  final commonLength = left._bytes.length < right._bytes.length
      ? left._bytes.length
      : right._bytes.length;
  for (var i = 0; i < commonLength; i++) {
    final comparison = left._bytes[i].compareTo(right._bytes[i]);
    if (comparison != 0) return comparison;
  }
  return left._bytes.length.compareTo(right._bytes.length);
}

List<List<int>> gitPathComponents(GitPath path) => [
  for (final component in _splitPathComponents(path._bytes))
    List<int>.unmodifiable(component),
];

void _validateGitPathBytes(List<int> bytes) {
  if (bytes.isEmpty) {
    throw ArgumentError.value(bytes, 'bytes', 'Git paths must not be empty.');
  }
  for (var i = 0; i < bytes.length; i++) {
    final byte = bytes[i];
    if (byte < 0 || byte > 0xff) {
      throw RangeError.range(byte, 0, 0xff, 'bytes[$i]');
    }
    if (byte == 0) {
      throw ArgumentError.value(
        bytes,
        'bytes',
        'Git paths cannot contain NUL.',
      );
    }
  }
  if (bytes.first == 0x2f || bytes.last == 0x2f) {
    throw ArgumentError.value(
      bytes,
      'bytes',
      'Git paths must be repository-relative without edge slashes.',
    );
  }
  for (final component in _splitPathComponents(bytes)) {
    if (component.isEmpty ||
        _bytesEqual(component, const [0x2e]) ||
        _bytesEqual(component, const [0x2e, 0x2e])) {
      throw ArgumentError.value(
        bytes,
        'bytes',
        'Git paths cannot contain empty, dot, or dot-dot components.',
      );
    }
  }
}

List<List<int>> _splitPathComponents(List<int> bytes) {
  final result = <List<int>>[];
  var start = 0;
  for (var i = 0; i <= bytes.length; i++) {
    if (i == bytes.length || bytes[i] == 0x2f) {
      result.add(bytes.sublist(start, i));
      start = i + 1;
    }
  }
  return result;
}

List<String> _presentPathComponent(List<int> bytes) => [
  for (var i = 0; i < bytes.length; i++)
    _presentPathByte(bytes[i], edgeSpace: i == 0 || i == bytes.length - 1),
];

String _presentPathByte(int byte, {required bool edgeSpace}) {
  if (byte == 0x20 && edgeSpace) return r'\x20';
  if (byte == 0x22) return r'\"';
  if (byte == 0x5c) return r'\\';
  if (byte >= 0x20 && byte <= 0x7e) return String.fromCharCode(byte);
  return '\\x${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}';
}

String _diagnosticByte(int byte) => switch (byte) {
  0x07 => r'\a',
  0x08 => r'\b',
  0x09 => r'\t',
  0x0a => r'\n',
  0x0b => r'\v',
  0x0c => r'\f',
  0x0d => r'\r',
  0x1b => r'\e',
  0x5c => r'\\',
  >= 0x20 && <= 0x7e => String.fromCharCode(byte),
  _ => '\\x${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}',
};

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
