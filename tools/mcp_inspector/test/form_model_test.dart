import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:noir_mcp_inspector/noir_mcp_inspector.dart';
import 'package:test/test.dart';

final _calculateSchema = JsonSchema.object(
  properties: <String, JsonSchema>{
    'operation': JsonSchema.string(
      enumValues: <String>['add', 'subtract', 'multiply', 'divide'],
      description: 'The arithmetic operation to apply',
    ),
    'a': JsonSchema.number(),
    'b': JsonSchema.number(),
  },
  required: <String>['operation', 'a', 'b'],
);

void main() {
  group('FormSpec.fromJsonSchema', () {
    test('maps the calculate schema to a select and two numbers', () {
      final spec = FormSpec.fromJsonSchema(_calculateSchema);

      expect(spec.fields.map((field) => field.name), <String>[
        'operation',
        'a',
        'b',
      ]);
      final operation = spec.fields.first;
      expect(operation.kind, FormFieldKind.select);
      expect(operation.options, <String>[
        'add',
        'subtract',
        'multiply',
        'divide',
      ]);
      expect(operation.isRequired, isTrue);
      expect(operation.description, 'The arithmetic operation to apply');
      expect(spec.fields[1].kind, FormFieldKind.number);
      expect(spec.fields[1].isRequired, isTrue);
      expect(spec.fields[2].kind, FormFieldKind.number);
    });

    test('maps each scalar schema to its own control', () {
      final spec = FormSpec.fromJsonSchema(
        JsonSchema.object(
          properties: <String, JsonSchema>{
            'note': JsonSchema.string(),
            'count': JsonSchema.integer(),
            'ratio': JsonSchema.number(),
            'newsletter': JsonSchema.boolean(defaultValue: true),
            'mode': JsonEnum(<dynamic>['fast', 'slow']),
          },
          required: <String>['note'],
        ),
      );

      expect(spec.fields.map((field) => field.kind), <FormFieldKind>[
        FormFieldKind.text,
        FormFieldKind.integer,
        FormFieldKind.number,
        FormFieldKind.boolean,
        FormFieldKind.select,
      ]);
      expect(spec.fields[3].initialFlag, isTrue);
      expect(spec.fields[4].options, <String>['fast', 'slow']);
      expect(
        spec.fields.where((field) => field.isRequired).single.name,
        'note',
      );
    });

    test('falls back to raw JSON for a shape it cannot map', () {
      final spec = FormSpec.fromJsonSchema(
        JsonSchema.object(
          properties: <String, JsonSchema>{
            'tags': JsonSchema.array(items: JsonSchema.string()),
          },
        ),
      );

      expect(spec.fields.single.kind, FormFieldKind.json);
    });

    test('summarises numeric and string constraints as hint text', () {
      final spec = FormSpec.fromJsonSchema(
        JsonSchema.object(
          properties: <String, JsonSchema>{
            'ratio': JsonSchema.number(minimum: 0, maximum: 100),
            'floor': JsonSchema.number(minimum: 0),
            'ceiling': JsonSchema.integer(maximum: 10),
            'step': JsonSchema.number(multipleOf: 5),
            'over': JsonSchema.number(exclusiveMinimum: 0),
            'name': JsonSchema.string(minLength: 1, maxLength: 64),
            'slug': JsonSchema.string(pattern: r'^[a-z]+$'),
            'email': JsonSchema.string(format: 'email'),
          },
        ),
      );

      final text = <String, String?>{
        for (final field in spec.fields) field.name: field.constraintText,
      };
      expect(text, <String, String?>{
        'ratio': '0..100',
        'floor': '>= 0',
        'ceiling': '<= 10',
        'step': 'multiple of 5',
        'over': '> 0',
        'name': 'length 1..64',
        'slug': r'pattern ^[a-z]+$',
        'email': 'format email',
      });
    });

    test('leaves constraint text null when the schema declares none', () {
      final spec = FormSpec.fromJsonSchema(_calculateSchema);

      expect(
        spec.fields.map((field) => field.constraintText),
        everyElement(isNull),
      );
    });

    /// Builds a one-property object schema through the wire parse path.
    ///
    /// The typed constructors normalise some values; `fromJson` does not, so
    /// this is the shape a real server can actually send.
    FormFieldSpec fieldFromWire(String propertyJson) {
      final schema = JsonSchema.fromJson(
        jsonDecode('{"type":"object","properties":{"x":$propertyJson}}')
            as Map<String, dynamic>,
      );
      return FormSpec.fromJsonSchema(schema).fields.single;
    }

    test('a non-finite bound keeps its own text instead of throwing', () {
      // `1e400` decodes to Infinity, and `Infinity.toInt()` throws. One such
      // property used to take down the whole tool list.
      expect(
        fieldFromWire('{"type":"number","maximum":1e400}').constraintText,
        '<= Infinity',
      );
    });

    test('a bound too large for an exact integer is not rounded', () {
      expect(
        fieldFromWire('{"type":"number","maximum":1e21}').constraintText,
        '<= 1e+21',
      );
    });

    test('an integer with fractional wire bounds still reports them', () {
      // The typed `int?` getters return null here, so the summary reads the
      // `num?` forms that carry the wire value.
      expect(
        fieldFromWire(
          '{"type":"integer","minimum":1.5,"maximum":9.5}',
        ).constraintText,
        '1.5..9.5',
      );
    });

    test('an array reports its item constraints', () {
      final field = fieldFromWire(
        '{"type":"array","minItems":1,"maxItems":5,"uniqueItems":true}',
      );

      expect(field.kind, FormFieldKind.json);
      expect(field.constraintText, 'items 1..5, unique');
    });

    test('a closed choice list reports no length constraint', () {
      final field = fieldFromWire(
        '{"type":"string","enum":["a","b"],"minLength":1}',
      );

      expect(field.kind, FormFieldKind.select);
      expect(field.constraintText, isNull);
    });

    test('joins the description and the constraints into one hint', () {
      final spec = FormSpec.fromJsonSchema(
        JsonSchema.object(
          properties: <String, JsonSchema>{
            'both': JsonSchema.number(
              description: 'The left operand',
              minimum: 0,
              maximum: 100,
            ),
            'describedOnly': JsonSchema.string(description: 'A note'),
            'constrainedOnly': JsonSchema.string(format: 'email'),
            'bare': JsonSchema.string(),
          },
        ),
      );

      expect(
        <String?>[for (final field in spec.fields) field.hint],
        <String?>['The left operand  (0..100)', 'A note', 'format email', null],
      );
    });

    test('yields an empty specification for a schema without properties', () {
      expect(FormSpec.fromJsonSchema(null).isEmpty, isTrue);
      expect(FormSpec.fromJsonSchema(JsonSchema.string()).isEmpty, isTrue);
      expect(
        FormSpec.fromJsonSchema(
          JsonSchema.object(properties: <String, JsonSchema>{}),
        ).isEmpty,
        isTrue,
      );
    });

    test('maps prompt arguments to required and optional text fields', () {
      final spec = FormSpec.fromPromptArguments(<PromptArgument>[
        const PromptArgument(
          name: 'language',
          description: 'Programming language',
          required: true,
        ),
        const PromptArgument(name: 'style'),
      ]);

      expect(spec.fields.map((field) => field.kind), <FormFieldKind>[
        FormFieldKind.text,
        FormFieldKind.text,
      ]);
      expect(spec.fields.first.isRequired, isTrue);
      expect(spec.fields.last.isRequired, isFalse);
    });
  });

  group('FormModel', () {
    test('coerces text into num arguments', () {
      final model = FormModel(FormSpec.fromJsonSchema(_calculateSchema))
        ..setText('a', '5')
        ..setText('b', '3');
      addTearDown(model.dispose);

      final arguments = model.toArguments();

      expect(arguments.isValid, isTrue);
      expect(arguments.values, <String, Object?>{
        'operation': 'add',
        'a': 5,
        'b': 3,
      });
      expect(arguments.values['a'], isA<num>());
    });

    test('starts a select on its first option when there is no default', () {
      final model = FormModel(FormSpec.fromJsonSchema(_calculateSchema));
      addTearDown(model.dispose);

      expect(model.textOf('operation'), 'add');
      expect(model.controllerFor('operation')!.text, 'add');
    });

    test('reports every required field the user left empty', () {
      final model = FormModel(FormSpec.fromJsonSchema(_calculateSchema))
        ..setText('a', '5');
      addTearDown(model.dispose);

      final arguments = model.toArguments();

      expect(arguments.isValid, isFalse);
      expect(arguments.missing, <String>['b']);
      expect(arguments.problem, 'Missing required: b');
    });

    test('reports text that cannot be coerced', () {
      final model = FormModel(FormSpec.fromJsonSchema(_calculateSchema))
        ..setText('a', 'five')
        ..setText('b', '3');
      addTearDown(model.dispose);

      final arguments = model.toArguments();

      expect(arguments.isValid, isFalse);
      expect(arguments.invalid, <String, String>{'a': 'not a number'});
      expect(arguments.problem, 'a: not a number');
    });

    test('always sends a boolean and omits an empty optional field', () {
      final model = FormModel(
        FormSpec.fromJsonSchema(
          JsonSchema.object(
            properties: <String, JsonSchema>{
              'newsletter': JsonSchema.boolean(),
              'note': JsonSchema.string(),
            },
          ),
        ),
      )..setFlag('newsletter', value: true);
      addTearDown(model.dispose);

      expect(model.toArguments().values, <String, Object?>{'newsletter': true});
    });

    test('parses a raw JSON field and reports a malformed one', () {
      final spec = FormSpec.fromJsonSchema(
        JsonSchema.object(
          properties: <String, JsonSchema>{
            'tags': JsonSchema.array(items: JsonSchema.string()),
          },
        ),
      );
      final good = FormModel(spec)..setText('tags', '["a","b"]');
      addTearDown(good.dispose);
      final bad = FormModel(spec)..setText('tags', '[a');
      addTearDown(bad.dispose);

      expect(good.toArguments().values['tags'], <String>['a', 'b']);
      expect(bad.toArguments().invalid.keys, <String>['tags']);
    });

    test('renders prompt arguments as strings', () {
      final model = FormModel(
        FormSpec.fromPromptArguments(<PromptArgument>[
          const PromptArgument(name: 'language', required: true),
        ]),
      )..setText('language', 'dart');
      addTearDown(model.dispose);

      expect(model.toArguments().asStrings, <String, String>{
        'language': 'dart',
      });
    });
  });
}
