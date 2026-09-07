import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class MarkerGenerator {
  static Future<Uint8List?> createCustomMarkerBitmap(String imagePath) async {
    if (imagePath.isEmpty) return null;
    
    try {
      Uint8List? bytes;
      
      // Handle Network URL
      if (imagePath.startsWith('http')) {
        final cacheDir = await getTemporaryDirectory();
        final fileName = 'marker_cache_${imagePath.hashCode}.png';
        final file = File(path.join(cacheDir.path, fileName));

        if (await file.exists()) {
          bytes = await file.readAsBytes();
        } else {
          try {
            final Uri uri = Uri.parse(imagePath);
            final HttpClientRequest request = await HttpClient().getUrl(uri);
            final HttpClientResponse response = await request.close();
            if (response.statusCode == 200) {
              final List<int> imageBytes = [];
              await response.forEach((chunk) => imageBytes.addAll(chunk));
              bytes = Uint8List.fromList(imageBytes);
              
              // Save to cache
              await file.writeAsBytes(bytes);
            }
          } catch (e) {
            debugPrint("Error downloading image for marker: $e");
          }
        }
      } else {
        // Handle Local File
        final File file = File(imagePath);
        if (await file.exists()) {
          bytes = await file.readAsBytes();
        }
      }

      if (bytes == null) return null;

      final int size = 180;
      final double radius = size / 2;
      final double borderWidth = 8.0;

      final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(pictureRecorder);
      
      final Paint paint = Paint()..color = Colors.white;
      final Paint borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth;
      
      // No shadow to prevent black rendering issues on Globe
      // canvas.drawCircle(Offset(radius, radius + 4), radius, shadowPaint);

      // Draw Circle Background (White)
      canvas.drawCircle(Offset(radius, radius), radius, paint);

      // Load Image
      final ui.Codec codec = await ui.instantiateImageCodec(bytes, targetWidth: size, targetHeight: size);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image image = frameInfo.image;
      
      canvas.save();
      final double imageRadius = radius - borderWidth;
      final Path clipPath = Path()..addOval(Rect.fromCircle(center: Offset(radius, radius), radius: imageRadius));
      canvas.clipPath(clipPath);
      
      paintImage(
        canvas: canvas, 
        rect: Rect.fromCircle(center: Offset(radius, radius), radius: imageRadius), 
        image: image,
        fit: BoxFit.cover,
      );
      
      canvas.restore();
      canvas.drawCircle(Offset(radius, radius), radius - borderWidth/2, borderPaint);

      final ui.Image markerAsImage = await pictureRecorder.endRecording().toImage(size, size);
      final ByteData? byteData = await markerAsImage.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();

    } catch (e) {
      debugPrint("Error generating marker: $e");
      return null;
    }
  }

  static Future<Uint8List> createDefaultMarkerBitmap(Color color) async {
    final int size = 120;
    final double radius = size / 2;

    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    
    final Paint paint = Paint()..color = color;
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;
    
    // No shadow
    // canvas.drawCircle(Offset(radius, radius + 4), radius - 4, shadowPaint);

    // Draw Circle
    canvas.drawCircle(Offset(radius, radius), radius - 6, paint);
    canvas.drawCircle(Offset(radius, radius), radius - 6, borderPaint);

    final ui.Image markerAsImage = await pictureRecorder.endRecording().toImage(size, size);
    final ByteData? byteData = await markerAsImage.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
