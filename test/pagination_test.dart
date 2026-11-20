import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/utils/pagination.dart';

void main() {
  test('pairs pages with a single cover', () {
    expect(buildSpreads(0), isEmpty);
    expect(buildSpreads(1), [
      [0],
    ]);
    expect(buildSpreads(2), [
      [0],
      [1],
    ]);
    expect(buildSpreads(3), [
      [0],
      [1, 2],
    ]);
    expect(buildSpreads(6), [
      [0],
      [1, 2],
      [3, 4],
      [5],
    ]);
  });

  test('maps pages to the spread that contains them', () {
    final spreads = buildSpreads(6);
    expect(spreadIndexForPage(spreads, 0), 0);
    expect(spreadIndexForPage(spreads, 1), 1);
    expect(spreadIndexForPage(spreads, 2), 1);
    expect(spreadIndexForPage(spreads, 3), 2);
    expect(spreadIndexForPage(spreads, 4), 2);
    expect(spreadIndexForPage(spreads, 5), 3);
  });
}
