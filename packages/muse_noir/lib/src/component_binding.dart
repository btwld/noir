import 'dart:collection';

import 'package:muse/muse.dart';
import 'package:noir/noir.dart';

/// Builds one resolved component of an accepted Muse surface.
typedef MuseNoirComponentBuilder =
    Widget Function(BuildContext context, MuseNoirRenderNode node);

/// A Muse component declaration paired with its trusted Noir builder.
final class MuseNoirComponentBinding {
  /// Creates a declaration paired with its trusted [builder].
  MuseNoirComponentBinding({
    required String name,
    required String description,
    required this.builder,
    Map<String, MuseProperty> properties = const {},
    MuseChildren children = MuseChildren.none,
    bool checkable = false,
  }) : component = MuseComponent(
         name: name,
         description: description,
         properties: properties,
         children: children,
         checkable: checkable,
       );

  /// Pure component declaration.
  final MuseComponent component;

  /// Trusted builder for [component].
  final MuseNoirComponentBuilder builder;
}

/// Trusted component implementations available to a Muse Noir view.
final class MuseNoirRenderer {
  /// Registers a non-empty list of uniquely named [components].
  MuseNoirRenderer(List<MuseNoirComponentBinding> components) {
    if (components.isEmpty) {
      throw ArgumentError.value(components, 'components', 'Must not be empty.');
    }
    final entries = <String, MuseNoirComponentBinding>{};
    for (final entry in components) {
      final name = entry.component.name;
      if (entries.containsKey(name)) {
        throw MuseDeclarationError(
          'duplicate_name',
          'The renderer repeats component "$name".',
        );
      }
      entries[name] = entry;
    }
    _components = Map<String, MuseNoirComponentBinding>.unmodifiable(entries);
  }

  late final Map<String, MuseNoirComponentBinding> _components;

  /// Registered bindings keyed by component name.
  Map<String, MuseNoirComponentBinding> get components => _components;

  /// Derives a catalog from these exact declarations.
  MuseCatalog catalog({required String id, String? guidance}) => MuseCatalog(
    id: id,
    components: [for (final entry in _components.values) entry.component],
    guidance: guidance,
  );
}

/// One resolved component as its trusted builder sees it.
final class MuseNoirRenderNode {
  /// Creates an inert node for direct tests of a builder.
  MuseNoirRenderNode({
    required this.type,
    required Map<String, Object?> properties,
    List<Widget> children = const <Widget>[],
    List<double?> childWeights = const <double?>[],
    Future<MuseActionResult> Function()? activate,
    this.errorText,
  }) : properties = UnmodifiableMapView(Map.of(properties)),
       children = List<Widget>.unmodifiable(children),
       childWeights = _validatedWeights(children, childWeights),
       _activate = activate,
       _canActivate = null,
       _onEdit = null;

  /// Creates a node connected to a mounted accepted surface.
  MuseNoirRenderNode.mounted({
    required this.type,
    required Map<String, Object?> properties,
    required List<Widget> children,
    required List<double?> childWeights,
    required Future<MuseActionResult> Function()? activate,
    required bool Function() canActivate,
    required this.errorText,
    required void Function(String property, Object? value) onEdit,
  }) : properties = UnmodifiableMapView(Map.of(properties)),
       children = List<Widget>.unmodifiable(children),
       childWeights = _validatedWeights(children, childWeights),
       _activate = activate,
       _canActivate = canActivate,
       _onEdit = onEdit;

  /// Catalog component name.
  final String type;

  /// Resolved values, including current local drafts.
  final Map<String, Object?> properties;

  /// Built children in composition order.
  final List<Widget> children;

  /// Implicit weights corresponding one-for-one with [children].
  final List<double?> childWeights;

  /// First failing derived check for this edited control.
  final String? errorText;
  final Future<MuseActionResult> Function()? _activate;
  final bool Function()? _canActivate;
  final void Function(String property, Object? value)? _onEdit;

  /// Validated activation, or null when this component has no action.
  ///
  /// The callback remains available while a draft is temporarily invalid so
  /// an editable control can update the draft and activate in one gesture.
  /// Muse rechecks eligibility and provenance when the callback runs.
  Future<MuseActionResult> Function()? get activate => _activate;

  /// Whether [activate] is currently eligible to run.
  bool get canActivate =>
      _activate != null && (_canActivate == null || _canActivate());

  /// Records a local edit without mutating application state.
  void edit(String property, Object? value) {
    if (property.trim().isEmpty) {
      throw ArgumentError.value(property, 'property', 'Must not be empty.');
    }
    final onEdit = _onEdit;
    if (onEdit == null) {
      throw StateError('Only a live mounted MuseNoirRenderNode accepts edits.');
    }
    onEdit(property, value);
  }

  static List<double?> _validatedWeights(
    List<Widget> children,
    List<double?> weights,
  ) {
    if (weights.isNotEmpty && weights.length != children.length) {
      throw ArgumentError.value(
        weights,
        'childWeights',
        'Must be empty or correspond one-for-one with children.',
      );
    }
    return List<double?>.unmodifiable(
      weights.isEmpty ? List<double?>.filled(children.length, null) : weights,
    );
  }
}
