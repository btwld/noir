import 'package:noir/noir.dart';

/// Shared palette for the pub search example.
///
/// The search shell and the package detail surface are separate widgets that
/// must stay visually identical, so the palette lives in one place rather than
/// being repeated in both files.

/// Page background behind every surface.
const pubBackground = Color(0.025, 0.045, 0.055);

/// Raised panel behind grouped content.
const pubPanel = Color(0.04, 0.075, 0.085);

/// Panel behind the active detail tab.
const pubActivePanel = Color(0.075, 0.17, 0.17);

/// Row background behind the highlighted search result.
const pubSelection = Color(0.08, 0.23, 0.22);

/// Primary accent used for focus, selection, and headings.
const pubAccent = Color(0.39, 0.85, 0.78);

/// Secondary accent used for values that deserve emphasis.
const pubHighlight = Color(0.95, 0.72, 0.32);

/// Low-emphasis label and help text.
const pubMuted = Color(0.42, 0.51, 0.56);

/// Resting border for unfocused panels.
const pubBorder = Color(0.16, 0.28, 0.30);
