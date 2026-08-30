import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

typedef _Owner = ({String path, String name});

void main() {
  late AnalysisContextCollection collection;
  final resolvedUnits = <String, Future<ResolvedUnitResult>>{};

  setUpAll(() {
    collection = AnalysisContextCollection(
      includedPaths: <String>[Directory.current.absolute.path],
    );
  });

  tearDownAll(() => collection.dispose());

  Future<ResolvedUnitResult> resolve(String relativePath) =>
      resolvedUnits.putIfAbsent(relativePath, () async {
        final absolutePath = path.normalize(
          path.join(Directory.current.absolute.path, relativePath),
        );
        final result = await collection
            .contextFor(absolutePath)
            .currentSession
            .getResolvedUnit(absolutePath);
        expect(
          result,
          isA<ResolvedUnitResult>(),
          reason: 'Analyzer could not resolve $relativePath: $result',
        );
        return result as ResolvedUnitResult;
      });

  test(
    'retained owners expose exactly the approved internal member seams',
    () async {
      for (final expectation in _internalMembers.entries) {
        final declaration = await _classDeclaration(resolve, expectation.key);
        final actual = <String>{
          for (final member in declaration.members)
            if (_memberElement(member)?.metadata.hasInternal ?? false)
              _memberName(member),
        };
        expect(
          actual,
          expectation.value,
          reason:
              '${expectation.key.path}:${expectation.key.name} must match the '
              'frozen supported-versus-internal matrix exactly.',
        );
      }
    },
  );

  test(
    'protected and visible-for-testing seams carry both annotations',
    () async {
      for (final owner in _protectedMembers.entries) {
        final declaration = await _classDeclaration(resolve, owner.key);
        for (final memberName in owner.value) {
          final member = _member(declaration, memberName);
          final metadata = _memberElement(member)!.metadata;
          expect(metadata.hasInternal, isTrue, reason: '$owner.$memberName');
          expect(metadata.hasProtected, isTrue, reason: '$owner.$memberName');
        }
      }

      final renderer = await _classDeclaration(resolve, _rendererOwner);
      final debugCurrentBuffer = _member(renderer, 'debugCurrentBuffer');
      final metadata = _memberElement(debugCurrentBuffer)!.metadata;
      expect(metadata.hasInternal, isTrue);
      expect(metadata.hasVisibleForTesting, isTrue);
    },
  );

  test('FocusAttachment is an internal implementation type', () async {
    final declaration = await _classDeclaration(resolve, _focusAttachmentOwner);
    expect(declaration.declaredFragment!.element.metadata.hasInternal, isTrue);
  });

  test('all exported createElement overrides are internal and exact', () async {
    final actualOwners = <_Owner>{};
    for (final file in <String>[
      ..._dartFilesUnder('lib/src/framework'),
      ..._dartFilesUnder('lib/src/widgets'),
    ]) {
      final unit = await resolve(file);
      for (final declaration
          in unit.unit.declarations.whereType<ClassDeclaration>()) {
        if (declaration.name.lexeme.startsWith('_')) continue;
        if (declaration.members.whereType<MethodDeclaration>().any(
          (member) => member.name.lexeme == 'createElement',
        )) {
          actualOwners.add((path: file, name: declaration.name.lexeme));
        }
      }
    }
    expect(actualOwners, _createElementOwners);

    for (final owner in actualOwners) {
      final declaration = await _classDeclaration(resolve, owner);
      expect(
        _memberElement(
          _member(declaration, 'createElement'),
        )!.metadata.hasInternal,
        isTrue,
        reason: '${owner.path}:${owner.name}.createElement must be @internal.',
      );
    }
  });

  test(
    'only the exact built-in high render widgets declare render factories',
    () async {
      final actualOwners = <_Owner>{};
      for (final file in _dartFilesUnder('lib/src/widgets')) {
        final unit = await resolve(file);
        for (final declaration
            in unit.unit.declarations.whereType<ClassDeclaration>()) {
          if (declaration.name.lexeme.startsWith('_')) continue;
          final names = declaration.members
              .whereType<MethodDeclaration>()
              .map((member) => member.name.lexeme)
              .toSet();
          if (names.contains('createRenderObject')) {
            actualOwners.add((path: file, name: declaration.name.lexeme));
          }
        }
      }
      expect(actualOwners, _builtInRenderWidgetOwners);

      for (final owner in actualOwners) {
        final declaration = await _classDeclaration(resolve, owner);
        for (final memberName in const <String>{
          'createRenderObject',
          'updateRenderObject',
        }) {
          expect(
            _memberElement(
              _member(declaration, memberName),
            )!.metadata.hasInternal,
            isTrue,
            reason:
                '${owner.path}:${owner.name}.$memberName must be @internal.',
          );
        }
      }
    },
  );

  test(
    'custom render-widget hooks stay supported while bridges stay private',
    () async {
      final renderObjectWidget = await _classDeclaration(
        resolve,
        _renderObjectWidgetOwner,
      );
      for (final memberName in const <String>{
        'createRenderObject',
        'updateRenderObject',
      }) {
        expect(
          _memberElement(
            _member(renderObjectWidget, memberName),
          )!.metadata.hasInternal,
          isFalse,
          reason: 'Advanced consumers must retain $memberName.',
        );
      }

      for (final owner in _privateBridgeOwners) {
        final declaration = await _classDeclaration(resolve, owner);
        expect(declaration.name.lexeme.startsWith('_'), isTrue);
      }
    },
  );

  test('BuildOwner and Buffer construction hide raw native owners', () async {
    final buildOwner = await _classDeclaration(resolve, _buildOwnerOwner);
    final constructors = buildOwner.members.whereType<ConstructorDeclaration>();
    final unnamed = constructors.singleWhere(
      (constructor) => constructor.name == null,
    );
    expect(
      unnamed.parameters.parameters
          .map((parameter) => parameter.toSource())
          .join(', '),
      isNot(contains('PipelineOwner')),
    );
    final testConstructor = constructors.singleWhere(
      (constructor) => constructor.name?.lexeme == 'test',
    );
    expect(
      testConstructor.declaredFragment!.element.metadata.hasInternal,
      isTrue,
    );

    final buffer = await _classDeclaration(resolve, _bufferOwner);
    final bufferConstructors = buffer.members
        .whereType<ConstructorDeclaration>()
        .map((constructor) => constructor.name?.lexeme ?? 'new')
        .toSet();
    expect(bufferConstructors, const <String>{'_', '_withValidity'});
    expect(
      bufferConstructors.every((constructor) => constructor.startsWith('_')),
      isTrue,
      reason: 'Buffer must have no source-public constructor.',
    );

    final bufferUnit = await resolve(_bufferOwner.path);
    final factory = bufferUnit.unit.declarations
        .whereType<FunctionDeclaration>()
        .singleWhere(
          (declaration) => declaration.name.lexeme == 'createBufferFromNative',
        );
    expect(factory.declaredFragment!.element.metadata.hasInternal, isTrue);
  });

  test('supported signatures close for high, high+low, and FFI-only', () async {
    final high = (await resolve('lib/noir.dart')).libraryElement;
    final low = (await resolve('lib/noir_low_level.dart')).libraryElement;
    final ffi = (await resolve('lib/noir_ffi.dart')).libraryElement;

    final tiers = <String, Map<String, Element>>{
      'high': high.exportNamespace.definedNames2,
      'high+low': <String, Element>{
        ...high.exportNamespace.definedNames2,
        ...low.exportNamespace.definedNames2,
      },
      'ffi': ffi.exportNamespace.definedNames2,
    };

    for (final tier in tiers.entries) {
      final available = tier.value.values.toSet();
      final failures = <String>[];
      for (final exported in tier.value.entries) {
        for (final signature in _supportedSignatureTypes(exported.value)) {
          final missing = <String>{};
          _collectMissingTypes(signature.type, available, missing);
          for (final type in missing) {
            failures.add('${exported.key}.${signature.owner} -> $type');
          }
        }
      }
      failures.sort();
      if (failures.isNotEmpty) {
        fail(
          "${tier.key} supported signatures must close over that tier's "
          'selected imports. Internal members are the only exclusions:\n'
          '${failures.join('\n')}',
        );
      }
    }
  });

  test('canonical fixed-width guards remain at Dart FFI boundaries', () async {
    final unit = await resolve('lib/src/ffi/bindings.dart');
    final bindings = unit.unit.declarations
        .whereType<ClassDeclaration>()
        .singleWhere(
          (declaration) => declaration.name.lexeme == 'OpenTuiBindings',
        );

    const checks = <String, List<String>>{
      'setCursorPosition': <String>[
        "_checkSigned32Abi(x, 'x');",
        "_checkSigned32Abi(y, 'y');",
      ],
      'enableKittyKeyboard': <String>[
        "_checkUnsignedAbi(flags, 0xFF, 'flags');",
      ],
      'addToHitGrid': <String>[
        "_checkSigned32Abi(x, 'x');",
        "(width, 'width')",
        "(id, 'id')",
        '_checkUnsignedAbi(value, 0xFFFFFFFF, name);',
      ],
      'checkHit': <String>[
        "_checkUnsignedAbi(x, 0xFFFFFFFF, 'x');",
        "_checkUnsignedAbi(y, 0xFFFFFFFF, 'y');",
      ],
    };
    for (final entry in checks.entries) {
      final source = _compactSource(
        (_member(bindings, entry.key) as MethodDeclaration).body.toSource(),
      );
      _expectOrderedFragments(source, entry.value);
    }

    final source = File('lib/src/ffi/bindings.dart').readAsStringSync();
    for (final obsolete in const <String>[
      'createTextBuffer',
      'bufferDrawTextBuffer',
      'updateStats',
      'setDebugOverlay',
    ]) {
      expect(source, isNot(contains(obsolete)), reason: obsolete);
    }
  });

  test('Buffer uses canonical u16 colors and u32 attributes', () async {
    final source = File('lib/src/core/buffer.dart').readAsStringSync();
    expect(source, contains('final Uint16List _foregrounds;'));
    expect(source, contains('final Uint16List _backgrounds;'));
    expect(source, contains('final Uint32List _attributes;'));
    expect(source, isNot(contains('final Uint32List chars;')));
    expect(source, isNot(contains('final Uint16List foregrounds;')));
    expect(source, isNot(contains('final Uint16List backgrounds;')));
    expect(source, isNot(contains('final Uint32List attributes;')));
    expect(source, isNot(contains('drawTextBuffer')));
    expect(source, isNot(contains('DirectTextAccess')));

    final unit = await resolve('lib/src/core/buffer.dart');
    final classes = unit.unit.declarations.whereType<ClassDeclaration>();
    final buffer = classes.singleWhere(
      (declaration) => declaration.name.lexeme == 'Buffer',
    );
    final direct = classes.singleWhere(
      (declaration) => declaration.name.lexeme == 'DirectBufferAccess',
    );
    for (final memberName in const <String>[
      'drawText',
      '_setCellCodeWithAlphaBlending',
    ]) {
      expect(
        _compactSource(
          (_member(buffer, memberName) as MethodDeclaration).body.toSource(),
        ),
        contains("_checkUnsignedAbi(attributes, 0xFFFFFFFF, 'attributes');"),
      );
    }
    expect(
      _compactSource(
        (_member(direct, 'setAttributes') as MethodDeclaration).body.toSource(),
      ),
      contains("_checkUnsignedAbi(attr, 0xFFFFFFFF, 'attr');"),
    );

    final bindings = File('lib/src/ffi/bindings.dart').readAsStringSync();
    expect(
      bindings,
      contains("_checkUnsignedAbi(attributes, 0xFFFFFFFF, 'attributes');"),
    );
  });
  test('TuiCanvas is the exact non-constructible paint vocabulary', () async {
    final unit = await resolve('lib/src/painting/tui_canvas.dart');
    final canvas = unit.unit.declarations
        .whereType<ClassDeclaration>()
        .singleWhere((declaration) => declaration.name.lexeme == 'TuiCanvas');
    expect(canvas.abstractKeyword, isNotNull);
    expect(canvas.interfaceKeyword, isNotNull);

    final publicConstructors = <String>{};
    final publicInstanceFields = <String>{};
    final publicStaticMembers = <String>{};
    final publicInstanceMethods = <String>{};
    for (final member in canvas.members) {
      switch (member) {
        case ConstructorDeclaration(:final name):
          final constructorName = name?.lexeme ?? 'new';
          if (!constructorName.startsWith('_')) {
            publicConstructors.add(constructorName);
          }
        case FieldDeclaration(:final fields, :final isStatic):
          for (final variable in fields.variables) {
            final name = variable.name.lexeme;
            if (name.startsWith('_')) continue;
            (isStatic ? publicStaticMembers : publicInstanceFields).add(name);
          }
        case MethodDeclaration(:final name, :final isStatic):
          if (name.lexeme.startsWith('_')) continue;
          (isStatic ? publicStaticMembers : publicInstanceMethods).add(
            name.lexeme,
          );
      }
    }

    expect(publicConstructors, isEmpty);
    expect(publicInstanceFields, isEmpty);
    expect(publicStaticMembers, isEmpty);
    expect(publicInstanceMethods, _canvasMethods);
    expect(
      unit.unit.declarations.whereType<ClassDeclaration>().any(
        (declaration) => declaration.name.lexeme == '_TuiCanvasRecorder',
      ),
      isTrue,
    );
  });

  test(
    'TuiApp has the exact narrow private-constructor facade shape',
    () async {
      final unit = await resolve('lib/src/app/app.dart');
      final app = unit.unit.declarations
          .whereType<ClassDeclaration>()
          .singleWhere((declaration) => declaration.name.lexeme == 'TuiApp');
      expect(app.finalKeyword, isNotNull);

      final constructors = app.members
          .whereType<ConstructorDeclaration>()
          .map((constructor) => constructor.name?.lexeme ?? 'new')
          .toSet();
      expect(constructors, const <String>{'_'});
      expect(
        constructors.every((constructor) => constructor.startsWith('_')),
        isTrue,
      );

      final publicInstanceMembers = <String>{};
      final publicStaticMembers = <String>{};
      for (final member in app.members) {
        switch (member) {
          case FieldDeclaration(:final fields, :final isStatic):
            for (final variable in fields.variables) {
              final name = variable.name.lexeme;
              if (name.startsWith('_')) continue;
              (isStatic ? publicStaticMembers : publicInstanceMembers).add(
                name,
              );
            }
          case MethodDeclaration(:final name, :final isStatic):
            if (name.lexeme.startsWith('_')) continue;
            (isStatic ? publicStaticMembers : publicInstanceMembers).add(
              name.lexeme,
            );
          case ConstructorDeclaration():
            break;
        }
      }
      // Navigator-style tree accessors: a widget ends the app through the
      // scope runTuiApp installs, rather than through a threaded callback.
      expect(publicStaticMembers, const <String>{'of', 'maybeOf', 'exit'});
      expect(publicInstanceMembers, _tuiAppMembers);

      final factory = unit.unit.declarations
          .whereType<FunctionDeclaration>()
          .singleWhere(
            (declaration) =>
                declaration.name.lexeme == 'createTuiAppForTesting',
          );
      final metadata = factory.declaredFragment!.element.metadata;
      expect(metadata.hasInternal, isTrue);
      expect(metadata.hasVisibleForTesting, isTrue);
      final high = (await resolve('lib/noir.dart')).libraryElement;
      expect(
        high.exportNamespace.definedNames2,
        isNot(contains('createTuiAppForTesting')),
      );
    },
  );

  test(
    'closure walk includes inheritance, top-level variables, and aliases',
    () async {
      final unit = await resolve(
        'test/architecture/public_member_seams_test.dart',
      );
      final library = unit.libraryElement;
      final publicType = library.getClass('_ClosureMutationPublic')!;
      final alias = library.typeAliases.singleWhere(
        (element) => element.name == '_ClosureMutationAlias',
      );
      final aliasedVariable = library.topLevelVariables.singleWhere(
        (element) => element.name == '_closureMutationAliasedVariable',
      );
      final available = <Element>{publicType, alias};

      final inheritedMissing = <String>{};
      final inheritedHiddenEdges = <String>{};
      for (final signature in _supportedSignatureTypes(publicType)) {
        final missing = <String>{};
        _collectMissingTypes(signature.type, available, missing);
        inheritedMissing.addAll(missing);
        if (missing.contains('_ClosureMutationHidden')) {
          inheritedHiddenEdges.add(signature.owner);
        }
      }
      expect(inheritedMissing, contains('_ClosureMutationHidden'));
      expect(
        inheritedHiddenEdges,
        containsAll(const <String>{
          'inheritedHidden.return',
          'inheritedHidden.hidden',
          'inheritedField.return',
        }),
      );

      final aliasMissing = <String>{};
      for (final signature in _supportedSignatureTypes(aliasedVariable)) {
        _collectMissingTypes(signature.type, available, aliasMissing);
      }
      expect(aliasMissing, contains('_ClosureMutationHidden'));
      expect(aliasMissing, isNot(contains('_ClosureMutationAlias')));
      expect(_ClosureMutationPublic, isNotNull);
      expect(_closureMutationAliasedVariable, isEmpty);
    },
  );
}

