import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/pub_search/package_detail.dart';
import '../../example/pub_search/theme.dart';
import '../example/pub_search_test_data.dart';
import '../helpers/golden_testing.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void main() {
  group('Pub search golden', () {
    late GoldenTester tester;
    late ScrollController scrollController;
    late FocusNode scrollFocusNode;

    setUpAll(() {
      tester = GoldenTester(width: 100, height: 32);
    });

    setUp(() {
      scrollController = ScrollController();
      scrollFocusNode = FocusNode(debugLabel: 'golden pub detail');
    });

    tearDown(() {
      scrollController.dispose();
      scrollFocusNode.dispose();
    });

    tearDownAll(() {
      tester.dispose();
    });

    test('quiet tabs overview', () async {
      await tester.expectGolden(
        Theme(
          data: pubTheme,
          child: PubPackageDetail(
            package: examplePubPackage,
            activeTab: PackageDetailTab.overview,
            onTabSelected: (_) {},
            scrollController: scrollController,
            scrollFocusNode: scrollFocusNode,
          ),
        ),
        'pub_search_detail',
        updateGoldens: _updateGoldens,
      );
    });
  });
}
