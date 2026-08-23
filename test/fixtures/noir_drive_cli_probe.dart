import 'package:noir/noir.dart';

void main() => runTuiApp(const _Probe());

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  var _count = 0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text('COUNT $_count'),
      Button(
        key: const ValueKey<String>('increment'),
        label: 'ADD',
        autofocus: true,
        onPressed: () => setState(() => _count++),
      ),
    ],
  );
}
