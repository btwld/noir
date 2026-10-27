import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

// A responsive VM-service peer with deliberately pending RPCs. Shutdown tests
// can also leave it alive after acknowledging quit, or reject the request.
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
    if (arguments.contains('--fail-quit')) {
      return ServiceExtensionResponse.error(-32000, 'quit rejected');
    }
    if (arguments.contains('--ignore-quit')) {
      stdout.writeln('quit acknowledged');
      return ServiceExtensionResponse.result('{"type":"Success"}');
    }
    keepAlive.cancel();
    Timer(const Duration(milliseconds: 100), () => exit(0));
    return ServiceExtensionResponse.result('{"type":"Success"}');
  });
}
