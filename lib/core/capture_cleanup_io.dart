import 'dart:io';

/// Only receives the temporary path returned by CameraController.takePicture.
Future<void> discardCapture(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}
