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

  @override
  void dispose() {
    _live = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    return _buildComponent(context, prepared, prepared.rootId);
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
    return _MuseNoirComponentHost(
      key: ValueKey<String>('muse_component:${component.id}'),
      child: binding.builder(
        context,
        MuseNoirRenderNode.mounted(
          type: component.type,
          properties: properties,
          children: children,
          childWeights: childWeights,
          activate: actionName == null
              ? null
              : () {
                  if (!_live) return Future.value(_staleActionFailure());
                  return museNoirDispatch(
                    widget.activation,
                    component.id,
                    actionName,
                    prepared,
                  );
                },
          canActivate: () =>
              _live &&
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

  MuseActionResult _staleActionFailure() => MuseActionResult.failed(
    MuseFailure(
      code: 'stale_surface',
      message: 'The rendered surface is no longer mounted.',
    ),
  );
}

final class _MuseNoirComponentHost extends StatelessWidget {
  const _MuseNoirComponentHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
