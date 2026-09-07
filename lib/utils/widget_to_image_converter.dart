import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';

class WidgetToImageConverter {
  /// Converts a widget to a PNG image file saved in cache directory
  /// Returns the file path of the generated image
  static Future<String?> convertWidgetToImage({
    required Widget widget,
    required String filename,
    Size size = const Size(800, 400),
  }) async {
    try {
      // Create screenshot controller
      final screenshotController = ScreenshotController();
      
      // Capture widget as image
      final imageBytes = await screenshotController.captureFromWidget(
        Material(
          color: Colors.white,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: widget,
          ),
        ),
        pixelRatio: 2.0,
      );

      // Save to cache directory
      final Directory cacheDir = await getTemporaryDirectory();
      final String filePath = '${cacheDir.path}/$filename';
      final File file = File(filePath);

      await file.writeAsBytes(imageBytes);
      debugPrint('Widget converted to image: $filePath (${imageBytes.length} bytes)');

      return filePath;
    } catch (e, stackTrace) {
      debugPrint('Error converting widget to image: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Deletes an image file if it exists
  static Future<void> deleteImage(String? filePath) async {
    if (filePath != null && filePath.isNotEmpty) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          debugPrint('Deleted old image: $filePath');
        }
      } catch (e) {
        debugPrint('Error deleting image: $e');
      }
    }
  }
}
