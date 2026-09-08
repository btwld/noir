/// Reusable lifecycle hooks and Signals reactive state for Noir.
///
/// This is the one authoring entrypoint. Import it together with
/// `package:noir/noir.dart`:
///
/// ```dart
/// import 'package:noir/noir.dart';
/// import 'package:noir_signals/noir_signals.dart';
/// ```
///
/// It exports three groups of declarations:
///
/// - the hook runtime and the built-in resource hooks, which Noir released
///   through its own `hooks.dart` library before this package existed;
/// - the signal hooks and [SignalValueBuilder], which connect Signals to
///   Noir's rebuild scheduling;
/// - the upstream `signals_core` primitives an application needs to declare a
///   model — [Signal], [Computed], [signal], [computed], [effect], [batch],
///   and [untracked] among them.
///
/// Application models stay ordinary Signals code. Import
/// `package:signals_core/signals_core.dart` directly when a model needs the
/// wider upstream surface.
library;

export 'package:signals_core/signals_core.dart'
    show
        Computed,
        ComputedOptions,
        EffectCallback,
        EffectCleanup,
        EffectOptions,
        ReadonlySignal,
        ReadonlySignalOptions,
        Signal,
        SignalEffectException,
        SignalOptions,
        SignalsError,
        SignalsReadAfterDisposeError,
        SignalsWriteAfterDisposeError,
        batch,
        computed,
        effect,
        signal,
        untracked;

export 'src/hooks/animation.dart'
    show useAnimation, useAnimationController, useAnimationStatus;
export 'src/hooks/async.dart'
    show AsyncSnapshot, ConnectionState, useFuture, useStream;
export 'src/hooks/controllers.dart'
    show
        useFocusNode,
        useScrollController,
        useTextEditingController,
        useViewportController;
export 'src/hooks/framework.dart'
    show
        Hook,
        HookBuilder,
        HookState,
        HookWidget,
        HookWidgetBuilder,
        use,
        useContext,
        useTickerProvider;
export 'src/hooks/listenable.dart'
    show
        ValueEquality,
        useChangeNotifier,
        useListenable,
        useListenableSelector,
        useOnListenableChange,
        useValueListenable,
        useValueNotifier;
export 'src/hooks/primitives.dart'
    show
        Dispose,
        Effect,
        ObjectRef,
        Reducer,
        Store,
        useCallback,
        useDisposable,
        useEffect,
        useIsMounted,
        useMemoized,
        useOnDispose,
        usePrevious,
        useReducer,
        useRef,
        useState,
        useValueChanged;
export 'src/hooks/signals.dart'
    show useComputed, useSignal, useSignalEffect, useSignalValue;
export 'src/signal_value_builder.dart'
    show SignalValueBuilder, SignalValueWidgetBuilder;
