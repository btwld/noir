// ignore_for_file: public_member_api_docs

import 'package:muse/muse.dart';
import 'package:noir/noir.dart';

import 'component_binding.dart';
import 'muse_bridge.dart';

final class MuseNoirSurfaceView extends StatefulWidget {
  const MuseNoirSurfaceView({
    required this.activation,
    required this.surface,
    required this.renderer,
    required this.error,
    super.key,
  });

  final MuseActivation activation;
  final MuseSurface surface;
  final MuseNoirRenderer renderer;
  final Widget Function(BuildContext context, MuseFailure failure) error;

  @override
  State<MuseNoirSurfaceView> createState() => _MuseNoirSurfaceViewState();
}

final class _MuseNoirSurfaceViewState extends State<MuseNoirSurfaceView> {
  var _live = true;
  final Map<String, _ActionLease> _actions = <String, _ActionLease>{};

  @override
  void dispose() {
    _live = false;
    for (final action in _actions.values) {
      action.active = false;
    }
    _actions.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final action in _actions.values) {
      action.active = false;
    }
    final prepared = museNoirPreparedSurfaceOf(widget.surface);
    if (prepared == null) {
      return widget.error(
        context,
        MuseFailure(
          code: 'invalid_surface',
          message: 'Muse did not provide a renderer-ready surface.',
        ),
      );
    }
    final incompatible = museNoirIncompatibleComponentTypes(
      widget.activation,
      widget.renderer.components.values.map((entry) => entry.component),
      prepared,
    );
    if (incompatible.isNotEmpty) {
      return widget.error(
        context,
        MuseFailure(
          code: 'renderer_missing_components',
          message:
              'Renderer has absent or incompatible components: '
              '${incompatible.join(', ')}.',
        ),
      );
    }
    final root = _buildComponent(context, prepared, prepared.rootId);
    _actions.removeWhere((_, action) => !action.active);
    return root;
  }

  Widget _buildComponent(
    BuildContext context,
    MuseNoirPreparedSurface prepared,
    String componentId,
  ) {
    final component = prepared.component(componentId);
    if (component == null) {
      return widget.error(
        context,
        MuseFailure(
          code: 'invalid_surface',
          message: 'The accepted surface has a missing component.',
        ),
      );
    }
    final properties = museNoirComponentProperties(
      widget.activation,
      component.id,
    );
    if (properties['visible'] == false) return const SizedBox.shrink();

    final children = <Widget>[
      for (final childId in component.children)
        _buildComponent(context, prepared, childId),
    ];
    final childWeights = <double?>[
      for (final childId in component.children)
        prepared.component(childId)?.weight,
    ];
    final binding = widget.renderer.components[component.type]!;
    final actionName = component.actionName;
    final action = actionName == null
        ? null
        : _actionFor(component, actionName, prepared);
    return _MuseNoirComponentHost(
      key: ValueKey<String>('muse_component:${component.id}'),
      child: binding.builder(
        context,
        MuseNoirRenderNode.mounted(
          type: component.type,
          properties: properties,
          children: children,
          childWeights: childWeights,
          activate: action?.activate,
          canActivate: () =>
              _live &&
              (action == null || action.active) &&
              widget.activation.status.value != MuseActivationStatus.disposed &&
              museNoirActionEnabled(widget.activation, component.id),
          errorText: museNoirComponentErrorText(
            widget.activation,
            component.id,
          ),
          onEdit: (property, value) {
            if (!_live ||
                widget.activation.status.value ==
                    MuseActivationStatus.disposed) {
              throw StateError('The Muse surface is no longer mounted.');
            }
            museNoirEditComponent(
              widget.activation,
              component.id,
              property,
              value,
            );
          },
        ),
      ),
    );
  }

  _ActionLease _actionFor(
    MuseNoirPreparedComponent component,
    String actionName,
    MuseNoirPreparedSurface prepared,
  ) {
    final identity = component.actionIdentity;
    var action = _actions[component.id];
    if (action == null ||
        !identical(action.identity, identity) ||
        action.name != actionName) {
      action?.active = false;
      action = _ActionLease(
        identity: identity,
        name: actionName,
        componentId: component.id,
        dispatch: _dispatch,
      );
      _actions[component.id] = action;
    }
    action
      ..prepared = prepared
      ..active = true;
    return action;
  }

  Future<MuseActionResult> _dispatch(_ActionLease action) {
    if (!_live ||
        !action.active ||
        widget.activation.status.value == MuseActivationStatus.disposed) {
      return Future<MuseActionResult>.value(_staleActionFailure());
    }
    return museNoirDispatch(
      widget.activation,
      action.componentId,
      action.name,
      action.prepared,
    );
  }

  MuseActionResult _staleActionFailure() => MuseActionResult.failed(
    MuseFailure(
      code: 'stale_surface',
      message: 'The rendered surface is no longer mounted.',
    ),
  );
}

final class _ActionLease {
  _ActionLease({
    required this.identity,
    required this.name,
    required this.componentId,
    required Future<MuseActionResult> Function(_ActionLease action) dispatch,
  }) {
    activate = () => dispatch(this);
  }

  final Object? identity;
  final String name;
  final String componentId;
  late final Future<MuseActionResult> Function() activate;
  late MuseNoirPreparedSurface prepared;
  bool active = false;
}

final class _MuseNoirComponentHost extends StatelessWidget {
  const _MuseNoirComponentHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
