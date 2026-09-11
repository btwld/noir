import 'package:noir/noir.dart';
import 'package:noir_mcp_inspector/noir_mcp_inspector.dart';
import 'package:test/test.dart';

import '../../../test/helpers/tui_test_app.dart';

void main() {
  for (final kind in FormFieldKind.values) {
    test('a mounted $kind field accepts a new focus request once', () async {
      final node = FocusNode();
      final model = _model(kind);
      final key = GlobalKey<_FormHostState>();
      final app = createTuiTestApp(
        _FormHost(key: key, model: model, node: node),
      );
      try {
        app.pumpFrame();
        await Future<void>.delayed(Duration.zero);
        expect(node.isAttached, isTrue);
        expect(node.hasFocus, isFalse);

        key.currentState!.requestFieldFocus();
        app.pumpFrame();
        await Future<void>.delayed(Duration.zero);
        expect(node.hasPrimaryFocus, isTrue);

        // The request is an edge, not a reason to steal focus on every build.
        node.unfocus();
        key.currentState!.rebuildForm();
        app.pumpFrame();
        await Future<void>.delayed(Duration.zero);
        expect(node.hasFocus, isFalse);
      } finally {
        app.dispose();
        model.dispose();
        node.dispose();
      }
    });
  }

  test(
    'withdrawing a field focus request before dispatch cancels it',
    () async {
      final node = FocusNode();
      final model = _model(FormFieldKind.text);
      final key = GlobalKey<_FormHostState>();
      final app = createTuiTestApp(
        _FormHost(key: key, model: model, node: node),
      );
      try {
        app.pumpFrame();
        key.currentState!.requestFieldFocus();
        app.pumpFrame();
        key.currentState!.clearFieldFocus();
        app.pumpFrame();
        await Future<void>.delayed(Duration.zero);
        expect(node.hasFocus, isFalse);
      } finally {
        app.dispose();
        model.dispose();
        node.dispose();
      }
    },
  );

  test('removing a form before its focus request dispatches is safe', () async {
    final node = FocusNode();
    final model = _model(FormFieldKind.text);
    final key = GlobalKey<_FormHostState>();
    final app = createTuiTestApp(_FormHost(key: key, model: model, node: node));
    try {
      app.pumpFrame();
      key.currentState!.requestFieldFocus();
      app.pumpFrame();
      app.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(node.isAttached, isFalse);
      expect(node.hasFocus, isFalse);
    } finally {
      app.dispose();
      model.dispose();
      node.dispose();
    }
  });
}

FormModel _model(FormFieldKind kind) => FormModel(
  FormSpec([
    FormFieldSpec(
      name: 'value',
      kind: kind,
      isRequired: true,
      options: const ['first', 'second'],
    ),
  ]),
);

class _FormHost extends StatefulWidget {
  const _FormHost({required this.model, required this.node, super.key});

  final FormModel model;
  final FocusNode node;

  @override
  State<_FormHost> createState() => _FormHostState();
}

class _FormHostState extends State<_FormHost> {
  FocusNode? _request;

  void requestFieldFocus() => setState(() => _request = widget.node);

  void clearFieldFocus() => setState(() => _request = null);

  void rebuildForm() => setState(() {});

  @override
  Widget build(BuildContext context) => FormView(
    model: widget.model,
    focusNodeFor: (_) => widget.node,
    autofocusNode: _request,
    onChanged: () {},
  );
}
