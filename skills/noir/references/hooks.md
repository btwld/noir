# Noir hooks

Keep hook code declarative, ordered, and explicit about resource ownership.
Treat Noir's hook contracts as authoritative rather than assuming parity with
another hook library.

## Start from the canonical contract

Read `../../../packages/noir_signals/doc/hooks.md` completely before changing
hook behavior or
writing lifecycle-sensitive application code. Load only the complementary
guidance needed for the task:

- Screen composition and terminal visual review: `design.md`
- Buttons, focus, keyboard, and pointer input: `inputs-and-focus.md`
- Consumer and repository test strategy: `testing.md`
- Live capture and input: `../SKILL.md#see-and-drive-a-running-app-drive-mode`

Verify signatures in `package:noir_signals/noir_signals.dart` and a nearby
working example.
Do not import `package:noir/src/**`, `package:noir/noir_low_level.dart`, or
`package:noir/noir_ffi.dart` for hook application code.

## Workflow

1. Name the persistent value or external resource and its owner.
2. Choose the smallest built-in hook that owns or observes it.
3. Call hooks unconditionally at the top level of `build` or a top-level
   `use...` function, in the same order on every build.
4. Put user-driven mutations in input callbacks. Use effects only to acquire,
   synchronize, and release resources outside the widget declaration.
5. Keep the widget tree declarative and pass current values plus callbacks to
   smaller stateless views when that clarifies the state boundary.
6. Test the state transition, then add a focused lifecycle or interaction test
   only when mounting, input routing, layout, or paint is part of the promise.

## State and identity

- `useState<T>(initialValue)` owns and observes a `ValueNotifier<T>`. Read and
  assign `.value`; an assignment that changes equality requests a rebuild.
- `useValueNotifier` owns a notifier but does not observe it. Pair it with
  `useValueListenable` when the host must rebuild.
- Use `useMemoized` to retain futures, streams, or other identity-sensitive
  objects. Creating a new asynchronous source on every build restarts it.
- Use `useCallback` only when stable callback identity is itself required.
  Ordinary local event closures do not need memoization.
- Use the supplied focus, editing, scrolling, viewport, and animation hooks
  instead of recreating their ownership and disposal manually.
- Call hooks from top-level custom functions whose names begin with `use`.
  Never call them from branches, loops, events, effects, cleanup, or other
  lifecycle callbacks.

For a local interaction, prefer this complete state boundary:

```dart
class Counter extends HookWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) {
    final count = useState<int>(0);
    return Column(
      children: [
        Text('Count: ${count.value}'),
        Button(
          autofocus: true,
          label: '+ Add one',
          onPressed: () => count.value++,
        ),
      ],
    );
  }
}
```

## Effects and cleanup

`useEffect` and its cleanup run synchronously during the hook widget build.
Neither may synchronously request a hook rebuild. In particular, do not update
`useState`, an observed notifier, or ordinary state from an effect or cleanup.
The hook runtime rejects hook rebuild requests there so the build queue cannot
loop; it does not roll back a notifier value that was already assigned.

Use an effect when the widget must subscribe, start, or acquire something, and
return the matching cleanup. Supply stable keys for the resource identity.
State changes are valid later from timers, futures, streams, and input
callbacks, after the effect has returned. Use `useRef` for synchronous
bookkeeping that must not rebuild.

```dart
useEffect(() {
  final timer = Timer.periodic(interval, (_) => tick.value++);
  return timer.cancel;
}, <Object?>[interval]);
```

Effects without keys clean up and rerun on every build. An empty key list runs
once for the mounted hook slot. Key lists are snapshotted; key changes replace
only that slot. Owned hooks dispose in reverse call order and continue cleanup
after a failure before rethrowing the first error.

## Verification

Format and analyze hook application code. Exercise callback-driven state
directly where possible. For repository examples, use the existing contributor
harness named by the repository guide; for package consumers, use only public
application seams. Inspect a drive-mode capture at 80x24 for visual work—the
driver runs without a real TTY—and do not treat it as an assertion framework.
For an interactive hook example, capture the initial frame, send input, capture
the changed state, resize, and capture again. Confirm the retained hook state
survives the resize; use `capture --cells` when styles or cursor state matter.
