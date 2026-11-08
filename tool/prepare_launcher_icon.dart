import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final source = img.decodePng(
    File('assets/images/tamaraw-logo.png').readAsBytesSync(),
  )!;
  final canvas = img.Image(width: 1024, height: 1024);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  final art = img.copyResize(
    source,
    width: source.width >= source.height ? 640 : null,
    height: source.height > source.width ? 640 : null,
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(
    canvas,
    art,
    dstX: (1024 - art.width) ~/ 2,
    dstY: (1024 - art.height) ~/ 2,
  );
  final output = File('assets/generated/launcher-icon.png');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(img.encodePng(canvas));
  // The original artwork is untouched; padding keeps it inside launcher masks.
}
