import 'dart:convert';
import 'dart:io';

void main() {
  final content = utf8.encode('BT /F1 24 Tf 50 150 Td (Encrypted PDF) Tj ET');
  final objects = <List<int>>[
    utf8.encode('<< /Type /Catalog /Pages 2 0 R >>'),
    utf8.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
    utf8.encode(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] '
      '/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    ),
    <int>[
      ...utf8.encode('<< /Length ${content.length} >>\nstream\n'),
      ...content,
      ...utf8.encode('\nendstream'),
    ],
    utf8.encode(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    ),
  ];

  final out = BytesBuilder(copy: false);
  out.add(utf8.encode('%PDF-1.4\n'));
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.add(utf8.encode('${i + 1} 0 obj\n'));
    out.add(objects[i]);
    out.add(utf8.encode('\nendobj\n'));
  }

  final xrefOffset = out.length;
  out.add(utf8.encode('xref\n0 ${objects.length + 1}\n'));
  out.add(utf8.encode('0000000000 65535 f \n'));
  for (final offset in offsets.skip(1)) {
    out.add(
      utf8.encode('${offset.toString().padLeft(10, '0')} 00000 n \n'),
    );
  }
  out.add(
    utf8.encode(
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xrefOffset\n%%EOF\n',
    ),
  );

  final file = File('build/small_plain.pdf');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(out.takeBytes());
  stdout.writeln('wrote ${file.path} (${file.lengthSync()} bytes)');
}
