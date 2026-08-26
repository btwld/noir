/// Named single-cell glyphs for terminal chrome.
library;

/// Named glyphs for marks, carets, arrows, shapes, keys, and status markers.
///
/// A terminal icon is a character, not an asset, so these are plain [String]
/// grapheme clusters rather than an `IconData`-style handle. Render one with
/// [Text] and color it through [TextStyle], or write it straight into a cell
/// with `TuiCanvas.setCell`:
///
/// ```dart
/// Text(Icons.check, style: TextStyle(color: theme.success))
/// ```
///
/// There is deliberately no `Icon` widget: it could only forward a string and
/// a color to [Text], which is what the caller already writes. There is no
/// `IconTheme` either — [ThemeData] already carries the color tokens, and a
/// glyph has no size to inherit on a fixed cell grid.
///
/// ## Two width groups
///
/// Terminals disagree about how wide some characters are, and Noir's layout
/// model (`terminalCellWidth`) has to commit to one answer: every member here
/// is one cell in that model. The groups describe what a *real* terminal does,
/// which is a separate question, and the two failure modes are not equally
/// severe.
///
/// - **Narrow** — not East-Asian-ambiguous, so expected to stay one cell across
///   normal terminal width modes. Everything from [check] through [minus].
/// - **Ambiguous** — one cell unless the terminal is configured to double East
///   Asian ambiguous width (an iTerm2 option, common in CJK locales).
///   Everything from [square] through [infinity].
///
/// **The conservative rule this catalog enforces is that no non-ASCII member
/// carries the Unicode `Emoji` property.** Those characters have an emoji
/// presentation available, and some terminal/font environments may choose it
/// and occupy two cells. Excluding them avoids an environment-dependent width
/// change when a value flips. ASCII keycap bases are safe when rendered alone,
/// so [asterisk] remains available even though `*` carries the property.
///
/// **Mixing narrow with ambiguous is weaker than that, and is a preference
/// rather than a guarantee.** It costs a cell only under ambiguous-doubling —
/// and in exactly that configuration Noir's box-drawing borders, `Divider`
/// rules, and block-element progress bars have already shifted, because they
/// are ambiguous too. Prefer one group for a fixed column or a state pair when
/// the choice is free, and do not contort a design to get there. Free-running
/// prose such as a hint string can mix them, because nothing is aligned to it.
///
/// `test/architecture/icon_width_class_test.dart` fails if a member leaves its
/// declared group, and `test/widgets/icon_state_pair_test.dart` fails if a
/// rendered toggle pairs glyphs from two groups.
///
/// ## What is missing, and why
///
/// Non-ASCII characters carrying the Unicode `Emoji` property are excluded
/// conservatively, even when their default Unicode presentation is text. That
/// rules out some obvious choices, each of which has a stand-in here:
///
/// | Wanted | Excluded because | Use instead |
/// |---|---|---|
/// | `⚠` warning sign | `Emoji` | [triangleUpOutline] or [bang] |
/// | `▶` `◀` triangles | `Emoji` | [pointerRight] / [pointerLeft] |
/// | `✔` heavy check | `Emoji` | [check] |
/// | `☑` ballot box | `Emoji`, and `☐` is not — the pair changes width | [square] / [squareOutline] |
/// | `♥` black heart | `Emoji` | [sparkle] |
/// | `⚙` gear | `Emoji` | [asterisk] |
/// | `⏸` `⏹` media keys | `Emoji` | [bar] / [rectangle] |
///
/// Nerd Font private-use glyphs are also absent: Noir does not assume a patched
/// font is installed.
abstract final class Icons {
  // ----------------------------------------------------------------------
  // Marks
  // ----------------------------------------------------------------------

  /// Check mark reporting success or a satisfied condition.
  static const String check = '✓'; // U+2713

  /// Struck check mark reporting a condition that failed its check.
  static const String checkNot = '⍻'; // U+237B

  /// Ballot X reporting failure, rejection, or a dismiss affordance.
  static const String close = '✗'; // U+2717

  /// Heavier [close] for when the light stroke reads too faintly.
  static const String closeHeavy = '✘'; // U+2718

  /// Geometrically centered X, the usual dismiss affordance.
  static const String closeThin = '✕'; // U+2715

  /// Exclamation mark reporting an error or a warning that needs attention.
  static const String bang = '!'; // U+0021

  /// Question mark reporting an unknown or unresolved state.
  static const String query = '?'; // U+003F

  /// Asterisk marking a footnote, a required field, or a modified item.
  static const String asterisk = '*'; // U+002A

  // ----------------------------------------------------------------------
  // Carets — small filled. The default disclosure and sort direction
  // marks.
  // ----------------------------------------------------------------------

