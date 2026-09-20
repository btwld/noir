// ignore_for_file: public_member_api_docs

import 'package:muse/muse.dart';
// This is the single audited renderer-adapter door approved by Muse ADR-0022.
// ignore: implementation_imports
import 'package:muse/src/internals.dart';

final class MuseNoirPreparedSurface {
  MuseNoirPreparedSurface._(this._value);

  final MusePreparedSurface _value;

  String get rootId => _value.rootId;

  MuseNoirPreparedComponent? component(String id) {
    final value = _value.components[id];
    return value == null ? null : MuseNoirPreparedComponent._(value);
  }
}

final class MuseNoirPreparedComponent {
  MuseNoirPreparedComponent._(this._value);

  final MusePreparedComponent _value;

  String get id => _value.id;
  String get type => _value.component;
  List<String> get children => _value.children;
  String? get actionName => _value.action?.name;
  Object? get actionIdentity => _value.action;
  double? get weight => switch (_value.properties['weight']) {
    final num value when value.isFinite && value > 0 => value.toDouble(),
    _ => null,
  };
}

MuseNoirPreparedSurface? museNoirPreparedSurfaceOf(MuseSurface surface) {
  final prepared = musePreparedSurfaceOf(surface);
  return prepared == null ? null : MuseNoirPreparedSurface._(prepared);
}

List<String> museNoirIncompatibleComponentTypes(
  MuseActivation activation,
  Iterable<MuseComponent> implemented,
  MuseNoirPreparedSurface surface,
) => museIncompatibleComponentTypes(
  activation.intent.catalog,
  implemented,
  surface._value.components.values.map((component) => component.component),
);

Map<String, Object?> museNoirComponentProperties(
  MuseActivation activation,
  String componentId,
) => museComponentProperties(activation, componentId);

bool museNoirActionEnabled(MuseActivation activation, String componentId) =>
    museActionEnabled(activation, componentId);

String? museNoirComponentErrorText(
  MuseActivation activation,
  String componentId,
) => museComponentErrorText(activation, componentId);

void museNoirEditComponent(
  MuseActivation activation,
  String componentId,
  String property,
  Object? value,
) => museEditComponent(activation, componentId, property, value);

Future<MuseActionResult> museNoirDispatch(
  MuseActivation activation,
  String componentId,
  String actionName,
  MuseNoirPreparedSurface rendered,
) => museDispatch(
  activation,
  componentId,
  actionName,
  museActionParameters(activation, componentId, rendered._value),
  rendered._value,
);

void Function() museNoirObserveActivation(
  MuseActivation activation,
  void Function() listener,
) => museObserveActivation(activation, listener);

String? museNoirNotFoundPath(MuseIntentNavigator navigator) =>
    museNotFoundPath(navigator);

void Function() museNoirObserveNotFound(
  MuseIntentNavigator navigator,
  void Function() listener,
) => museObserveNotFound(navigator, listener);
