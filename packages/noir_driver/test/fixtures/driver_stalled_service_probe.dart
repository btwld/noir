import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

// A responsive VM-service peer with two deliberately pending RPCs. It exits
// normally when asked; deadline tests never need to kill a stalled process.
void main(List<String> arguments) {
  final keepAlive = Timer.periodic(const Duration(seconds: 1), (_) {});
  var infoRequests = 0;
  registerExtension('ext.noir.driver.info', (_, _) async {
    if (infoRequests++ == 0 && arguments.contains('--delayed-ready')) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return ServiceExtensionResponse.result(
      jsonEncode({'type': 'Success', 'width': 80, 'height': 24, 'frames': 1}),
    );
  });
  for (final method in ['waitStable', 'sendBytes']) {
    registerExtension(
      'ext.noir.driver.$method',
      (_, _) => Completer<ServiceExtensionResponse>().future,
    );
  }
  registerExtension('ext.noir.driver.quit', (_, _) async {
    keepAlive.cancel();
    Timer(const Duration(milliseconds: 100), () => exit(0));
    return ServiceExtensionResponse.result('{"type":"Success"}');
  });
}
