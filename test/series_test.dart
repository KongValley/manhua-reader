import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/utils/series.dart';

void main() {
  test('derives series from common volume suffixes', () {
    expect(deriveSeriesName('VOL.001', 'VOL.001.pdf'), 'VOL');
    expect(deriveSeriesName('海贼王 第12卷', '海贼王 第12卷.pdf'), '海贼王');
    expect(
      deriveSeriesName('One Piece v03', 'One Piece v03.mobi'),
      'One Piece',
    );
    expect(deriveSeriesName('海贼王 12', '海贼王 12.pdf'), '海贼王');
    expect(deriveSeriesName('One Piece (Vol.7)', 'x.pdf'), 'One Piece');
  });

  test('does not invent a series without a volume marker', () {
    expect(deriveSeriesName('海边的咖啡馆', '海边的咖啡馆.pdf'), isNull);
    expect(deriveSeriesName('第3卷', '第3卷.pdf'), isNull);
    expect(deriveSeriesName('2024', '2024.pdf'), isNull);
    expect(deriveSeriesName('', 'One Piece v01.mobi'), 'One Piece');
  });
}
