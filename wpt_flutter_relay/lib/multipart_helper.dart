import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

class MultipartHelper {
  final String filename; // Filename provided at instantiation
  late final String boundary; // Boundary dynamically generated

  MultipartHelper(this.filename) {
    boundary = _generateBoundary(); // Initialize the boundary
  }

  // Method to generate a random boundary
  String _generateBoundary() {
    const length = 32; // Length of the random part of the boundary
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return 'FlutterBoundary-${List.generate(length, (index) => chars[random.nextInt(chars.length)]).join()}';
  }

  @override
  String toString() {
    return "Filename: $filename\nBoundary: $boundary";
  }

  Uint8List getPrefix() {
    var buffer = StringBuffer();
    buffer.write('--$boundary\r\n');
    buffer.write(
        'Content-Disposition: form-data; name="file"; filename="$filename"\r\n');
    buffer.write('Content-Type: application/octet-stream\r\n\r\n');
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  Uint8List getPostfix() {
    var buffer = StringBuffer();
    buffer.write('\r\n--$boundary--\r\n');
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  Stream<List<int>> assembleMultipartWithFile(File file) async* {
    
    // Add prefix
    yield getPrefix();

    // Read file in chunks
    final fileStream = file.openRead();
    await for (final chunk in fileStream) {
      yield chunk;
    }

    // Add postfix
    yield getPostfix();
  }

  Future<int> calculateContentLength(File file) async {
    var contentLength = 0;

    int prefixLength = getPrefix().length;
    contentLength += prefixLength;

    int fileLength = await file.length();
    contentLength += fileLength;

    int postfixLength = getPostfix().length;
    contentLength += postfixLength;

    return contentLength;
  }
}
