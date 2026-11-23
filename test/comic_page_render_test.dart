import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/formats/album_comic_source.dart';
import 'package:manhua_reader/formats/archive_comic_source.dart';
import 'package:manhua_reader/formats/comic_page_crop.dart';
import 'package:manhua_reader/formats/comic_source.dart';
import 'package:manhua_reader/formats/mobi/mobi_book.dart';
import 'package:manhua_reader/formats/mobi_comic_source.dart';
import 'package:manhua_reader/formats/page_raster.dart';
import 'package:manhua_reader/formats/pdf_comic_source.dart';
import 'package:manhua_reader/models/toc_entry.dart';
import 'package:manhua_reader/widgets/comic_page_image.dart';
import 'package:manhua_reader/widgets/paper_curl.dart';
import 'package:manhua_reader/widgets/paper_page_view.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('crops narrow white, black, and transparent borders with a guard', () {
    for (final (border, body) in [
      (Colors.white, Colors.black),
      (Colors.black, Colors.white),
      (Colors.transparent, Colors.blue),
    ]) {
      expect(
        _detect(
          (x, y) => x < 10 || x >= 90 || y < 8 || y >= 92 ? border : body,
        ),
        const Rect.fromLTRB(0.07, 0.05, 0.93, 0.95),
      );
    }
  });

  test('keeps blank pages, broad margins, and marks touching the edge', () {
    expect(_detect((x, y) => Colors.white), ComicPageCropController.fullPage);
    expect(
      _detect((x, y) => x < 18 || x >= 82 ? Colors.white : Colors.black),
      ComicPageCropController.fullPage,
    );
    expect(
      _detect(
        (x, y) => x >= 10 || (x == 0 && y == 50) ? Colors.black : Colors.white,
      ),
      ComicPageCropController.fullPage,
    );
  });

  test('caps both pixel count and texture edge', () {
    final square = fitPageRasterSize(const Size(1, 1), const Size(9000, 9000));
    expect(square.width * square.height, lessThanOrEqualTo(8 * 1024 * 1024));
    expect(square.aspectRatio, 1);
    final long = fitPageRasterSize(const Size(1, 8), const Size(9000, 9000));
    expect(long, const Size(512, 4096));
  });

  test(
    'PDF, CBZ, album, and MOBI render larger bitmaps for larger targets',
    () async {
      final temp = await Directory.systemTemp.createTemp('comic_page_render_');
      addTearDown(() => temp.delete(recursive: true));
      final raster = _drawPage(400, 600);
      final data = await raster.toByteData(format: ui.ImageByteFormat.png);
      raster.dispose();
      final png = Uint8List.sublistView(data!);
      final album = Directory('${temp.path}/album')..createSync();
      await File('${album.path}/01.png').writeAsBytes(png);
      final archive = Archive()..add(ArchiveFile.bytes('01.png', png));
      final cbz = await File('${temp.path}/book.cbz')
          .writeAsBytes(ZipEncoder().encodeBytes(archive));
      final mobi = await File('${temp.path}/book.mobi')
          .writeAsBytes(_mobi(png));
      for (final source in <ComicSource>[
        await AlbumComicSource.open(album.path),
        await ArchiveComicSource.open(cbz.path),
        MobiComicSource(await MobiBook.open(mobi.path)),
      ]) {
        addTearDown(source.dispose);
        await _expectRenderAndCrop(source, nativeSize: const Size(400, 600));
      }

      Pdfrx.cacheDirectoryPath ??= temp.path;
      await pdfrxFlutterInitialize();
      final pdf = PdfComicSource(await PdfDocument.openData(_pdf()));
      addTearDown(pdf.dispose);
      await _expectRenderAndCrop(pdf, nativeSize: const Size(800, 1200));
    },
  );

  testWidgets(
    'zoom coalesces requests and keeps layout and the last valid image',
    (tester) async {
      final source = _ControlledSource();
      final transform = TransformationController();
      final images = <(int, int)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 180,
              height: 270,
              child: PageRenderScale(
                controller: transform,
                child: ComicPageImage(
                  source: source,
                  index: 0,
                  onImage: (image) => images.add((image.width, image.height)),
                ),
              ),
            ),
          ),
        ),
      );

      final page = find.byType(ComicPageImage);
      final originalSize = tester.getSize(page);
      final first = source.requests.single;
      first.completer.complete(
        _drawPage(first.size.width.toInt(), first.size.height.toInt()),
      );
      await tester.pump();
      final base = images.last;

      transform.value = Matrix4.diagonal3Values(2, 2, 1);
      await tester.pump(const Duration(milliseconds: 120));
      final pending = source.requests.last;
      expect(pending.size.width, greaterThan(first.size.width));
      expect(images.last, base);

      transform.value = Matrix4.diagonal3Values(3, 3, 1);
      await tester.pump(const Duration(milliseconds: 120));
      expect(source.requests, hasLength(2));
      final stale = _drawPage(
        pending.size.width.toInt(),
        pending.size.height.toInt(),
      );
      pending.completer.complete(stale);
      await tester.pump();
      expect(stale.debugDisposed, isTrue);
      expect(images.last, base);
      final latest = source.requests.last;
      expect(latest.size.width, greaterThan(pending.size.width));
      latest.completer.complete(
        _drawPage(latest.size.width.toInt(), latest.size.height.toInt()),
      );
      await tester.pumpAndSettle();
      expect(images.last, (
        latest.size.width.toInt(),
        latest.size.height.toInt(),
      ));
      expect(tester.getSize(page), originalSize);

      await tester.pumpWidget(const SizedBox.shrink());
      transform.dispose();
    },
  );

  testWidgets(
    'paper curl uses the same cropped aspect and source pixels as the page',
    (tester) async {
      final source = _ControlledSource();
      final controller = PageController();
      final crop = ComicPageCropController(source);
      for (var page = 0; page < source.pageCount; page++) {
        await tester.runAsync(() async {
          final changed = Completer<void>();
          void listener() => changed.complete();
          crop.addListener(listener);
          final image = _drawPage(120, 180);
          crop.inspectPage(page, image);
          image.dispose();
          await changed.future.timeout(const Duration(seconds: 5));
          crop.removeListener(listener);
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          home: PaperPageView(
            controller: controller,
            source: source,
            rightToLeft: false,
            background: Colors.black,
            cropController: crop,
            wrapPage: (child, onZoomChanged) => child,
            onSettled: (_) {},
          ),
        ),
      );
      for (final request in source.requests) {
        request.completer.complete(
          _drawPage(request.size.width.toInt(), request.size.height.toInt()),
        );
      }
      await tester.pumpAndSettle();
      final pageView = find.byType(PaperPageView);
      final viewport = tester.getSize(pageView);
      final animation = controller.animateToPage(
        1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.linear,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<PaperCurlPainter>()
          .single;
      final turn = painter.readTurn(viewport)!;
      for (final sheet in [...turn.outgoing, ...turn.incoming]) {
        expect(
          sheet.rect.size.aspectRatio,
          closeTo(crop.pageSize(0).aspectRatio, 0.001),
        );
        expect(
          sheet.imageRect.size.aspectRatio,
          closeTo(sheet.rect.size.aspectRatio, 0.01),
        );
        expect(
          sheet.imageRect.left,
          closeTo(crop.boundsFor(0).left * sheet.image.width, 0.001),
        );
        expect(sheet.imageRect.left, greaterThan(0));
      }
      await tester.pumpAndSettle();
      await animation;
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      crop.dispose();
    },
  );
}

Rect _detect(Color Function(int x, int y) sample) {
  final data = ByteData(100 * 100 * 4);
  for (var y = 0; y < 100; y++) {
    for (var x = 0; x < 100; x++) {
      final argb = sample(x, y).toARGB32();
      data.setUint32((y * 100 + x) * 4, (argb << 8) | (argb >> 24));
    }
  }
  return detectComicBorder(data, 100, 100);
}

Future<void> _expectRenderAndCrop(
  ComicSource source, {
  required Size nativeSize,
}) async {
  final renderer = source as ComicPageRenderer;
  final preview = await renderer.renderPageImage(0, const Size(120, 180));
  addTearDown(preview.dispose);
  expect(
    Size(preview.width.toDouble(), preview.height.toDouble()),
    const Size(120, 180),
  );
  final zoomed = await renderer.renderPageImage(0, const Size(800, 1200));
  addTearDown(zoomed.dispose);
  expect(Size(zoomed.width.toDouble(), zoomed.height.toDouble()), nativeSize);

  final crop = ComicPageCropController(source);
  addTearDown(crop.dispose);
  final changed = Completer<void>();
  crop.addListener(() => changed.complete());
  crop.inspectPage(0, preview);
  await changed.future.timeout(const Duration(seconds: 5));
  expect(crop.boundsFor(0).left, greaterThan(0));
  expect(
    crop.pageSize(0).aspectRatio,
    lessThan(source.pageSize(0).aspectRatio),
  );
}

ui.Image _drawPage(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);
  canvas.drawRect(
    Rect.fromLTRB(width * 0.1, height * 0.06, width * 0.9, height * 0.94),
    Paint()..color = Colors.blue,
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  return image;
}

Uint8List _mobi(Uint8List png) {
  const firstRecord = 94;
  const imageRecord = firstRecord + 24;
  final bytes = Uint8List(imageRecord + png.length);
  final header = ByteData.sublistView(bytes);
  bytes.setRange(60, 64, 'BOOK'.codeUnits);
  header.setUint16(76, 2);
  header.setUint32(78, firstRecord);
  header.setUint32(86, imageRecord);
  bytes.setRange(firstRecord + 16, firstRecord + 20, 'MOBI'.codeUnits);
  bytes.setRange(imageRecord, bytes.length, png);
  return bytes;
}

Uint8List _pdf() {
  const stream = '0 0 1 rg 40 36 320 528 re f\n';
  final pdf = StringBuffer('%PDF-1.4\n');
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 600] /Contents 4 0 R >>',
    '<< /Length ${stream.length} >>\nstream\n${stream}endstream',
  ];
  final offsets = <int>[];
  for (final (index, object) in objects.indexed) {
    offsets.add(pdf.length);
    pdf.write('${index + 1} 0 obj\n$object\nendobj\n');
  }
  final crossRef = pdf.length;
  pdf.write('xref\n0 5\n0000000000 65535 f \n');
  for (final offset in offsets) {
    pdf.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  pdf.write(
    'trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n$crossRef\n%%EOF\n',
  );
  return Uint8List.fromList(pdf.toString().codeUnits);
}

class _ControlledSource extends ComicSource implements ComicPageRenderer {
  final requests = <({Size size, Completer<ui.Image> completer})>[];

  @override
  Future<ui.Image> renderPageImage(int index, Size targetSize) {
    final completer = Completer<ui.Image>();
    requests.add((size: targetSize, completer: completer));
    return completer.future;
  }

  @override
  int get pageCount => 2;

  @override
  Size pageSize(int index) => const Size(120, 180);

  @override
  Widget buildPage(
    BuildContext context,
    int index, {
    ValueChanged<ui.Image>? onImage,
  }) => ComicPageImage(source: this, index: index, onImage: onImage);

  @override
  Widget buildThumbnail(BuildContext context, int index) =>
      const SizedBox.shrink();

  @override
  Future<List<TocEntry>> loadToc() async => [];

  @override
  Future<void> dispose() async {}
}