Iterable<({String owner, DartType type})> _supportedSignatureTypes(
  Element element,
) sync* {
  if (element.metadata.hasInternal) return;

  if (element case final TypeParameterizedElement parameterized) {
    for (final parameter in parameterized.typeParameters) {
      final bound = parameter.bound;
      if (bound != null) {
        yield (owner: '${element.name}<${parameter.name}>', type: bound);
      }
    }
  }

  if (element case final TypeAliasElement alias) {
    yield (owner: alias.name ?? '<alias>', type: alias.aliasedType);
  }

  if (element case final FunctionTypedElement function) {
    yield* _executableSignatureTypes(function);
  }

  if (element case final ExtensionElement extension) {
    yield (owner: '${extension.name}.on', type: extension.extendedType);
  }

  if (element case final TopLevelVariableElement variable) {
    yield (owner: variable.name ?? '<variable>', type: variable.type);
  }

  if (element case final InstanceElement instance) {
    for (final field in instance.fields) {
      if (_isSupportedMember(field)) {
        yield (owner: '${instance.name}.${field.name}', type: field.type);
      }
    }
    for (final member in <ExecutableElement>[
      ...instance.getters,
      ...instance.setters,
      ...instance.methods,
      if (instance case final InterfaceElement interface)
        ...interface.constructors,
    ]) {
      if (_isSupportedMember(member)) {
        yield* _executableSignatureTypes(member);
      }
    }

    if (instance case final InterfaceElement interface) {
      for (final member in interface.interfaceMembers.values.toSet()) {
        if (_isSupportedMember(member, includeSynthetic: true)) {
          yield* _executableSignatureTypes(member);
        }
      }
    }
  }
}

