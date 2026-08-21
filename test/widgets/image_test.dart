import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart' show RenderImage;
import 'package:noir/src/core/terminal_image.dart'
    show maxTerminalImageEncodedBytes;
import 'package:test/test.dart';

import '../helpers/test_element_host.dart';

void main() {
  test('borrowed images remain live after the widget unmounts', () {
    final image = TerminalImage.fromRgba(
      Uint8List.fromList(<int>[255, 0, 0, 255]),
      pixelWidth: 1,
      pixelHeight: 1,
      rowStride: 4,
    );
    final host = TestElementHost()..mount(Image(image: image));

    host
      ..pumpFrame()
      ..dispose();

    expect(image.info.pixelWidth, 1);
    image.dispose();
  });

  test(
    'named sources dispose their successfully decoded image on unmount',
    () async {
      final loaded = Completer<TerminalImage>();
      final host = TestElementHost()
        ..mount(
          Image.rgba(
            Uint8List.fromList(<int>[255, 0, 0, 255]),
            pixelWidth: 1,
            pixelHeight: 1,
            rowStride: 4,
            onLoad: loaded.complete,
          ),
        );
      final image = await loaded.future;
      host
        ..pumpFrame()
        ..dispose();

      expect(() => image.info, throwsStateError);
    },
  );

  test('equal snapshotted RGBA sources do not reload', () async {
    final key = GlobalKey<_ImageParentState>();
    var loads = 0;
    final host = TestElementHost()
      ..mount(_ImageParent(key: key, onLoad: (_) => loads++));
    await Future<void>.delayed(Duration.zero);
    host.pumpFrame();

    key.currentState!.rebuild();
    host.pumpFrame();
    await Future<void>.delayed(Duration.zero);

    expect(loads, 1);
    host.dispose();
  });

  test('network rejects non-HTTP schemes with a typed error', () async {
    final failed = Completer<Object>();
    final host = TestElementHost()
      ..mount(
        Image.network(
          Uri.parse('file:///tmp/image.png'),
          onError: (error, _) => failed.complete(error),
        ),
      );

    final error = await failed.future;

    expect(
      error,
      isA<ImageLoadException>().having(
        (value) => value.code,
        'code',
        ImageLoadErrorCode.unsupportedUrlScheme,
      ),
    );
    host.dispose();
  });

  test('file read failures use the typed file error', () async {
    final failed = Completer<Object>();
    final host = TestElementHost()
      ..mount(
        Image.file(
          'test/fixtures/does-not-exist.png',
          onError: (error, _) => failed.complete(error),
        ),
      );

    expect(
      await failed.future,
      isA<ImageLoadException>().having(
        (value) => value.code,
        'code',
        ImageLoadErrorCode.fileRead,
      ),
    );
    host.dispose();
  });

  test('network snapshots headers and reports non-success status', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final receivedHeader = Completer<String?>();
    server.listen((request) async {
      receivedHeader.complete(request.headers.value('x-image-token'));
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    final headers = <String, String>{'x-image-token': 'snapshot'};
    final failed = Completer<Object>();
    final widget = Image.network(
      Uri.parse('http://127.0.0.1:${server.port}/missing'),
      headers: headers,
      onError: (error, _) => failed.complete(error),
    );
    headers['x-image-token'] = 'mutated';
    final host = TestElementHost()..mount(widget);

    final error = await failed.future;

    expect(await receivedHeader.future, 'snapshot');
    expect(
      error,
      isA<ImageLoadException>()
          .having((value) => value.code, 'code', ImageLoadErrorCode.httpStatus)
          .having((value) => value.status, 'status', HttpStatus.notFound),
    );
    host.dispose();
  });

  test('replacement failure retains the last successful decoded image', () async {
    final loaded = Completer<TerminalImage>();
    final failed = Completer<Object>();
    final key = GlobalKey<_FileImageHarnessState>();
    final host = TestElementHost()
      ..mount(
        _FileImageHarness(
          key: key,
          path:
              'external/opentui/packages/core/src/tests/fixtures/images/rgba.png',
          onLoad: loaded.complete,
          onError: failed.complete,
        ),
      );
    final image = await loaded.future;
    host.pumpFrame();
    expect(host.renderObject, isA<RenderImage>());

    key.currentState!.replace('test/fixtures/does-not-exist.png');
    host.pumpFrame();
    expect(await failed.future, isA<ImageLoadException>());
    host.pumpFrame();

    expect((host.renderObject! as RenderImage).image, same(image));
    expect(image.info.pixelWidth, greaterThan(0));
    host.dispose();
    expect(() => image.info, throwsStateError);
  });

  test('source replacement cancels stale network callbacks', () async {
    final fixture = await File(
      'external/opentui/packages/core/src/tests/fixtures/images/rgba.png',
    ).readAsBytes();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final slowRequest = Completer<HttpRequest>();
    server.listen((request) async {
      if (request.uri.path == '/slow') {
        slowRequest.complete(request);
        return;
      }
      request.response.add(fixture);
      await request.response.close();
    });
    final loads = <String>[];
    final key = GlobalKey<_NetworkImageHarnessState>();
    final host = TestElementHost()
      ..mount(
        _NetworkImageHarness(
          key: key,
          uri: Uri.parse('http://127.0.0.1:${server.port}/slow'),
          loads: loads,
        ),
      );
    await slowRequest.future;

    key.currentState!.replace(
      Uri.parse('http://127.0.0.1:${server.port}/fast'),
    );
    host.pumpFrame();
    for (var attempt = 0; attempt < 20 && loads.isEmpty; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(loads, <String>['/fast']);
    host.dispose();
  });

  test('streamed file and HTTP metadata reject the 64 MiB limit', () async {
    final directory = await Directory.systemTemp.createTemp(
      'noir_image_limit_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final oversized = File('${directory.path}/oversized.png');
    final handle = await oversized.open(mode: FileMode.write);
    await handle.truncate(maxTerminalImageEncodedBytes + 1);
    await handle.close();
    final fileFailure = Completer<Object>();
    final fileHost = TestElementHost()
      ..mount(
        Image.file(
          oversized.path,
          onError: (error, stackTrace) => fileFailure.complete(error),
        ),
      );
    expect(
      await fileFailure.future,
      isA<TerminalImageException>().having(
        (error) => error.code,
        'code',
        TerminalImageErrorCode.memoryLimit,
      ),
    );
    fileHost.dispose();

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.contentLength = maxTerminalImageEncodedBytes + 1;
      request.response.add(const <int>[0]);
      try {
        await request.response.close();
      } on Object {
        // The client intentionally closes after reading the oversized header.
      }
    });
    final networkFailure = Completer<Object>();
    final networkHost = TestElementHost()
      ..mount(
        Image.network(
          Uri.parse('http://127.0.0.1:${server.port}/oversized'),
          onError: (error, stackTrace) => networkFailure.complete(error),
        ),
      );
    expect(
      await networkFailure.future,
      isA<TerminalImageException>().having(
        (error) => error.code,
        'code',
        TerminalImageErrorCode.memoryLimit,
      ),
    );
    networkHost.dispose();
  });
}

final class _ImageParent extends StatefulWidget {
  const _ImageParent({required this.onLoad, super.key});

  final void Function(TerminalImage image) onLoad;

  @override
  State<_ImageParent> createState() => _ImageParentState();
}

final class _ImageParentState extends State<_ImageParent> {
  final pixels = Uint8List.fromList(<int>[0, 255, 0, 255]);

  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) => Image.rgba(
    pixels,
    pixelWidth: 1,
    pixelHeight: 1,
    rowStride: 4,
    onLoad: widget.onLoad,
  );
}

final class _FileImageHarness extends StatefulWidget {
  const _FileImageHarness({
    required this.path,
    required this.onLoad,
    required this.onError,
    super.key,
  });

  final String path;
  final void Function(TerminalImage image) onLoad;
  final void Function(Object error) onError;

  @override
  State<_FileImageHarness> createState() => _FileImageHarnessState();
}

final class _FileImageHarnessState extends State<_FileImageHarness> {
  late String path = widget.path;

  void replace(String value) => setState(() => path = value);

  @override
  Widget build(BuildContext context) => Image.file(
    path,
    onLoad: widget.onLoad,
    onError: (error, stackTrace) => widget.onError(error),
  );
}

final class _NetworkImageHarness extends StatefulWidget {
  const _NetworkImageHarness({
    required this.uri,
    required this.loads,
    super.key,
  });

  final Uri uri;
  final List<String> loads;

  @override
  State<_NetworkImageHarness> createState() => _NetworkImageHarnessState();
}

final class _NetworkImageHarnessState extends State<_NetworkImageHarness> {
  late Uri uri = widget.uri;

  void replace(Uri value) => setState(() => uri = value);

  @override
  Widget build(BuildContext context) =>
      Image.network(uri, onLoad: (_) => widget.loads.add(uri.path));
}
