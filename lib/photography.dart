import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'export.dart';

const _photography = MethodChannel('tempus/photography');
const maxAlbumPhotoBytes = 64 * 1024 * 1024;

enum FilmLook {
  bronze('Бронза', [0.74, 13, .10, 6, 4, .14, 4, 9]),
  chestnut('Каштан', [0.52, 20, .14, 3, 6, .25, 6, 6]),
  archive('Архив', [0.38, 10, -.08, 15, 7, .20, 7, 10]),
  original('Оригинал', [1, 0, 0, 0, 0, 0, 0, 0]);

  const FilmLook(this.label, this.profile);
  final String label;
  final List<double> profile;

  List<double> preview(double strength) {
    final saturation = 1 - (1 - profile[0]) * strength;
    final contrast = 1 + profile[2] * strength * .56;
    final warm = profile[1] * strength * .70;
    final lift = profile[3] * strength * .55 + (1 - contrast) * 105;
    const luma = [.2126, .7152, .0722];
    return [
      for (var row = 0; row < 3; row++) ...[
        for (var column = 0; column < 3; column++)
          contrast *
              (column == row
                  ? saturation + (1 - saturation) * luma[column]
                  : (1 - saturation) * luma[column]),
        0,
        lift + warm * [1.0, .23, -.88][row],
      ],
      0,
      0,
      0,
      1,
      0,
    ];
  }
}

Future<Uint8List> developPhoto(
  File source,
  FilmLook look,
  double strength,
) async {
  if (look == FilmLook.original || strength == 0) return source.readAsBytes();
  final path = await _photography.invokeMethod<String>('develop', {
    'source': source.path,
    'profile': look.profile,
    'strength': strength,
  });
  if (path == null) {
    throw const FormatException('Processed photo is unavailable');
  }
  final result = File(path);
  try {
    return await result.readAsBytes();
  } finally {
    await removeTemporaryPhoto(result);
  }
}

Future<void> removeTemporaryPhoto(File file) async {
  try {
    await file.delete();
  } on FileSystemException {
    // A camera plugin may have removed its cached copy already.
  }
}

Future<bool> saveCameraPhoto(Uint8List bytes) async {
  final name = 'TEMPUS-${DateTime.now().millisecondsSinceEpoch}.jpg';
  final saved = await _photography.invokeMethod<bool>('saveToGallery', {
    'name': name,
    'image': bytes,
  });
  return saved == true || await saveFile(name, bytes) != null;
}

Future<Uint8List> makePhotoThumbnail(Uint8List photo) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(photo);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final width = descriptor.width;
      final height = descriptor.height;
      const maxEdge = 480;
      final codec = await descriptor.instantiateCodec(
        targetWidth: width >= height ? width.clamp(1, maxEdge) : null,
        targetHeight: height > width ? height.clamp(1, maxEdge) : null,
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final bytes = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (bytes == null) throw const FormatException('Invalid thumbnail');
          return bytes.buffer.asUint8List(
            bytes.offsetInBytes,
            bytes.lengthInBytes,
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

(int, int)? jpegDimensions(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) return null;
  var offset = 2;
  while (offset + 4 <= bytes.length && bytes[offset++] == 0xff) {
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset + 3 > bytes.length) break;
    final marker = bytes[offset++];
    if (marker == 0xda || marker == 0xd9) break;
    final length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) break;
    if (length >= 8 &&
        const {
          0xc0,
          0xc1,
          0xc2,
          0xc3,
          0xc5,
          0xc6,
          0xc7,
          0xc9,
          0xca,
          0xcb,
          0xcd,
          0xce,
          0xcf,
        }.contains(marker)) {
      final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      if (width > 0 && height > 0) return (width, height);
    }
    offset += length;
  }
  return null;
}