Iterable<({String owner, DartType type})> _executableSignatureTypes(
  FunctionTypedElement executable,
) sync* {
  final owner = executable.name ?? '<unnamed>';
  yield (owner: '$owner.return', type: executable.returnType);
  for (final parameter in executable.formalParameters) {
    yield (owner: '$owner.${parameter.name}', type: parameter.type);
  }
  for (final parameter in executable.typeParameters) {
    final bound = parameter.bound;
    if (bound != null) {
      yield (owner: '$owner<${parameter.name}>', type: bound);
    }
  }
}

bool _isSupportedMember(Element element, {bool includeSynthetic = false}) {
  final relatedHasInternal = switch (element) {
    PropertyAccessorElement(:final baseElement, :final variable) =>
      baseElement.metadata.hasInternal ||
          baseElement.variable.metadata.hasInternal ||
          variable.metadata.hasInternal,
    ExecutableElement(:final baseElement) => baseElement.metadata.hasInternal,
    FieldElement(:final baseElement) => baseElement.metadata.hasInternal,
    _ => false,
  };
  return element.isPublic &&
      (includeSynthetic || !element.isSynthetic) &&
      !element.metadata.hasInternal &&
      !relatedHasInternal;
}

void _collectMissingTypes(
  DartType type,
  Set<Element> available,
  Set<String> missing, [
  Set<TypeAliasElement>? activeAliases,
]) {
  final aliases = activeAliases ?? <TypeAliasElement>{};
  final alias = type.alias;
  if (alias != null) {
    if (!_isAvailableTypeElement(alias.element, available)) {
      missing.add(alias.element.name ?? alias.element.displayName);
    }
    if (!aliases.add(alias.element)) return;
    for (final argument in alias.typeArguments) {
      _collectMissingTypes(argument, available, missing, aliases);
    }
    _collectMissingTypes(
      alias.element.aliasedType,
      available,
      missing,
      aliases,
    );
    aliases.remove(alias.element);
    return;
  }

  switch (type) {
    case final InterfaceType interface:
      if (!_isAvailableTypeElement(interface.element, available)) {
        missing.add(interface.element.name ?? interface.element.displayName);
      }
      for (final argument in interface.typeArguments) {
        _collectMissingTypes(argument, available, missing, aliases);
      }
    case final FunctionType function:
      _collectMissingTypes(function.returnType, available, missing, aliases);
      for (final parameter in function.formalParameters) {
        _collectMissingTypes(parameter.type, available, missing, aliases);
      }
      for (final parameter in function.typeParameters) {
        final bound = parameter.bound;
        if (bound != null) {
          _collectMissingTypes(bound, available, missing, aliases);
        }
      }
    case final RecordType record:
      for (final field in <RecordTypeField>[
        ...record.positionalFields,
        ...record.namedFields,
      ]) {
        _collectMissingTypes(field.type, available, missing, aliases);
      }
    case final TypeParameterType parameter:
      _collectMissingTypes(parameter.bound, available, missing, aliases);
    case DynamicType() || InvalidType() || NeverType() || VoidType():
      break;
    default:
      final element = type.element;
      if (element != null && !_isAvailableTypeElement(element, available)) {
        missing.add(element.name ?? element.displayName);
      }
  }
}

