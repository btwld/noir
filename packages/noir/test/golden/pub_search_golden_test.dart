import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/src/pub_search/package_detail.dart';
import '../../example/src/pub_search/theme.dart';
import '../example/pub_search_test_data.dart';
import '../helpers/golden_testing.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void main() {
  group('Pub search golden', () {
    late GoldenTester wideTester;
    late GoldenTester narrowTester;
    late ScrollController scrollController;
    late FocusNode scrollFocusNode;

    setUpAll(() {
      wideTester = GoldenTester(width: 100, height: 32);
      narrowTester = GoldenTester();
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
      wideTester.dispose();
      narrowTester.dispose();
    });

    Widget detail(PackageDetailTab tab) => Theme(
      data: pubTheme,
      child: PubPackageDetail(
        package: examplePubPackage,
        activeTab: tab,
        onTabSelected: (_) {},
        scrollController: scrollController,
        scrollFocusNode: scrollFocusNode,
      ),
    );

    test('wide overview pairs compact summary groups', () async {
      await wideTester.expectGolden(
        detail(PackageDetailTab.overview),
        'pub_search_detail',
        updateGoldens: _updateGoldens,
      );
    });

    test('narrow overview stacks compact summary groups', () async {
      await narrowTester.expectGolden(
        detail(PackageDetailTab.overview),
        'pub_search_detail_overview_narrow',
        updateGoldens: _updateGoldens,
      );
    });

    test('versions show a friendly release ledger', () async {
      await wideTester.expectGolden(
        detail(PackageDetailTab.versions),
        'pub_search_detail_versions',
        updateGoldens: _updateGoldens,
      );
    });

    test('dependencies pair primary groups', () async {
      await wideTester.expectGolden(
        detail(PackageDetailTab.dependencies),
        'pub_search_detail_dependencies',
        updateGoldens: _updateGoldens,
      );
    });

    test('health prioritizes summaries and rendered reports', () async {
      await wideTester.expectGolden(
        detail(PackageDetailTab.health),
        'pub_search_detail_health',
        updateGoldens: _updateGoldens,
      );
    });
  });
}
