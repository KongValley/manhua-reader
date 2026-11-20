import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  final sample = File('test/VOL.001.pdf');
  final cache = Directory.systemTemp.createTempSync('manhua_pdf_test_');

  tearDownAll(() async {
    try {
      await cache.delete(recursive: true);
    } catch (_) {}
  });

  test(
    'opens the sample PDF and renders its first page',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      Pdfrx.cacheDirectoryPath ??= cache.path;
      await pdfrxFlutterInitialize();

      final document = await PdfDocument.openFile(sample.path);
      try {
        expect(document.pages.length, greaterThan(50));
        expect(await document.loadOutline(), isEmpty);

        final page = document.pages.first;
        final image = await page.render(
          fullWidth: 320,
          fullHeight: 320 * page.height / page.width,
        );
        expect(image, isNotNull);
        final rendered = await image!.createImage();
        try {
          expect(rendered.width, 320);
          expect(rendered.height, greaterThan(100));
          final pixels = await rendered.toByteData(
            format: ImageByteFormat.rawRgba,
          );
          expect(pixels, isNotNull);
          expect(pixels!.lengthInBytes, rendered.width * rendered.height * 4);
        } finally {
          rendered.dispose();
          image.dispose();
        }
      } finally {
        await document.dispose();
      }
    },
    skip: sample.existsSync() ? null : 'test/VOL.001.pdf is missing',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