  /// Upward caret, and the ascending sort direction.
  static const String caretUp = '▴'; // U+25B4

  /// Downward caret, and the descending sort direction.
  static const String caretDown = '▾'; // U+25BE

  /// Leftward caret, marking a collapsed or previous position.
  static const String caretLeft = '◂'; // U+25C2

  /// Rightward caret, marking a collapsed node or the selected row.
  static const String caretRight = '▸'; // U+25B8

  // ----------------------------------------------------------------------
  // Carets — small hollow, for an inactive or secondary disclosure.
  // ----------------------------------------------------------------------

  /// Hollow [caretUp].
  static const String caretUpOutline = '▵'; // U+25B5

  /// Hollow [caretDown].
  static const String caretDownOutline = '▿'; // U+25BF

  /// Hollow [caretLeft].
  static const String caretLeftOutline = '◃'; // U+25C3

  /// Hollow [caretRight].
  static const String caretRightOutline = '▹'; // U+25B9

  // ----------------------------------------------------------------------
  // Carets — medium, when the small carets read too faintly.
  // ----------------------------------------------------------------------

  /// Medium [caretUp].
  static const String caretUpMedium = '⏶'; // U+23F6

  /// Medium [caretDown].
  static const String caretDownMedium = '⏷'; // U+23F7

  /// Medium [caretLeft].
  static const String caretLeftMedium = '⏴'; // U+23F4

  /// Medium [caretRight].
  static const String caretRightMedium = '⏵'; // U+23F5

  // ----------------------------------------------------------------------
  // Pointers — solid wedges. [pointerRight] also reads as a play
  // affordance.
  // ----------------------------------------------------------------------

  /// Rightward wedge, heavier than [caretRight].
  static const String pointerRight = '►'; // U+25BA

  /// Leftward wedge, heavier than [caretLeft].
  static const String pointerLeft = '◄'; // U+25C4

  /// Hollow [pointerRight].
  static const String pointerRightOutline = '▻'; // U+25BB

  /// Hollow [pointerLeft].
  static const String pointerLeftOutline = '◅'; // U+25C5

  // ----------------------------------------------------------------------
  // Chevrons
  // ----------------------------------------------------------------------

  /// Single left angle quote, used as a back or previous affordance.
  static const String chevronLeft = '‹'; // U+2039

  /// Single right angle quote, used as a forward or next affordance.
  static const String chevronRight = '›'; // U+203A

  /// Double left angle quote, used for a first or jump-back affordance.
  static const String chevronDoubleLeft = '«'; // U+00AB

  /// Double right angle quote, used for a last or jump-forward affordance.
  static const String chevronDoubleRight = '»'; // U+00BB

  // ----------------------------------------------------------------------
  // Arrows — narrow variants. The plain arrows are ambiguous-width; see
  // [arrowUp].
  // ----------------------------------------------------------------------

  /// Two-headed up arrow, reading as a jump to the start.
  static const String arrowUpDouble = '↟'; // U+219F

  /// Two-headed down arrow, reading as a jump to the end.
  static const String arrowDownDouble = '↡'; // U+21A1

  /// Two-headed left arrow, reading as a jump to the first item.
  static const String arrowLeftDouble = '↞'; // U+219E

  /// Two-headed right arrow, reading as a jump to the last item.
  static const String arrowRightDouble = '↠'; // U+21A0

  /// Up arrow from a bar, reading as a promote or move-to-top action.
  static const String arrowUpToBar = '↥'; // U+21A5

  /// Down arrow from a bar, reading as a demote or move-to-bottom action.
  static const String arrowDownToBar = '↧'; // U+21A7

  /// Struck left arrow reporting a move that is not available.
  static const String arrowLeftBlocked = '↚'; // U+219A

  /// Struck right arrow reporting a move that is not available.
  static const String arrowRightBlocked = '↛'; // U+219B

  /// Down-then-right arrow marking a nested or derived entry.
  static const String arrowBranchDown = '↳'; // U+21B3

  /// Up-then-left arrow marking a return to an enclosing entry.
  static const String arrowBranchUp = '↰'; // U+21B0

  /// Wavy right arrow marking an indirect or asynchronous step.
  static const String arrowWavyRight = '↝'; // U+219D

  /// Heavy north-east arrow marking a link that leaves the application. `↗`
  /// carries the Unicode `Emoji` property and may receive a two-cell emoji
  /// presentation in some environments.
  static const String arrowUpRight = '➚'; // U+279A

  // ----------------------------------------------------------------------
  // Keyboard keys, for key hints in a footer or a help pane.
  // ----------------------------------------------------------------------

  /// Return key.
  static const String enter = '⏎'; // U+23CE

