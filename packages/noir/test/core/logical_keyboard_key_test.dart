import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  test('named logical keys have unique stable ids', () {
    const keys = [
      LogicalKeyboardKey.unknown,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.tab,
      LogicalKeyboardKey.backspace,
      LogicalKeyboardKey.delete,
      LogicalKeyboardKey.insert,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyB,
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.keyE,
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.keyG,
      LogicalKeyboardKey.keyH,
      LogicalKeyboardKey.keyI,
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.keyM,
      LogicalKeyboardKey.keyN,
      LogicalKeyboardKey.keyO,
      LogicalKeyboardKey.keyP,
      LogicalKeyboardKey.keyQ,
      LogicalKeyboardKey.keyR,
      LogicalKeyboardKey.keyS,
      LogicalKeyboardKey.keyT,
      LogicalKeyboardKey.keyU,
      LogicalKeyboardKey.keyV,
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.keyX,
      LogicalKeyboardKey.keyY,
      LogicalKeyboardKey.keyZ,
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
      LogicalKeyboardKey.f1,
      LogicalKeyboardKey.f2,
      LogicalKeyboardKey.f3,
      LogicalKeyboardKey.f4,
      LogicalKeyboardKey.f5,
      LogicalKeyboardKey.f6,
      LogicalKeyboardKey.f7,
      LogicalKeyboardKey.f8,
      LogicalKeyboardKey.f9,
      LogicalKeyboardKey.f10,
      LogicalKeyboardKey.f11,
      LogicalKeyboardKey.f12,
      LogicalKeyboardKey.shift,
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.alt,
      LogicalKeyboardKey.meta,
    ];

    final keyIds = keys.map((key) => key.keyId).toList();

    expect(keyIds.toSet(), hasLength(keys.length));
    expect(LogicalKeyboardKey.f1, isNot(LogicalKeyboardKey.keyE));
  });

  test('one Unicode scalar is its own id above the named keys', () {
    final grinning = LogicalKeyboardKey.forCharacter('\u{1F600}');
    final heart = LogicalKeyboardKey.forCharacter('\u{1F9E1}');

    expect(grinning.keyId, 0x200000000 + 0x1F600);
    expect(heart.keyId, 0x200000000 + 0x1F9E1);
    expect(grinning, isNot(heart));
    expect({grinning, heart}, hasLength(2));
    expect(LogicalKeyboardKey.forCharacter('!').keyId, 0x200000000 + 0x21);
    expect(LogicalKeyboardKey.forCharacter('a'), LogicalKeyboardKey.keyA);
    expect(LogicalKeyboardKey.forCharacter(' '), LogicalKeyboardKey.space);
  });

  test('multi-scalar strings do not match on a colliding hash', () {
    // Two distinct pairs of scalars whose UTF-16 polynomial hash collides
    // in 29 bits. Shortcut identity must follow the text, not that hash.
    const left = '\u{12613}\u{14160}';
    const right = '\u{15C61}\u{11A96}';
    final leftKey = LogicalKeyboardKey.forCharacter(left);
    final rightKey = LogicalKeyboardKey.forCharacter(right);

    expect(leftKey.keyId, rightKey.keyId);
    expect(leftKey, isNot(rightKey));
    expect(leftKey.hashCode, isNot(rightKey.hashCode));
    expect({leftKey, rightKey}, hasLength(2));
    expect(LogicalKeyboardKey.forCharacter(left), leftKey);
  });
}