bool _isAvailableTypeElement(Element element, Set<Element> available) {
  final library = element.library;
  return library == null || library.isInSdk || available.contains(element);
}

Future<ClassDeclaration> _classDeclaration(
  Future<ResolvedUnitResult> Function(String path) resolve,
  _Owner owner,
) async {
  final result = await resolve(owner.path);
  return result.unit.declarations.whereType<ClassDeclaration>().singleWhere(
    (declaration) => declaration.name.lexeme == owner.name,
  );
}

ClassMember _member(ClassDeclaration declaration, String name) =>
    declaration.members.singleWhere((member) => _memberName(member) == name);

String _memberName(ClassMember member) => switch (member) {
  MethodDeclaration(:final name) => name.lexeme,
  ConstructorDeclaration(:final name) => name?.lexeme ?? 'new',
  _ => '<unsupported:${member.runtimeType}>',
};

Element? _memberElement(ClassMember member) => switch (member) {
  MethodDeclaration(:final declaredFragment) => declaredFragment?.element,
  ConstructorDeclaration(:final declaredFragment) => declaredFragment?.element,
  _ => null,
};

String _compactSource(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

void _expectOrderedFragments(String source, List<String> fragments) {
  var offset = 0;
  for (final fragment in fragments) {
    final next = source.indexOf(fragment, offset);
    expect(next, isNonNegative, reason: fragment);
    offset = next + fragment.length;
  }
}

Iterable<String> _dartFilesUnder(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .map(
      (file) => path
          .relative(file.path, from: Directory.current.path)
          .replaceAll(Platform.pathSeparator, '/'),
    )
    .where((file) => file.endsWith('.dart'));

const _buildOwnerOwner = (
  path: 'lib/src/framework/owner.dart',
  name: 'BuildOwner',
);
const _bufferOwner = (path: 'lib/src/core/buffer.dart', name: 'Buffer');
const _focusAttachmentOwner = (
  path: 'lib/src/framework/focus_manager.dart',
  name: 'FocusAttachment',
);
const _rendererOwner = (path: 'lib/src/core/renderer.dart', name: 'Renderer');
const _renderObjectWidgetOwner = (
  path: 'lib/src/framework/widget.dart',
  name: 'RenderObjectWidget',
);

const Map<_Owner, Set<String>> _internalMembers = <_Owner, Set<String>>{
  (path: 'lib/src/framework/build_context.dart', name: 'BuildContext'): {
    'element',
    'owner',
    'getElementForInheritedWidgetOfExactType',
    'findRenderObject',
    'findAncestorRenderObjectOfType',
    'visitAncestorElements',
    'visitChildElements',
  },
  (path: 'lib/src/framework/widget.dart', name: 'Widget'): {'createElement'},
  (path: 'lib/src/framework/widget.dart', name: 'StatelessWidget'): {
    'createElement',
  },
  (path: 'lib/src/framework/widget.dart', name: 'StatefulWidget'): {
    'createElement',
  },
  (path: 'lib/src/framework/widget.dart', name: 'ProxyWidget'): {
    'createElement',
  },
  (path: 'lib/src/framework/widget.dart', name: 'RenderObjectWidget'): {
    'createElement',
  },
  (
    path: 'lib/src/framework/widget.dart',
    name: 'SingleChildRenderObjectWidget',
  ): {
    'createElement',
  },
  (
    path: 'lib/src/framework/element.dart',
    name: 'MultiChildRenderObjectWidget',
  ): {
    'createElement',
  },
  (path: 'lib/src/widgets/inherited.dart', name: 'InheritedWidget'): {
    'createElement',
  },
  (path: 'lib/src/widgets/row_column.dart', name: 'Flex'): {
    'createElement',
    'createRenderObject',
    'updateRenderObject',
  },
  (path: 'lib/src/widgets/align.dart', name: 'Align'): {
    'createRenderObject',
    'updateRenderObject',
  },
  (path: 'lib/src/widgets/constrained_box.dart', name: 'ConstrainedBox'): {
    'createRenderObject',
    'updateRenderObject',
  },
  (path: 'lib/src/widgets/decorated_box.dart', name: 'DecoratedBox'): {
    'createRenderObject',
    'updateRenderObject',
  },
  (path: 'lib/src/widgets/padding.dart', name: 'Padding'): {
    'createRenderObject',
    'updateRenderObject',
  },
  (path: 'lib/src/widgets/pointer_listener.dart', name: 'PointerListener'): {
    'createRenderObject',
    'updateRenderObject',
  },
  (path: 'lib/src/widgets/rich_text.dart', name: 'RichText'): {
    'createRenderObject',
    'updateRenderObject',
  },
  (path: 'lib/src/widgets/text.dart', name: 'Text'): {
    'createRenderObject',
    'updateRenderObject',
  },
  (path: 'lib/src/widgets/menu_anchor.dart', name: 'MenuAnchor'): {
    'createElement',
  },
  (path: 'lib/src/widgets/modal.dart', name: 'Modal'): {'createElement'},
  (path: 'lib/src/widgets/overlay.dart', name: 'OverlayPortal'): {
    'createElement',
  },
  (path: 'lib/src/framework/focus_manager.dart', name: 'FocusNode'): {
    'attach',
    'detach',
    'isAttachedTo',
  },
  _buildOwnerOwner: {
    'test',
    'isBuilding',
    'beginRebuild',
    'endRebuild',
    'pipelineOwner',
    'hitTestAt',
    'copyToClipboard',
    'scheduleBuild',
    'clearDirty',
    'registerGlobalKey',
    'unregisterGlobalKey',
    'validateGlobalKeyPlacement',
    'deactivateChild',
    'finalizeTree',
  },
  (path: 'lib/src/rendering/object.dart', name: 'RenderObject'): {
    'pipelineOwner',
    'moveChild',
    'attach',
    'didAttach',
  },
  (path: 'lib/src/widgets/scroll_box.dart', name: 'RenderScrollBox'): {
    'didAttach',
  },
  (path: 'lib/src/framework/diagnostics.dart', name: 'WidgetInspectorService'):
      {'rootElement', 'registerRoot', 'unregisterRoot'},
  (path: 'lib/src/framework/focus_manager.dart', name: 'FocusManager'): {
    'nodeForElement',
  },
  _bufferOwner: {
    'invalidate',
    'attributesWithLink',
    'linkForAttributes',
    'acceptsTextCluster',
    'handle',
  },
  _rendererOwner: {'debugCurrentBuffer', 'handle', 'bindings'},
};

const Map<_Owner, Set<String>> _protectedMembers = <_Owner, Set<String>>{
  (path: 'lib/src/rendering/object.dart', name: 'RenderObject'): {
    'moveChild',
    'didAttach',
  },
  (path: 'lib/src/widgets/scroll_box.dart', name: 'RenderScrollBox'): {
    'didAttach',
  },
};

const Set<_Owner> _createElementOwners = <_Owner>{
  (path: 'lib/src/framework/widget.dart', name: 'Widget'),
  (path: 'lib/src/framework/widget.dart', name: 'StatelessWidget'),
  (path: 'lib/src/framework/widget.dart', name: 'StatefulWidget'),
  (path: 'lib/src/framework/widget.dart', name: 'ProxyWidget'),
  (path: 'lib/src/framework/widget.dart', name: 'RenderObjectWidget'),
  (
    path: 'lib/src/framework/widget.dart',
    name: 'SingleChildRenderObjectWidget',
  ),
  (
    path: 'lib/src/framework/element.dart',
    name: 'MultiChildRenderObjectWidget',
  ),
  (path: 'lib/src/widgets/inherited.dart', name: 'InheritedWidget'),
  (path: 'lib/src/widgets/row_column.dart', name: 'Flex'),
  (path: 'lib/src/widgets/stack.dart', name: 'Stack'),
  (path: 'lib/src/widgets/stack.dart', name: 'Positioned'),
  (path: 'lib/src/widgets/menu_anchor.dart', name: 'MenuAnchor'),
  (path: 'lib/src/widgets/modal.dart', name: 'Modal'),
  (path: 'lib/src/widgets/overlay.dart', name: 'OverlayPortal'),
};

const Set<_Owner> _builtInRenderWidgetOwners = <_Owner>{
  (path: 'lib/src/widgets/align.dart', name: 'Align'),
  (path: 'lib/src/widgets/ascii_font.dart', name: 'AsciiFont'),
  (path: 'lib/src/widgets/constrained_box.dart', name: 'ConstrainedBox'),
  (path: 'lib/src/widgets/decorated_box.dart', name: 'DecoratedBox'),
  (path: 'lib/src/widgets/padding.dart', name: 'Padding'),
  (path: 'lib/src/widgets/pointer_listener.dart', name: 'PointerListener'),
  (path: 'lib/src/widgets/rich_text.dart', name: 'RichText'),
  (path: 'lib/src/widgets/text.dart', name: 'Text'),
  (path: 'lib/src/widgets/row_column.dart', name: 'Flex'),
  (path: 'lib/src/widgets/stack.dart', name: 'Stack'),
  (path: 'lib/src/widgets/wrap.dart', name: 'Wrap'),
};

const Set<_Owner> _privateBridgeOwners = <_Owner>{
  (path: 'lib/src/widgets/flexible.dart', name: '_FlexibleNode'),
  (path: 'lib/src/widgets/input.dart', name: '_TextInputLeaf'),
  (path: 'lib/src/widgets/text_area.dart', name: '_TextAreaLeaf'),
  (path: 'lib/src/widgets/select.dart', name: '_SelectLeaf'),
  (
    path: 'lib/src/widgets/scroll_box.dart',
    name: '_ScrollBoxRenderObjectWidget',
  ),
};

const Set<String> _canvasMethods = <String>{
  'save',
  'restore',
  'clipRect',
  'fillRect',
  'drawText',
  'drawBox',
  'setCell',
  'drawTextLayout',
  'drawImage',
};

const Set<String> _tuiAppMembers = <String>{
  'isHeadless',
  'onKey',
  'onMouse',
  'onPaste',
  'enableMouse',
  'disableMouse',
  'enableKittyKeyboard',
  'disableKittyKeyboard',
  'reassemble',
  'requestExit',
  'dispose',
};

final class _ClosureMutationHidden {}

class _ClosureMutationBase {
  final _ClosureMutationHidden inheritedField = _ClosureMutationHidden();

  _ClosureMutationHidden inheritedHidden(_ClosureMutationHidden hidden) =>
      hidden;
}

mixin _ClosureMutationMixin {}

abstract interface class _ClosureMutationInterface {}

abstract class _ClosureMutationPublic extends _ClosureMutationBase
    with _ClosureMutationMixin
    implements _ClosureMutationInterface {}

typedef _ClosureMutationAlias = List<_ClosureMutationHidden>;

final _ClosureMutationAlias _closureMutationAliasedVariable =
    <_ClosureMutationHidden>[];