  /// Keypad Enter key, distinct from [enter].
  static const String enterKeypad = '⌤'; // U+2324

  /// Escape key.
  static const String escape = '␛'; // U+241B

  /// Backspace key, which erases to the left.
  static const String backspace = '⌫'; // U+232B

  /// Forward-delete key, which erases to the right.
  static const String deleteForward = '⌦'; // U+2326

  /// Tab key, which moves focus forward.
  static const String tab = '⇥'; // U+21E5

  /// Shift+Tab, which moves focus backward.
  static const String tabBack = '⇤'; // U+21E4

  /// Control modifier key.
  static const String control = '⌃'; // U+2303

  /// Option or Alt modifier key.
  static const String option = '⌥'; // U+2325

  /// Command modifier key.
  static const String command = '⌘'; // U+2318

  /// Caps Lock key.
  static const String capsLock = '⇪'; // U+21EA

  /// Power symbol, reading as a quit or shutdown affordance.
  static const String power = '⏻'; // U+23FB

  // ----------------------------------------------------------------------
  // Shapes — narrow. Use these to avoid East-Asian-ambiguous width.
  // ----------------------------------------------------------------------

  /// Hollow rounded square.
  static const String squareRounded = '▢'; // U+25A2

  /// Filled wide rectangle, reading as a stop affordance.
  static const String rectangle = '▬'; // U+25AC

  /// Hollow [rectangle].
  static const String rectangleOutline = '▭'; // U+25AD

  /// Filled upright bar, reading as a pause affordance or a block cursor.
  static const String bar = '▮'; // U+25AE

  /// Hollow [bar].
  static const String barOutline = '▯'; // U+25AF

  /// Filled lozenge, a narrow stand-in for [diamond].
  static const String lozenge = '⧫'; // U+29EB

  /// Hollow [lozenge].
  static const String lozengeOutline = '◊'; // U+25CA

  /// Filled circle inside a ring, reading as a selected radio option.
  static const String fisheye = '◉'; // U+25C9

  /// Dotted ring marking an empty slot or a placeholder.
  static const String circleDotted = '◌'; // U+25CC

  /// Small hollow circle, a narrow stand-in for [circleOutline].
  static const String circleSmall = '⚬'; // U+26AC

  // ----------------------------------------------------------------------
  // Bullets — narrow.
  // ----------------------------------------------------------------------

  /// Small filled bullet.
  static const String bulletSmall = '∙'; // U+2219

  /// Hollow bullet, marking a nested list level.
  static const String bulletOutline = '◦'; // U+25E6

  /// Triangular bullet.
  static const String bulletTriangular = '‣'; // U+2023

  /// Hyphen bullet, for a list that should read as plain text.
  static const String bulletHyphen = '⁃'; // U+2043

  // ----------------------------------------------------------------------
  // Stars — narrow.
  // ----------------------------------------------------------------------

  /// Filled four-pointed star, marking something new or highlighted.
  static const String sparkle = '✦'; // U+2726

  /// Hollow [sparkle].
  static const String sparkleOutline = '✧'; // U+2727

  /// Outlined five-pointed star, a narrow stand-in for [starOutline].
  static const String starHollow = '⚝'; // U+269D

  /// Small star, for a dense rating row.
  static const String starSmall = '⋆'; // U+22C6

  // ----------------------------------------------------------------------
  // Objects and actions.
  // ----------------------------------------------------------------------

  /// Magnifier, marking a search field or a filter.
  static const String search = '⌕'; // U+2315

  /// House, marking a root or home position.
  static const String home = '⌂'; // U+2302

  /// Pencil, marking an editable or modified item.
  static const String pencil = '✎'; // U+270E

  /// Scissors, marking a cut action or a tear line.
  static const String scissors = '✄'; // U+2704

  /// Bell, marking a notification or an alert setting.
  static const String bell = '⍾'; // U+237E

  /// Filled hourglass reporting work in progress.
  static const String hourglass = '⧗'; // U+29D7

  /// Hollow [hourglass], reporting work that has not started.
  static const String hourglassOutline = '⧖'; // U+29D6

  /// Clockwise circle arrow reporting a reload or retry.
  static const String refresh = '↻'; // U+21BB

  /// Anticlockwise circle arrow reporting an undo or revert.
  static const String undo = '↺'; // U+21BA

  /// Fork, marking a branch or a diverged history.
  static const String branch = '⑂'; // U+2442

  /// Plus sign, marking an add or expand action.
  static const String plus = '+'; // U+002B

  /// True minus sign, wider than the ASCII hyphen.
  static const String minus = '−'; // U+2212

  // ----------------------------------------------------------------------
  // Shapes — filled. These match the ambiguous-width box-drawing chrome.
  // ----------------------------------------------------------------------

