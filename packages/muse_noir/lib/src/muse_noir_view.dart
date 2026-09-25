import 'package:muse/muse.dart';
import 'package:noir/noir.dart';

import 'component_binding.dart';
import 'muse_bridge.dart';
import 'surface_view.dart';

/// Builds the initial loading presentation.
typedef MuseNoirLoadingBuilder = Widget Function(BuildContext context);

/// Builds a typed generation or renderer failure presentation.
typedef MuseNoirErrorBuilder =
    Widget Function(BuildContext context, MuseFailure failure);

/// Builds an unmatched-route presentation.
typedef MuseNoirNotFoundBuilder =
    Widget Function(BuildContext context, String path);

/// Presents the borrowed navigator's current activation through Noir widgets.
final class MuseNoirView extends StatefulWidget {
  /// Creates a view that borrows [navigator] and [renderer].
  const MuseNoirView({
    required this.navigator,
    required this.renderer,
    this.loadingBuilder,
    this.errorBuilder,
    this.notFoundBuilder,
    super.key,
  });

  /// App-owned navigator observed by this view.
  final MuseIntentNavigator navigator;

  /// Trusted terminal renderer.
  final MuseNoirRenderer renderer;

  /// Optional initial-loading presentation.
  final MuseNoirLoadingBuilder? loadingBuilder;

  /// Optional typed failure presentation.
  final MuseNoirErrorBuilder? errorBuilder;

  /// Optional unmatched-route presentation.
  final MuseNoirNotFoundBuilder? notFoundBuilder;

  @override
  State<MuseNoirView> createState() => _MuseNoirViewState();
}

final class _MuseNoirViewState extends State<MuseNoirView> {
  MuseActivation? _current;
  MuseActivation? _shownActivation;
  MuseSurface? _shownSurface;
  MuseNoirRenderer? _shownRenderer;
  VoidCallback? _stopObserving;
  VoidCallback? _stopObservingShown;
  VoidCallback? _stopObservingNotFound;

  @override
  void initState() {
    super.initState();
    widget.navigator.currentListenable.addListener(_navigationChanged);
    _observeNotFound();
    _selectCurrent();
  }

  @override
  void didUpdateWidget(MuseNoirView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.navigator, widget.navigator)) {
      oldWidget.navigator.currentListenable.removeListener(_navigationChanged);
      widget.navigator.currentListenable.addListener(_navigationChanged);
      _observeNotFound();
      _clearSurface();
      _selectCurrent();
    } else if (!identical(oldWidget.renderer, widget.renderer)) {
      _refreshSurface();
    }
  }

  void _observeNotFound() {
    _stopObservingNotFound?.call();
    _stopObservingNotFound = museNoirObserveNotFound(
      widget.navigator,
      () => setState(() {}),
    );
  }

  void _navigationChanged() => setState(_selectCurrent);

  void _selectCurrent() {
    _stopObserving?.call();
    _current = widget.navigator.current;
    final current = _current;
    _stopObserving = current == null
        ? null
        : museNoirObserveActivation(current, _changed);
    _refreshSurface();
    _observeShown();
  }

  void _observeShown() {
    _stopObservingShown?.call();
    final shown = _shownActivation;
    _stopObservingShown = shown == null || identical(shown, _current)
        ? null
        : museNoirObserveActivation(shown, _changed);
  }

  void _changed() => setState(() {
    _refreshSurface();
    _observeShown();
  });

  void _refreshSurface() {
    final current = _current;
    if (current == null ||
        current.status.value == MuseActivationStatus.disposed) {
      _clearSurface();
      return;
    }
    final surface = current.surface;
    if (surface != null) {
      _shownActivation = current;
      _shownSurface = surface;
      _shownRenderer = widget.renderer;
      return;
    }
    if (current.status.value == MuseActivationStatus.generating &&
        _shownActivation != null &&
        _shownActivation!.status.value != MuseActivationStatus.disposed) {
      _shownRenderer = widget.renderer;
      return;
    }
    _clearSurface();
  }

  void _clearSurface() {
    _shownActivation = null;
    _shownSurface = null;
    _shownRenderer = null;
  }

  @override
  void dispose() {
    widget.navigator.currentListenable.removeListener(_navigationChanged);
    _stopObserving?.call();
    _stopObservingShown?.call();
    _stopObservingNotFound?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notFoundPath = museNoirNotFoundPath(widget.navigator);
    if (notFoundPath != null) {
      return widget.notFoundBuilder?.call(context, notFoundPath) ??
          const Text('Screen not found.');
    }
    final surface = _shownSurface;
    if (surface != null) {
      return MuseNoirSurfaceView(
        key: ObjectKey<MuseActivation>(_shownActivation!),
        activation: _shownActivation!,
        surface: surface,
        renderer: _shownRenderer!,
        error: _error,
      );
    }
    final failure = _current?.failure;
    if (failure != null) return _error(context, failure);
    if (_current?.status.value == MuseActivationStatus.ready ||
        _current?.status.value == MuseActivationStatus.disposed) {
      return const SizedBox.shrink();
    }
    return widget.loadingBuilder?.call(context) ??
        const Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 1,
          children: <Widget>[Spinner(), Text('Generating surface...')],
        );
  }

  Widget _error(BuildContext context, MuseFailure failure) =>
      widget.errorBuilder?.call(context, failure) ??
      Text(
        'Unable to display this screen.',
        style: TextStyle(
          color: Theme.of(context).danger,
          fontWeight: FontWeight.bold,
        ),
      );
}
