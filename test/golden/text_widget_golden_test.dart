import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/golden_testing.dart';

/// Set UPDATE_GOLDENS=1 to regenerate golden files instead of comparing.
final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void main() {
  group('Text Widget Golden Tests', () {
    late GoldenTester tester;

    setUpAll(() {
      tester = GoldenTester(width: 50, height: 20);
    });

    tearDownAll(() {
      tester.dispose();
    });

    test('all text widget variations', () async {
      // Create all text widget test cases in a single map
      final textWidgetCases = <String, Widget>{
        // Basic Text Variations
        'simple_text': const Text('Hello World'),
        'long_text': const Text(
          'This is a very long text that should demonstrate text rendering',
        ),
        'empty_text': const Text(''),
        'single_character': const Text('X'),
        'text_with_symbols': const Text(r'Test 123 !@#$%^&*()'),

        // Text Alignment
        'left_aligned': const Text('Left Aligned'),
        'center_aligned': const Text(
          'Center Aligned',
          textAlign: TextAlign.center,
        ),
        'right_aligned': const Text(
          'Right Aligned',
          textAlign: TextAlign.right,
        ),

        // Text with Styles
        'colored_text': const Text(
          'Colored Text',
          style: TextStyle(color: Color.blue),
        ),
        'text_with_background': const Text(
          'Background Text',
          style: TextStyle(backgroundColor: Color.red),
        ),
        'bold_text': const Text(
          'Bold Text',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        'italic_text': const Text(
          'Italic Text',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
        'underlined_text': const Text(
          'Underlined Text',
          style: TextStyle(decoration: TextDecoration.underline),
        ),
        'styled_combination': const Text(
          'Styled Text',
          style: TextStyle(
            color: Color.yellow,
            backgroundColor: Color.blue,
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
          ),
        ),

        // Text in Containers
        'padded_text': const Container(
          padding: EdgeInsets.all(3),
          child: Text('Padded Text'),
        ),
        'asymmetric_padding': Container(
          padding: const EdgeInsets.only(left: 1, top: 2, right: 3, bottom: 4),
          child: const Text('Asymmetric Padding'),
        ),
        'container_centered': const Container(
          alignment: Alignment.center,
          width: 30,
          height: 5,
          child: Text('Centered in Container'),
        ),
        'decorated_container': const Container(
          padding: EdgeInsets.all(2),
          decoration: BoxDecoration(color: Color.green),
          child: Text('Decorated Container', style: TextStyle()),
        ),
        'sized_container': const Container(
          width: 25,
          height: 3,
          padding: EdgeInsets.all(1),
          child: Text('Sized Container Text'),
        ),

        // Text in Layout Widgets
        'text_in_row': const Row(
          children: [Text('Left'), Text('Middle'), Text('Right')],
        ),
        'row_with_spacing': const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text('Start'), Text('Center'), Text('End')],
        ),
        'text_in_column': const Column(
          children: [Text('Line 1'), Text('Line 2'), Text('Line 3')],
        ),
        'aligned_widget': const Align(
          alignment: Alignment.topRight,
          child: Text('Top Right Aligned'),
        ),
        'nested_layout': const Container(
          padding: EdgeInsets.all(2),
          child: Column(
            children: [
              Text('Title', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Text('Label: '),
                  Text('Value', style: TextStyle(color: Color.blue)),
                ],
              ),
              Text('Footer', textAlign: TextAlign.center),
            ],
          ),
        ),

        // Edge Cases
        'special_characters': const Text('Special: ASCII only test'),
        'text_with_newlines': const Text(r'Line 1\nLine 2\nLine 3'),
        'long_single_word': const Text('Supercalifragilisticexpialidocious'),
        'text_overflow': Text('A' * 60), // Longer than buffer width
      };

      // Test all cases using consolidated golden files
      await tester.expectGoldenMulti(
        textWidgetCases,
        'text_widgets',
        updateGoldens: _updateGoldens,
      );
    });
  });
}
