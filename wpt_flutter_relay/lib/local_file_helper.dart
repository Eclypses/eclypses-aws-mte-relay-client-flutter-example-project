import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class LocalFileManager {

  // List of asset files
  final List<String> assetFiles = [
    'assets/The Gettysburg Address.txt',
  ];

  Future<void> copyAssetsToDocumentsDirectory() async {

    // Get the application's DocumentsDirectory
    final directory = await getApplicationDocumentsDirectory();

    List<String> storedFiles = await listFiles();

    assetFiles.where((assetPath) => !storedFiles.contains(assetPath)).forEach((assetPath) async {
    
// Extract file name from asset path
      final fileName = assetPath.split('/').last;
      final file = File('${directory.path}/$fileName');

      // Load asset data and write to file
      final byteData = await rootBundle.load(assetPath);
      await file.writeAsBytes(byteData.buffer.asUint8List());
  });

  }


  // Get the application's documents directory
  Future<Directory> _getLocalDirectory() async {
    return await getApplicationDocumentsDirectory();
  }

  // Save a file to local storage
  Future<File> saveFile(String fileName, String content) async {
    final directory = await _getLocalDirectory();
    final file = File('${directory.path}/$fileName');
    return file.writeAsString(content); 
  }

  // Read a file from local storage
  Future<String> readFile(String fileName) async {
    try {
      final directory = await _getLocalDirectory();
      final file = File('${directory.path}/$fileName');
      return await file.readAsString(); 
    } catch (e) {
      throw Exception("File not found: $fileName. Error: $e");
    }
  }

  // List all files in the directory
  Future<List<String>> listFiles() async {
    final directory = await _getLocalDirectory();
    final files = directory.listSync();
    return files.map((file) => file.path).toList();
  }
}
