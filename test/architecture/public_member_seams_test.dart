import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
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
    'only the exact built-in high render widgets declare lifecycle hooks',
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

  test('TextBuffer exposes truthful supported and raw seams', () async {
    Future<ClassDeclaration> type(String file, String name) =>
        _classDeclaration(resolve, (path: 'lib/src/$file', name: name));
    final textBuffer = await type('core/text_buffer.dart', 'TextBuffer');
    final factory = _member(textBuffer, 'create') as ConstructorDeclaration;
    expect(factory.factoryKeyword, isNotNull);
    expect(
      _compactSource(factory.parameters.toSource()),
      '({WidthMethod widthMethod = WidthMethod.unicode})',
      reason: 'supported creation must be named-only with one width method',
    );
    final factoryDoc = _memberDoc(factory).toLowerCase();
    for (final fact in const <String>['empty', 'grows']) {
      expect(factoryDoc, contains(fact), reason: fact);
    }
    expect(
      factoryDoc,
      isNot(matches(_creationCapacityPromise)),
      reason: 'creation must not promise requested allocation or capacity',
    );
    final lengthDoc = _memberDoc(_member(textBuffer, 'length')).toLowerCase();
    for (final fact in const <String>['current', 'logical', 'cells']) {
      expect(lengthDoc, contains(fact), reason: fact);
    }
    expect(lengthDoc, isNot(matches(RegExp(r'\ballocated\b|\bcapacity\b'))));
    final resetDoc = _memberDoc(_member(textBuffer, 'reset')).toLowerCase();
    expect(resetDoc, contains('clears'));
    expect(resetDoc, contains('zero'));
    final statements = (factory.body as BlockFunctionBody).block.statements;
    expect(statements, hasLength(4));
    expect(
      _compactSource(statements[1].toSource()),
      'final ptr = bindings.createTextBuffer(0, widthMethod.value);',
      reason: 'supported creation owns the literal-zero ABI placeholder',
    );
    final nullCheck = statements[2] as IfStatement;
    expect(_compactSource(nullCheck.expression.toSource()), 'ptr == nullptr');
    expect(
      _compactSource(nullCheck.thenStatement.toSource()),
      "{throw StateError('Failed to create TextBuffer');}",
      reason: 'nullptr must become StateError before ownership',
    );
    expect(
      _compactSource(statements[3].toSource()),
      'return TextBuffer._(bindings, ptr);',
    );
    final ownershipConstructor =
        _member(textBuffer, '_') as ConstructorDeclaration;
    expect(ownershipConstructor.body.toSource(), contains('_finalizer.attach'));
    final bindings = await type('ffi/bindings.dart', 'OpenTuiBindings');
    final raw = _member(bindings, 'createTextBuffer') as MethodDeclaration;
    expect(
      _compactSource(raw.parameters!.toSource()),
      '(int abiLength, int widthMethod)',
      reason: 'the guarded raw tier must retain both required ABI integers',
    );
    expect(
      _compactSource(raw.body.toSource()),
      contains('_generated.createTextBuffer(abiLength, widthMethod)'),
      reason: 'raw arguments must forward once in declaration order',
    );
    final rawDoc = _memberDoc(raw).toLowerCase();
    for (final fact in <String>[
      'abi 2',
      'ignored by the pinned native implementation',
      'ordinary raw callers pass zero',
      'second value',
      'native width-method identifier',
      'may return `nullptr`',
      'supported `textbuffer` wrapper maps null',
      '[stateerror]',
    ]) {
      expect(rawDoc, contains(fact), reason: fact);
    }
    expect(
      rawDoc,
      isNot(matches(_rawFalseContract)),
      reason: 'raw docs cannot promise capacity or blanket failure throws',
    );
    final write = _member(textBuffer, 'writeChunk') as MethodDeclaration;
    final supportedDoc = _memberDoc(write).toLowerCase();
    expect(supportedDoc, contains('appends'));
    expect(supportedDoc, contains('unsigned 8-bit'));
    expect(supportedDoc, contains('unsigned 32-bit'));
    expect(
      supportedDoc,
      isNot(
        matches(RegExp(r'\breturn\w*\b|\bcount\b|\bresult\b|\bencoding\b')),
      ),
    );
    expect(
      _compactSource(write.body.toSource()),
      "{_checkNotDisposed(); _checkUnsignedAbi(attributes, 0xFF, 'attributes'); "
      '_utf8Scratch.update(text, maxBytes: 0xFFFFFFFF); '
      '_lineMetadataStale = true; '
      '_bindings.textBufferWriteUtf8Chunk(_ptr, _utf8Scratch.pointer, '
      '_utf8Scratch.length, fg, bg, attributes);}',
    );
    expect(write.returnType!.toSource(), 'void');
    expect(
      _compactSource(write.parameters!.toSource()),
      '(String text, Color fg, Color bg, int attributes)',
    );
    for (final rawName in const <String>[
      'textBufferWriteChunk',
      'textBufferWriteUtf8Chunk',
    ]) {
      final raw = _member(bindings, rawName) as MethodDeclaration;
      expect(raw.returnType!.toSource(), 'int', reason: rawName);
      final doc = _memberDoc(raw).toLowerCase();
      for (final fact in const <String>[
        'opaque native write result',
        'dart-side marshalling or invocation exceptions are mapped to [ffiexception]',
        'native write failure may be represented only inside the opaque result, including zero',
      ]) {
        expect(doc, contains(fact), reason: '$rawName: $fact');
      }
      expect(doc, isNot(matches(_rawWriteFalsePromise)), reason: rawName);
      expect(
        _compactSource(raw.body.toSource()),
        matches(_directRawWriteReturn),
      );
    }

    final setCell = _member(textBuffer, 'setCell') as MethodDeclaration;
    expect(
      _compactSource(setCell.parameters!.toSource()),
      '(int index, String scalar, Color fg, Color bg, int attributes)',
    );
    final setCellDoc = _memberDoc(setCell).toLowerCase();
    for (final fact
        in 'one zero-based logical cell|extends with spaces|exactly one well-formed unicode scalar|one raw cell word|does not perform grapheme clustering|display-width expansion|newline retains native line behavior'
            .split('|')) {
      expect(setCellDoc, contains(fact), reason: fact);
    }
    final setCellStatements =
        (setCell.body as BlockFunctionBody).block.statements;
    expect(setCellStatements.map((statement) => _compactSource(statement.toSource())), <
      String
    >[
      '_checkNotDisposed();',
      "if (index < 0 || index > 0xFFFFFFFF) {throw RangeError.range(index, 0, 0xFFFFFFFF, 'index');}",
      "if (attributes < 0 || attributes > 0xFFFF) {throw RangeError.range(attributes, 0, 0xFFFF, 'attributes');}",
      'final scalarValues = scalar.runes.toList(growable: false);',
      'final scalarValue = scalarValues.length == 1 ? scalarValues.single : -1;',
      "if (scalarValues.length != 1 || (scalarValue >= 0xD800 && scalarValue <= 0xDFFF) || String.fromCharCode(scalarValue) != scalar) {throw ArgumentError.value(scalar, 'scalar', 'must contain exactly one well-formed Unicode scalar');}",
      '_lineMetadataStale = true;',
      '_bindings.textBufferSetCell(_ptr, index, scalarValue, fg, bg, attributes);',
    ]);

    final direct = await type('core/text_buffer.dart', 'DirectTextAccess');
    final directDoc = _compactSource(
      (direct.declaredFragment!.element.documentationComment ?? '').replaceAll(
        '///',
        '',
      ),
    ).toLowerCase();
    for (final fact
        in 'native encoded cell words|not a unicode string or a uniformly decodable code-point array|top bits `00` identify a direct scalar word|top bits `10` identify a packed grapheme-start word|right extent and an opaque 26-bit pool identity|top bits `11` identify a continuation word|left and right extents and the same opaque identity|process-global native grapheme pool|cannot independently recover grapheme text|non-empty views are native-owned, read-only|immediate inspection|next textbuffer mutation, reset, or disposal|zero, getdirectaccess returns dart-owned empty typed lists'
            .split('|')) {
      expect(directDoc, contains(fact), reason: fact);
    }
    final directConstructor = _member(direct, 'new') as ConstructorDeclaration;
    expect(
      _compactSource(directConstructor.parameters.toSource()),
      '({required this.encodedCells, required this.foregrounds, required this.backgrounds, required this.attributes, required this.length})',
    );
    final directFields = direct.members
        .whereType<FieldDeclaration>()
        .expand((field) => field.fields.variables)
        .map((variable) => variable.name.lexeme)
        .toSet();
    expect(directFields, contains('encodedCells'));
    expect(directFields, isNot(contains('chars')));
    expect(
      direct.members.whereType<MethodDeclaration>().map(
        (method) => method.name.lexeme,
      ),
      isNot(contains('getChar')),
    );

    final selection = _member(textBuffer, 'setSelection') as MethodDeclaration;
    final selectionDoc = _memberDoc(selection).toLowerCase();
    for (final fact
        in 'half-open native-cell range `[start, end)`|[start] is included|[end] is excluded|unsigned 32-bit|greater than or equal to [start]|may exceed the current [length]'
            .split('|')) {
      expect(selectionDoc, contains(fact), reason: fact);
    }
    final selectionSource = _compactSource(selection.body.toSource());
    _expectOrderedFragments(
      selectionSource,
      "_checkNotDisposed();|_checkUnsignedAbi(start, 0xFFFFFFFF, 'start');|_checkUnsignedAbi(end, 0xFFFFFFFF, 'end');|if (start > end)|throw ArgumentError.value(end, 'end', 'must be greater than or equal to start');|_bindings.textBufferSetSelection("
          .split('|'),
    );
    expect(selectionSource, isNot(contains('.length')));

    const rawFacts = <String, String>{
      'createTextBuffer':
          'abi 2|two required integers|first slot|ignored|ordinary raw callers pass zero|second value|width-method identifier|may return `nullptr`|supported `textbuffer` wrapper maps null to [stateerror]|unsigned 32-bit|unsigned 8-bit|pre-invocation [rangeerror]',
      'destroyTextBuffer':
          'status-free `void`|native failure is not reported separately',
      'textBufferGetLength':
          'native logical cell count|no native failure status',
      'textBufferSetCell':
          '[charcode] is one raw cell word|native allocation or update errors are swallowed|not observable|unsigned 32-bit|unsigned 16-bit|pre-invocation [rangeerror]',
      'textBufferWriteChunk':
          'opaque native write result|native write failure may be represented only inside the opaque result, including zero|unsigned 8-bit|unsigned 32-bit|pre-invocation [rangeerror]',
      'textBufferWriteUtf8Chunk':
          'opaque native write result|native write failure may be represented only inside the opaque result, including zero|caller owns persistent bytes for the call|unsigned 32-bit|unsigned 8-bit|pre-invocation [rangeerror]',
      'textBufferFinalizeLineInfo':
          'status-free `void`|no native failure status',
      'textBufferGetLineCount':
          'current native line count|cache-construction failure has no separate status',
      'textBufferGetLineStartsPtr':
          'native-owned pointer|reported line count|zero count means no element may be dereferenced|no nullable empty or failure sentinel|incomplete or empty data|no status',
      'textBufferGetLineWidthsPtr':
          'native-owned pointer|reported line count|zero count means no element may be dereferenced|no nullable empty or failure sentinel|incomplete or empty data|no status',
      'textBufferReset': 'status-free `void`|no native failure status',
      'textBufferSetSelection':
          'half-open native-cell range `[start, end)`|[start] is included|[end] is excluded|status-free `void`|no native failure status|unsigned 32-bit|pre-invocation [rangeerror]|reversed, equal, or beyond the current length',
      'textBufferResetSelection': 'status-free `void`|no native failure status',
      'bufferDrawTextBuffer':
          'pinned export swallows native drawing errors|not observable|[clipy] must fit signed 32-bit values|[clipheight] must fit unsigned 32-bit values|regardless of [hascliprect]|pre-invocation [rangeerror]',
      'textBufferGetCharPtr':
          'native-owned pointer to encoded cell words|logical cell count|no nullable empty or failure sentinel|incomplete or empty data|no status',
      'textBufferGetFgPtr':
          'native-owned rgba cache pointer|count-bounded|no nullable empty or failure sentinel|possibly partial|no status',
      'textBufferGetBgPtr':
          'native-owned rgba cache pointer|count-bounded|no nullable empty or failure sentinel|possibly partial|no status',
      'textBufferGetAttributesPtr':
          'native-owned packed-attribute cache pointer|count-bounded|no nullable empty or failure sentinel|possibly partial|no status',
    };
    final rawTextBufferMethods = <String, MethodDeclaration>{
      for (final method in bindings.members.whereType<MethodDeclaration>())
        if (method.name.lexeme.startsWith('textBuffer') ||
            const {
              'createTextBuffer',
              'destroyTextBuffer',
              'bufferDrawTextBuffer',
            }.contains(method.name.lexeme))
          method.name.lexeme: method,
    };
    expect(rawTextBufferMethods.keys, unorderedEquals(rawFacts.keys));
    for (final entry in rawFacts.entries) {
      final doc = _memberDoc(rawTextBufferMethods[entry.key]!).toLowerCase();
      expect(
        doc,
        contains(
          'dart-side marshalling or invocation exceptions are mapped to [ffiexception]',
        ),
        reason: '${entry.key}: Dart exception boundary',
      );
      for (final fact in entry.value.split('|')) {
        expect(doc, contains(fact), reason: '${entry.key}: $fact');
      }
      expect(
        doc,
        isNot(matches(_rawTextBufferFalseOutcome)),
        reason: '${entry.key}: false blanket native outcome',
      );
    }
    final consumer = parseString(
      content: File(
        'test/fixtures/source_package_consumer/bin/low_level_multi_child.dart',
      ).readAsStringSync(),
    ).unit;
    final function = consumer.declarations
        .whereType<FunctionDeclaration>()
        .single;
    final consumerBody = function.functionExpression.body as BlockFunctionBody;
    const consumerCall =
        "textBuffer.writeChunk('contract', Color.white, Color.black, 0);";
    final calls = consumerBody.block.statements
        .whereType<ExpressionStatement>()
        .where(
          (statement) => _compactSource(statement.toSource()) == consumerCall,
        );
    expect(calls, hasLength(1));
    expect(
      consumerBody.block.statements.map(
        (statement) => _compactSource(statement.toSource()),
      ),
      containsAll(<String>[
        "textBuffer.setCell(0, 'N', Color.white, Color.black, 0);",
        'final encodedCell = textBuffer.getDirectAccess().encodedCells[0];',
      ]),
    );
  });

  test('TextBuffer fixed-width inputs fail closed before mutation and FFI', () async {
    final textBuffer = await _classDeclaration(resolve, const (
      path: 'lib/src/core/text_buffer.dart',
      name: 'TextBuffer',
    ));
    MethodDeclaration textBufferMethod(String name) =>
        _member(textBuffer, name) as MethodDeclaration;
    final snapshot = textBufferMethod('compositingSnapshotFromCapturedHandle');
    expect(
      _compactSource(snapshot.parameters!.toSource()),
      '(Pointer<TextBufferHandle> capturedHandle)',
    );
    expect(
      _compactSource(snapshot.returnType!.toSource()),
      '({DirectTextAccess access, List<int> lineStarts, List<int> lineWidths})',
    );
    const memberBodies = <String, String>{
      'compositingSnapshotFromCapturedHandle':
          '{final access = _directAccessFromHandle(capturedHandle); final lineInfo = _lineInfoFromHandle(capturedHandle); return (access: access, lineStarts: lineInfo.starts, lineWidths: lineInfo.widths);}',
      'getDirectAccess':
          '{_checkNotDisposed(); return _directAccessFromHandle(_ptr);}',
      'lineInfo': '{_checkNotDisposed(); return _lineInfoFromHandle(_ptr);}',
      'finalizeLineInfo':
          '{_checkNotDisposed(); _bindings.textBufferFinalizeLineInfo(_ptr); _lineMetadataStale = false;}',
      'reset':
          '{_checkNotDisposed(); _bindings.textBufferReset(_ptr); _lineMetadataStale = false;}',
      'lineCount':
          '{_checkNotDisposed(); _checkLineMetadataFinalized(); return _bindings.textBufferGetLineCount(_ptr);}',
      '_readLineMetadata':
          '{final view = ptr.asTypedList(count); return List<int>.unmodifiable(List<int>.generate(count, (i) => view[i]));}',
    };
    for (final entry in memberBodies.entries) {
      expect(
        _compactSource(textBufferMethod(entry.key).body.toSource()),
        entry.value,
      );
    }
    final storage = await _classDeclaration(resolve, const (
      path: 'lib/src/foundation/persistent_utf8_text.dart',
      name: 'PersistentUtf8Text',
    ));
    final update = _member(storage, 'update') as MethodDeclaration;
    final updateSource = _compactSource(update.body.toSource());
    expect('utf8.encode(text)'.allMatches(updateSource), hasLength(1));
    _expectOrderedFragments(
      updateSource,
      "if (_disposed) throw StateError('PersistentUtf8Text is disposed');|final bytes = utf8.encode(text);|if (maxBytes != null && bytes.length > maxBytes)|throw RangeError.range(bytes.length, 0, maxBytes, 'text', 'encoded UTF-8 byte length exceeds maxBytes');|if (_pointer == nullptr || bytes.length > _capacity)|_length = bytes.length;"
          .split('|'),
    );

    final bufferUnit = await resolve('lib/src/core/buffer.dart');
    final bufferSource = File('lib/src/core/buffer.dart').readAsStringSync();
    expect(bufferSource, isNot(contains('_bindings.textBufferGet')));
    final textBufferSource = File(
      'lib/src/core/text_buffer.dart',
    ).readAsStringSync();
    expect(textBufferSource, isNot(contains('_scanLineInfo')));
    expect(textBufferSource, isNot(contains('fallbackAccess')));
    final drawValidator = bufferUnit.unit.declarations
        .whereType<FunctionDeclaration>()
        .singleWhere(
          (declaration) =>
              declaration.name.lexeme == '_validateTextBufferDrawArguments',
        );
    final validatorSource = _compactSource(
      drawValidator.functionExpression.body.toSource(),
    );
    _expectOrderedFragments(
      validatorSource,
      "destination._checkValid();|final textBufferHandle = textBuffer.handle;|_checkSigned32Abi(x, 'x');|_checkSigned32Abi(y, 'y');|if (clipX != null) _checkSigned32Abi(clipX, 'clipX');|if (clipY != null) _checkSigned32Abi(clipY, 'clipY');|if (clipWidth != null)|_checkUnsignedAbi(clipWidth, 0xFFFFFFFF, 'clipWidth');|if (clipHeight != null)|_checkUnsignedAbi(clipHeight, 0xFFFFFFFF, 'clipHeight');|final hasClipRect = clipX != null && clipY != null && clipWidth != null && clipHeight != null;"
          .split('|'),
    );
    for (final className in const ['Buffer', '_ClippedBufferView']) {
      final owner = bufferUnit.unit.declarations
          .whereType<ClassDeclaration>()
          .singleWhere((declaration) => declaration.name.lexeme == className);
      final draw = _member(owner, 'drawTextBuffer') as MethodDeclaration;
      final drawDoc = _memberDoc(draw).toLowerCase();
      expect(drawDoc, matches(RegExp('(?<!un)signed 32-bit')));
      expect(drawDoc, contains('unsigned 32-bit'));
      final source = _compactSource(draw.body.toSource());
      expect(source, contains('_validateTextBufferDrawArguments('));
      expect(source, isNot(contains('textBuffer.handle')));
      expect(source, contains('validation.textBufferHandle'));
      expect(
        'compositingSnapshotFromCapturedHandle'.allMatches(source),
        hasLength(className == 'Buffer' ? 0 : 1),
      );
    }

    final bindings = await _classDeclaration(resolve, const (
      path: 'lib/src/ffi/bindings.dart',
      name: 'OpenTuiBindings',
    ));
    const rawChecks = <String, String>{
      'createTextBuffer':
          "_checkUnsignedAbi(abiLength, 0xFFFFFFFF, 'abiLength');|_checkUnsignedAbi(widthMethod, 0xFF, 'widthMethod');|return _guard(",
      'textBufferSetCell':
          "_checkUnsignedAbi(index, 0xFFFFFFFF, 'index');|_checkUnsignedAbi(charCode, 0xFFFFFFFF, 'charCode');|_checkUnsignedAbi(attributes, 0xFFFF, 'attributes');|_guardAlloc(",
      'textBufferWriteChunk':
          "_checkUnsignedAbi(attributes, 0xFF, 'attributes');|final bytes = convert.utf8.encode(text);|_checkUnsignedAbi(bytes.length, 0xFFFFFFFF, 'text');|return _guardAlloc(",
      'textBufferWriteUtf8Chunk':
          "_checkUnsignedAbi(textLen, 0xFFFFFFFF, 'textLen');|_checkUnsignedAbi(attributes, 0xFF, 'attributes');|return _guardAlloc(",
      'textBufferSetSelection':
          "_checkUnsignedAbi(start, 0xFFFFFFFF, 'start');|_checkUnsignedAbi(end, 0xFFFFFFFF, 'end');|_guardAlloc(",
      'bufferDrawTextBuffer':
          "_checkSigned32Abi(x, 'x');|_checkSigned32Abi(y, 'y');|_checkSigned32Abi(clipX, 'clipX');|_checkSigned32Abi(clipY, 'clipY');|_checkUnsignedAbi(clipWidth, 0xFFFFFFFF, 'clipWidth');|_checkUnsignedAbi(clipHeight, 0xFFFFFFFF, 'clipHeight');|_guard(",
    };
    for (final entry in rawChecks.entries) {
      final method = _member(bindings, entry.key) as MethodDeclaration;
      final source = _compactSource(method.body.toSource());
      _expectOrderedFragments(source, entry.value.split('|'));
      if (entry.key == 'textBufferSetSelection') {
        expect(source, isNot(contains('start > end')));
      }
      if (entry.key == 'textBufferWriteChunk') {
        expect('convert.utf8.encode(text)'.allMatches(source), hasLength(1));
      }
    }
  });

  test('Buffer-family fixed-width inputs fail closed before clip drop and FFI', () async {
    final bufferUnit = await resolve('lib/src/core/buffer.dart');
    // Both seam files must reject out-of-domain values, never mask them.
    expect(
      File('lib/src/core/buffer.dart').readAsStringSync(),
      isNot(contains('& 0xFF')),
    );
    expect(
      File('lib/src/ffi/bindings.dart').readAsStringSync(),
      isNot(contains('& 0xFF')),
    );

    ClassDeclaration bufferClass(String name) => bufferUnit.unit.declarations
        .whereType<ClassDeclaration>()
        .singleWhere((declaration) => declaration.name.lexeme == name);
    final buffer = bufferClass('Buffer');
    final clipped = bufferClass('_ClippedBufferView');
    const supportedBodies = <String, String>{
      'drawText':
          "_checkValid();|_checkUnsignedAbi(x, 0xFFFFFFFF, 'x');|_checkUnsignedAbi(y, 0xFFFFFFFF, 'y');|_checkUnsignedAbi(attributes, 0xFF, 'attributes');|_bindings.bufferDrawText(",
      'fillRect':
          "_checkValid();|_checkUnsignedAbi(x, 0xFFFFFFFF, 'x');|_checkUnsignedAbi(y, 0xFFFFFFFF, 'y');|_checkUnsignedAbi(width, 0xFFFFFFFF, 'width');|_checkUnsignedAbi(height, 0xFFFFFFFF, 'height');|_bindings.bufferFillRect(",
      'drawBox':
          "_checkValid();|_checkSigned32Abi(x, 'x');|_checkSigned32Abi(y, 'y');|_checkUnsignedAbi(width, 0xFFFFFFFF, 'width');|_checkUnsignedAbi(height, 0xFFFFFFFF, 'height');|_bindings.bufferDrawBox(",
      'setCellWithAlphaBlending':
          "_checkValid();|if (char.isEmpty) throw ArgumentError('Character cannot be empty');|_setCellCodeWithAlphaBlending(",
      '_setCellCodeWithAlphaBlending':
          "_checkValid();|if (x < 0 || x >= width || y < 0 || y >= height)|_checkUnsignedAbi(attributes, 0xFF, 'attributes');|_bindings.bufferSetCellWithAlphaBlending(",
      'drawFrameBuffer':
          "_checkValid();|sourceBuffer._checkValid();|_checkUnsignedAbi(srcX, 0xFFFFFFFF, 'srcX');|_checkUnsignedAbi(srcY, 0xFFFFFFFF, 'srcY');|_checkUnsignedAbi(srcWidth, 0xFFFFFFFF, 'srcWidth');|_checkUnsignedAbi(srcHeight, 0xFFFFFFFF, 'srcHeight');|_checkSigned32Abi(destX, 'destX');|_checkSigned32Abi(destY, 'destY');|_bindings.drawFrameBuffer(",
      'resize':
          "_checkValid();|_checkUnsignedAbi(newWidth, 0xFFFFFFFF, 'newWidth');|_checkUnsignedAbi(newHeight, 0xFFFFFFFF, 'newHeight');|if (newWidth <= 0 || newHeight <= 0)|_bindings.bufferResize(",
    };
    for (final entry in supportedBodies.entries) {
      final method = _member(buffer, entry.key) as MethodDeclaration;
      _expectOrderedFragments(
        _compactSource(method.body.toSource()),
        entry.value.split('|'),
      );
    }
    final directAccess = bufferClass('DirectBufferAccess');
    final setAttributes =
        _member(directAccess, 'setAttributes') as MethodDeclaration;
    _expectOrderedFragments(_compactSource(setAttributes.body.toSource()), [
      'final index = _getIndex(x, y);',
      "_checkUnsignedAbi(attr, 0xFF, 'attr');",
      'attributes[index] = attr;',
    ]);
    const clippedBodies = <String, String>{
      'setCell':
          "_checkValid();|_checkUnsignedAbi(attributes, 0xFF, 'attributes');|if (!_inClip(x, y)) return;|super.setCell(",
      'setCellWithAlphaBlending':
          "_checkValid();|_checkUnsignedAbi(attributes, 0xFF, 'attributes');|if (!_inClip(x, y)) return;|super.setCellWithAlphaBlending(",
      'drawText':
          "_checkValid();|_checkUnsignedAbi(attributes, 0xFF, 'attributes');|if (y < clipY || y >= clipY + clipHeight) return;|super.drawText(",
      'fillRect':
          '_checkValid();|if (x0 >= x1 || y0 >= y1) return;|super.fillRect(',
    };
    for (final entry in clippedBodies.entries) {
      final method = _member(clipped, entry.key) as MethodDeclaration;
      _expectOrderedFragments(
        _compactSource(method.body.toSource()),
        entry.value.split('|'),
      );
    }
    final viewDoc = _compactSource(
      (clipped.declaredFragment!.element.documentationComment ?? '').replaceAll(
        '///',
        '',
      ),
    ).toLowerCase();
    for (final fact in const <String>[
      'signed logical space',
      'clip silently',
      'validated even for calls the clip rectangle drops',
    ]) {
      expect(viewDoc, contains(fact), reason: fact);
    }
    final seam = _member(clipped, '_setTextBufferCell') as MethodDeclaration;
    // The compositing seam must forward to the shared funnel unchanged.
    expect(
      _compactSource(seam.body.toSource()),
      '{super._setCellCodeWithAlphaBlending(x, y, charCode, fg, bg, attributes);}',
    );
    final seamDoc = _memberDoc(seam).toLowerCase();
    for (final fact in const <String>[
      'shared supported-tier funnel',
      'unsigned 8-bit attribute check owns rejection',
    ]) {
      expect(seamDoc, contains(fact), reason: fact);
    }
    final copyDoc = _memberDoc(
      _member(clipped, '_copyTextBufferCells'),
    ).toLowerCase();
    for (final fact in const <String>[
      'native `u16` words',
      'unsigned 8-bit cell domain',
      'caps attributes at 0xff',
      'attr_mask',
      'use_default_*',
      'null color pointers, which this package never passes',
      'no mask is applied',
      '[rangeerror]',
    ]) {
      expect(copyDoc, contains(fact), reason: fact);
    }

    final bindings = await _classDeclaration(resolve, const (
      path: 'lib/src/ffi/bindings.dart',
      name: 'OpenTuiBindings',
    ));
    const rawBodies = <String, String>{
      'bufferDrawText':
          "_checkUnsignedAbi(x, 0xFFFFFFFF, 'x');|_checkUnsignedAbi(y, 0xFFFFFFFF, 'y');|_checkUnsignedAbi(attributes, 0xFF, 'attributes');|_guardAlloc(",
      'bufferFillRect':
          "_checkUnsignedAbi(x, 0xFFFFFFFF, 'x');|_checkUnsignedAbi(y, 0xFFFFFFFF, 'y');|_checkUnsignedAbi(width, 0xFFFFFFFF, 'width');|_checkUnsignedAbi(height, 0xFFFFFFFF, 'height');|_guardAlloc(",
      'bufferDrawBox':
          "_checkSigned32Abi(x, 'x');|_checkSigned32Abi(y, 'y');|_checkUnsignedAbi(width, 0xFFFFFFFF, 'width');|_checkUnsignedAbi(height, 0xFFFFFFFF, 'height');|for (final borderChar in borderChars)|_checkUnsignedAbi(borderChar, 0xFFFFFFFF, 'borderChars');|final titleBytes = convert.utf8.encode(options.title ?? '');|_checkUnsignedAbi(titleLen, 0xFFFFFFFF, 'title');|_guardAlloc(",
      'bufferSetCellWithAlphaBlending':
          "_checkUnsignedAbi(x, 0xFFFFFFFF, 'x');|_checkUnsignedAbi(y, 0xFFFFFFFF, 'y');|_checkUnsignedAbi(charCode, 0xFFFFFFFF, 'charCode');|_checkUnsignedAbi(attributes, 0xFF, 'attributes');|_guardAlloc(",
      'drawFrameBuffer':
          "_checkSigned32Abi(destX, 'destX');|_checkSigned32Abi(destY, 'destY');|_checkUnsignedAbi(sourceX, 0xFFFFFFFF, 'sourceX');|_checkUnsignedAbi(sourceY, 0xFFFFFFFF, 'sourceY');|_checkUnsignedAbi(sourceWidth, 0xFFFFFFFF, 'sourceWidth');|_checkUnsignedAbi(sourceHeight, 0xFFFFFFFF, 'sourceHeight');|_guard(",
      'bufferResize':
          "_checkUnsignedAbi(width, 0xFFFFFFFF, 'width');|_checkUnsignedAbi(height, 0xFFFFFFFF, 'height');|_guard(",
    };
    const rawFacts = <String, String>{
      'bufferDrawText':
          'swallows native text-drawing errors|not observable|crosses as a native `usize`|unsigned 32-bit|unsigned 8-bit|pre-invocation [rangeerror]',
      'bufferFillRect':
          'swallows native fill errors|not observable|unsigned 32-bit|pre-invocation [rangeerror]',
      'bufferDrawBox':
          'swallows native box-drawing errors|not observable|must fit signed 32-bit values|each selected border character|encoded title byte length|unsigned 32-bit|at most 0x7f by construction|crosses unchecked|pre-invocation [rangeerror]',
      'bufferSetCellWithAlphaBlending':
          'swallows native cell-update errors|not observable|unsigned 32-bit|unsigned 8-bit|pre-invocation [rangeerror]',
      'drawFrameBuffer':
          'zero source coordinate or extent crosses as native null|full-extent default|status-free `void`|no native failure status|must fit signed 32-bit values|unsigned 32-bit|pre-invocation [rangeerror]',
      'bufferResize':
          'swallows native resize errors|not observable|unsigned 32-bit|pre-invocation [rangeerror]|raw zero dimensions forward unchanged|positive-dimensions rule',
    };
    for (final entry in rawBodies.entries) {
      final method = _member(bindings, entry.key) as MethodDeclaration;
      final source = _compactSource(method.body.toSource());
      _expectOrderedFragments(source, entry.value.split('|'));
      if (entry.key == 'bufferDrawBox') {
        // The box title must be encoded exactly once, pre-guard.
        expect('utf8.encode'.allMatches(source), hasLength(1));
      }
      final doc = _memberDoc(method).toLowerCase();
      expect(
        doc,
        contains(
          'dart-side marshalling or invocation exceptions are mapped to [ffiexception]',
        ),
        reason: '${entry.key}: Dart exception boundary',
      );
      for (final fact in rawFacts[entry.key]!.split('|')) {
        expect(doc, contains(fact), reason: '${entry.key}: $fact');
      }
      expect(
        doc,
        isNot(matches(_rawTextBufferFalseOutcome)),
        reason: '${entry.key}: false blanket native outcome',
      );
    }
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
      expect(publicStaticMembers, isEmpty);
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

String _memberDoc(ClassMember member) => _compactSource(
  (_memberElement(member)?.documentationComment ?? '').replaceAll('///', ''),
);

String _compactSource(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

void _expectOrderedFragments(String source, List<String> fragments) {
  var offset = 0;
  for (final fragment in fragments) {
    final next = source.indexOf(fragment, offset);
    expect(next, isNonNegative, reason: fragment);
    offset = next + fragment.length;
  }
}

final _creationCapacityPromise = RegExp(
  r'\bat least\b|\brequested length\b|\bcapacity\b|\ballocat(?:e|ed|ion)\b',
);
final _rawFalseContract = RegExp(
  r'\b(?:with|reserve\w*|allocat\w*|guarantee\w*)\b.{0,40}\bcapacity\b|\bthrows\b.{0,40}\bon (?:native )?failure\b',
);
final _rawWriteFalsePromise = RegExp(
  r'\b(?:logical|cells?|bytes?)\b.{0,30}\b(?:count|written)\b|'
  r'\bstable (?:bit )?encoding\b|\bthrows \[ffiexception\] on failure\b|'
  r'\bnative write failure\b.{0,30}\bthrows\b',
);
final _directRawWriteReturn = RegExp(
  r'return _generated\.textBufferWriteChunk\([^;]+\);\}\);\}$',
);
final _rawTextBufferFalseOutcome = RegExp(
  r'throws \[ffiexception\] on (?:native )?failure|'
  r'native failure.{0,30}(?:throws|mapped to \[ffiexception\])|'
  '(?<!no )nullable.{0,30}(?:empty|failure) sentinel|'
  'nullptr.{0,30}(?:empty|failure) sentinel|'
  '(?:complete|guaranteed).{0,30}cache',
);

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
  (path: 'lib/src/framework/focus_manager.dart', name: 'FocusNode'): {
    'attach',
    'detach',
  },
  _buildOwnerOwner: {
    'test',
    'pipelineOwner',
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
  _bufferOwner: {'invalidate', 'handle'},
  _rendererOwner: {'debugCurrentBuffer', 'handle', 'bindings'},
  (path: 'lib/src/core/text_buffer.dart', name: 'TextBuffer'): {
    'lineInfo',
    'compositingSnapshotFromCapturedHandle',
    'handle',
  },
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
};

const Set<_Owner> _builtInRenderWidgetOwners = <_Owner>{
  (path: 'lib/src/widgets/align.dart', name: 'Align'),
  (path: 'lib/src/widgets/constrained_box.dart', name: 'ConstrainedBox'),
  (path: 'lib/src/widgets/decorated_box.dart', name: 'DecoratedBox'),
  (path: 'lib/src/widgets/padding.dart', name: 'Padding'),
  (path: 'lib/src/widgets/pointer_listener.dart', name: 'PointerListener'),
  (path: 'lib/src/widgets/rich_text.dart', name: 'RichText'),
  (path: 'lib/src/widgets/text.dart', name: 'Text'),
  (path: 'lib/src/widgets/row_column.dart', name: 'Flex'),
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