  /// Filled square. `Checkbox` paints this for a checked value.
  static const String square = '■'; // U+25A0

  /// Filled circle. `Switch` paints this when on, and it reads as a live
  /// status dot.
  static const String circle = '●'; // U+25CF

  /// Filled diamond, a status marker distinct from [circle] in monochrome.
  static const String diamond = '◆'; // U+25C6

  /// Filled up triangle. `DataTable` paints this for an ascending sort.
  static const String triangleUp = '▲'; // U+25B2

  /// Filled down triangle. `DataTable` paints this for a descending sort.
  static const String triangleDown = '▼'; // U+25BC

  // ----------------------------------------------------------------------
  // Shapes — hollow.
  // ----------------------------------------------------------------------

  /// Hollow square. `Checkbox` paints this for an unchecked value.
  static const String squareOutline = '□'; // U+25A1

  /// Hollow circle. `Switch` paints this when off, and it reads as an idle
  /// status dot.
  static const String circleOutline = '○'; // U+25CB

  /// Hollow [diamond].
  static const String diamondOutline = '◇'; // U+25C7

  /// Hollow up triangle, the warning shape. There is no `⚠` here: it carries
  /// the Unicode `Emoji` property.
  static const String triangleUpOutline = '△'; // U+25B3

  /// Hollow down triangle.
  static const String triangleDownOutline = '▽'; // U+25BD

  // ----------------------------------------------------------------------
  // Circle variants, for dense state columns.
  // ----------------------------------------------------------------------

  /// Ring inside a ring, marking a focused or targeted item.
  static const String bullseye = '◎'; // U+25CE

  /// Large hollow circle.
  static const String circleLarge = '◯'; // U+25EF

  /// Circle with its left half filled, reporting partial progress.
  static const String circleHalfLeft = '◐'; // U+25D0

  /// Circle with its right half filled, reporting partial progress.
  static const String circleHalfRight = '◑'; // U+25D1

  // ----------------------------------------------------------------------
  // Status and rating.
  // ----------------------------------------------------------------------

  /// Circled lowercase i reporting neutral information.
  static const String info = 'ⓘ'; // U+24D8

  /// Filled star, marking a favorite or a high rating.
  static const String star = '★'; // U+2605

  /// Hollow [star], marking an unset favorite or an empty rating slot.
  static const String starOutline = '☆'; // U+2606

  // ----------------------------------------------------------------------
  // Arrows — plain. These read as the literal cursor keys in a hint
  // string.
  // ----------------------------------------------------------------------

  /// Up arrow.
  static const String arrowUp = '↑'; // U+2191

  /// Down arrow.
  static const String arrowDown = '↓'; // U+2193

  /// Left arrow.
  static const String arrowLeft = '←'; // U+2190

  /// Right arrow, which also reads as a "maps to" separator.
  static const String arrowRight = '→'; // U+2192

  /// Shift modifier key. Ambiguous-width, unlike the other key glyphs.
  static const String shift = '⇧'; // U+21E7

  // ----------------------------------------------------------------------
  // Punctuation and separators.
  // ----------------------------------------------------------------------

  /// List bullet.
  static const String bullet = '•'; // U+2022

  /// Middle dot, a lighter [bullet] and the usual hint-string separator.
  static const String dot = '·'; // U+00B7

  /// Horizontal ellipsis reporting elided content or a pending action.
  static const String ellipsis = '…'; // U+2026

  /// Em dash, for a break in a sentence.
  static const String dashEm = '—'; // U+2014

  /// En dash, for a numeric range.
  static const String dashEn = '–'; // U+2013

  // ----------------------------------------------------------------------
  // Mathematical and unit signs.
  // ----------------------------------------------------------------------

  /// Degree sign.
  static const String degree = '°'; // U+00B0

  /// Plus-minus sign, for a tolerance or a delta.
  static const String plusMinus = '±'; // U+00B1

  /// Multiplication sign, for dimensions such as 80×24.
  static const String times = '×'; // U+00D7

  /// Division sign.
  static const String divide = '÷'; // U+00F7

  /// Not-equal sign.
  static const String notEqual = '≠'; // U+2260

  /// Less-than-or-equal sign.
  static const String lessEqual = '≤'; // U+2264

  /// Greater-than-or-equal sign.
  static const String greaterEqual = '≥'; // U+2265

  /// Almost-equal sign, for a rounded figure.
  static const String approxEqual = '≈'; // U+2248

  /// Identical-to sign, which also reads as a list or menu affordance.
  static const String identical = '≡'; // U+2261

  /// Infinity sign, for an unbounded limit.
  static const String infinity = '∞'; // U+221E
}
