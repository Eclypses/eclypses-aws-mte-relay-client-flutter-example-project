<center>
<img src="../../Eclypses.png" style="width:50%;"/>
</center>

<div align="center" style="font-size:40pt; font-weight:900; font-family:arial; margin-top:50px;" >
iOS MteRelay Swift Package For <br>Amazon Web Services</div>

<div align="center" style="font-size:30pt; font-weight:900; font-family:arial; margin-top:50px;" >
Flutter Implementation</div>
<br><br><br>

# MteRelay Swift Package

### The SPM package provides out-of-the-box MTE integration into Swift iOS applications, allowing quick integration with very minimal code changes.  This Amazon Web Services (AWS) Client Package requires a corresponding AWS MteRelay Server API to receive the encoded requests and relay them onto the original API. This Documentation focuses on Flutter integration specifically. 
 
<br><br>

## Overview 
When you have integrated this Client Package into the iOS sub application of your Flutter application and have set up and configured the corresponding MteRelay Server API, your application will make its network calls just as before except that they are now routed through the MteRelay. 

There, the URLRequest is inspected and the relevant information captured. The MteRelay checks for a corresponding MteRelay API and if not found, returns an error. However, if the MteRelay IS found, a new request is created, the original data is encoded with MTE and sent to the MteRelay API where is it decoded. 

Then, the original request is sent on to the original destination API. Any response will follow the same path in reverse.
<br><br>
## Add AWS MteRelay Swift Package to your Flutter application:
1. Turn on Swift Package Manager as shown [here](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers). 
1. In your Flutter project, go to the ios folder. This folder contains the Xcode project for the iOS part of your Flutter app.
1. In the ios folder, you should see a file named <your_project_name>.xcworkspace. Open this file in Xcode.
1.  Add this [AWS MteRelay Package](https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios.git) -  [HowTo](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app)
1. Build the project from either the IDE with the Flutter project or the Xcode project. If you get an error calling out a compile/target mismatch, in the Xcode project, open the General tab of the Runner project and update the minimum deployment.
1.  Set up corresponding AWS MteRelay API to receive the requests from your application, where they will be decoded and relayed on to the original destination API.
1.  Navigate to your target’s General pane, and in the “Frameworks, Libraries, and Embedded Content” section, confirm that the MteRelay module is there. If not, add it.
<br><br>

## MteRelay Package Integration
### Overview
<!-- Do the minimal setup which primarily consists of configuring the AWS MteRelay Server URL and editing your iOS application to use the MteRelay dataTask function.  -->
- Since Flutter’s main code is in Dart, you’ll need to bridge any Swift functionality to Dart using a [Method Channel](https://docs.flutter.dev/platform-integration/platform-channels) (see below).
- In the Swift files (e.g., in AppDelegate.swift) in the ios portion of your project, you can import and use the Swift package’s code as needed.


### iOS Integration (See code examples below)
- In AppDelegate.swift or other appropriate class ...
    - Import MteRelay
    - Create a Relay class variable, e.g. < private var relay: Relay!> 
    - Create the Method Channel
    - Add the method channel handler to distinguish between different methods based on the method parameter
    - Add the method to receive the dataTask call from the MethodChannel, create the request and call the Relay module. 
    - Add RelayResponseDelegate conformance and the single method this conformance requires

      - For streamed file uploads, add the method to receive the relayFileStreamUpload call from the MethodChannel, create the request and call the Relay module. 
      - Add the writeToStream and closeStream methods to handle the streamed data from the Flutter application.
      - Add the required RelayStreamDelegate and RelayStreamResponseDelegate conformance the their methods.

    Your class interacting with MteRelay Client must contain these elements
```swift  
import "MteRelay"

// The class were you wish to receive MteRelay responses needs to have a reference to MteRelay instance and conform to RelayResponseDelegate, RelayStreamDelegate, RelayStreamResponseDelegate and RelayStreamCompletionDelegate.
class AppDelegate: FlutterAppDelegate, RelayResponseDelegate, RelayStreamDelegate, RelayStreamResponseDelegate, RelayStreamCompletionDelegate {

    // Class Variables
    var streamingResult: FlutterResult!
    var outputStreams: [String: OutputStream] = [:]
    var count: Int = 0
    var methodChannel: FlutterMethodChannel!
    private var relay: Relay!

    func relayResponse(success: Bool, responseStr: String, errorMessage: String?) {
        DispatchQueue.main.async {
            self.methodChannel?.invokeMethod("relayResponseMessage", arguments: "Relay Response: \(success) \(responseStr) \(errorMessage ?? "")");
        }
    }

    func relayStreamResponse(success: Bool, responseStr: String, errorMessage: String?) {
        if !success {
            streamingResult("Error: \(errorMessage ?? "Unknown error")")
        } else {
            streamingResult(responseStr)
        }
    }
    
    // Get requestBodySgtream from Flutter
    func getRequestBodyStream(outputStream: OutputStream) -> Int {
        let streamID = UUID().uuidString
        outputStreams[streamID] = outputStream
        DispatchQueue.main.async {
            self.methodChannel?.invokeMethod("getFileStream", arguments: streamID, result: { result in
                if let intValue = result as? Int {
                    self.count = intValue
                } else if let error = result as? FlutterError {
                    self.streamingResult("Error: \(error.message ?? "Unknown error")")
                } else {
                    self.count = 0
                    self.streamingResult("Unexpected result: \(result ?? "nil")")
                }
            })
        }
        return count
    }

        func streamCompletionPercentage(bytesCompleted: Double, totalBytes: Double) {
        let streamCompletionPercentage = (bytesCompleted/totalBytes)
        DispatchQueue.main.async {
            self.methodChannel?.invokeMethod("streamCompletionPercentage", arguments: streamCompletionPercentage);
        }
    }


    // Create the Method Channel
    let controller = window?.rootViewController as! FlutterViewController
    methodChannel = FlutterMethodChannel(name: "com.eclypses.mteRelay", binaryMessenger: controller.binaryMessenger)
    
    // Add the method channel handler to distinguish between different methods based on the method parameter
    methodChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        switch call.method {
        case "initializeRelay":
            Task {
                do {
                    self?.relay = try await Relay()
                    self?.relay.relayResponseDelegate = self
                } catch {
                    result(FlutterError(code: "ERROR", message: "Instance not initialized", details: nil))
                }
            }
            result(nil) // No result needed for initialization
        case "relayDataTask":
            if let args = call.arguments as? [String: Any],
                let instance = self?.relay {
                self?.relayDataTask(args, instance, result)
            } else {
                result(FlutterError(code: "ERROR", message: "Instance not initialized or invalid parameters", details: nil))
            }
        case "relayUploadFile":
            if let args = call.arguments as? [String: Any],
                let instance = self?.relay {
                instance.relayStreamDelegate = self
                instance.relayStreamResponseDelegate = self
                instance.relayStreamCompletionDelegate = self
                self?.streamingResult = result
                self?.relayFileStreamUpload(args, instance, result)
            } else {
                result(FlutterError(code: "ERROR", message: "Instance not initialized or invalid parameters", details: nil))
            }
        case "relayDownloadFile":
            if let args = call.arguments as? [String: Any],
                let instance = self?.relay {
                instance.relayStreamResponseDelegate = self
                self?.streamingResult = result
                self?.relayFileStreamDownload(args, instance, result)
            } else {
                result(FlutterError(code: "ERROR", message: "Relay not initialized or invalid parameters", details: nil))
            }
        case "rePair":
                if let args = call.arguments as? [String: Any],
                   let instance = self?.relay {
                    self?.rePair(args, instance, result)
                } else {
                    result(FlutterError(code: "ERROR", message: "Relay not initialized or invalid parameters", details: nil))
                }
            case "adjustRelaySettings":
                if let args = call.arguments as? [String: Any],
                   let instance = self?.relay {
                    self?.adjustRelaySettings(args)
                } else {
                    result(FlutterError(code: "ERROR", message: "Relay not initialized or invalid parameters", details: nil))
                }
        case "writeToStream":
            if let args = call.arguments as? [String: Any] {
                self?.writeToStream(arguments: args)
            }else {
                result(FlutterError(code: "ERROR", message: "Invalid parameters", details: nil))
            }
        case "closeStream":
            if let args = call.arguments as? [String: Any] {
                self?.closeStream(arguments: args)
            }else {
                result(FlutterError(code: "ERROR", message: "Invalid parameters", details: nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    fileprivate func relayDataTask(_ args: [String: Any],
                                   _ instance: Relay,
                                   _ result: @escaping FlutterResult) {
        guard let urlString = args["url"] as? String,
              let url = URL(string: urlString),
              let method = args["method"] as? String,
              let headers = args["headers"] as? [String: String],
              let body = args["body"] as? String,
              let headersToEncrypt = args["headersToEncrypt"] as? [String] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.allHTTPHeaderFields = headers
        if body != "" {
            request.httpBody = body.data(using: .utf8)
        }
        Task {
            await instance.dataTask(with: request,
                                    headersToEncrypt: headersToEncrypt,
                                    completionHandler: { (data, response, error) in
                
                if let error = error {
                    result(FlutterError(code: "RelayError", message: error.localizedDescription, details: nil))
                }
                if let data {
                    if let json = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers),
                       let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
                        result(String(decoding: jsonData, as: UTF8.self))
                    } else {
                        result(FlutterError(code: "ERROR", message: "Malformed JSON", details: nil))
                    }
                }
            })
        }
    }
    
    fileprivate func relayFileStreamUpload(_ args: [String: Any],
                                           _ instance: Relay,
                                           _ result: @escaping FlutterResult) {
        guard let urlString = args["url"] as? String,
              let url = URL(string: urlString),
              let method = args["method"] as? String,
              let headers = args["headers"] as? [String: String],
              let headersToEncrypt = args["headersToEncrypt"] as? [String] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.allHTTPHeaderFields = headers
        Task {
            try instance.uploadFileStream(request: request, headersToEncrypt: headersToEncrypt)
        }
    }
    
    fileprivate func relayFileStreamDownload(_ args: [String: Any],
                                           _ instance: Relay,
                                           _ result: @escaping FlutterResult) {
        guard let urlString = args["url"] as? String,
              let url = URL(string: urlString),
              let method = args["method"] as? String,
              let headers = args["headers"] as? [String: String],
              let headersToEncrypt = args["headersToEncrypt"] as? [String],
              let downloadlocation = args["downloadLocation"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.allHTTPHeaderFields = headers
        guard let downloadUrl = URL(string: downloadlocation) else {
            let message = "Invalid downloadUrl: \(downloadlocation)"
            result(FlutterError(code: "INVALID_ARGUMENTS", message: message, details: nil))
            return
        }
        Task {
            try instance.downloadFileStream(request: request, downloadUrl: downloadUrl, headersToEncrypt: headersToEncrypt)
        }
    }
    
    fileprivate func rePair(_ args: [String: Any],
                                           _ instance: Relay,
                                           _ result: @escaping FlutterResult) {
        guard let urlString = args["url"] as? String,
              let _ = URL(string: urlString) else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            return
        }
        Task {
            try await instance.rePairMte(relayServerUrlString: urlString) { success in
                Task {
                    if success == true {
                        result("Successfully Re-Paired with \(urlString)")
                    } else {
                        result(FlutterError(code: "Re-Pair Failed", message: "Unable to re-pair with \(urlString)", details: nil))
                    }
                }
            }
        }
    }
    
    fileprivate func adjustRelaySettings(_ args: [String: Any]) {
        var responseMessage = ""
        do {
            if let newStreamChunkSize = args["streamChunkSize"] as? Int,
               newStreamChunkSize != relay.getStreamChunkSizeSetting() {
               try relay.setStreamChunkSize(newStreamChunkSize)
                responseMessage = responseMessage + "\nRelaySetting.streamChunkSize adjusted to \(newStreamChunkSize) "
            }
            if let newPairPoolSize = args["pairPoolSize"] as? Int,
               newPairPoolSize != relay.getPairPoolSizeSetting() {
                try relay.setPairPoolSize(newPairPoolSize)
                responseMessage = responseMessage + "\nRelaySetting.pairPoolSize adjusted to \(newPairPoolSize) "
            }
            if let persistPairs = args["persistPairs"] as? Bool,
               persistPairs != relay.getPersistPairsSetting() {
                try relay.setPersistPairs(persistPairs)
                responseMessage = responseMessage + "/nRelaySetting.persistPairs adjusted to \(persistPairs) "
            }
            if !responseMessage.isEmpty {
                relayResponse(success: true,
                              responseStr: responseMessage,
                              errorMessage: nil)
            } else {
                relayResponse(success: true,
                              responseStr: "\nNo Relay Settings were changed based on arguments and existing RelaySettings",
                              errorMessage: nil)
            }
        } catch {
            relayResponse(success: false,
                          responseStr: "\nAdjust RelaySettings Failed",
                          errorMessage: "Error: \(error)")
        }
    }
    
    var index = 1
    var totalBytes: Int = 0
    func writeToStream(arguments: [String: Any]) {
        guard
            let streamID = arguments["streamID"] as? String,
            let data = arguments["data"] as? FlutterStandardTypedData,
            let outputStream = outputStreams[streamID]
        else {
            streamingResult("writeToStream received invalid arguments.")
            return
        }
        
        let bytes = [UInt8](data.data)
        totalBytes += bytes.count
        let bytesWritten = writeToOutputStream(outputStream: outputStream, buffer: Data(bytes))
        index += 1
    }
    
    func closeStream(arguments: [String: Any]) {
        guard
            let streamID = arguments["streamID"] as? String
        else {
            streamingResult("writeToStream received invalid arguments.")
            return
        }
        if let stream = outputStreams[streamID] {
            stream.close()
            outputStreams.removeValue(forKey: streamID)
        }
    }
    
    func writeToOutputStream(outputStream: OutputStream, buffer: Data) -> Int {
        var bytesLeft = buffer.count
        var totalBytesWritten = 0
        
        // Wait until the stream has space available and write in chunks
        while bytesLeft > 0 {
            if outputStream.hasSpaceAvailable {
                // Calculate the range of data to write
                let range = totalBytesWritten..<totalBytesWritten + bytesLeft
                let chunk = buffer.subdata(in: range)
                
                // Write data to the output stream
                let bytesWritten = chunk.withUnsafeBytes {
                    outputStream.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: bytesLeft)
                }
                
                // Check for errors
                if bytesWritten < 0 {
                    if let streamError = outputStream.streamError {
                        streamingResult("Stream error: \(streamError.localizedDescription)")
                    }
                    break
                }
                
                // Update counters
                totalBytesWritten += bytesWritten
                bytesLeft -= bytesWritten
            } else {
                // Allow other events to process if the stream is not ready
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
        }
        return totalBytesWritten
    }
```

### Flutter Integration
- Open your Flutter project in the IDE of your choice. VS Code works well.
- In <YourProject/lib> directory, create a new relay_helper.dart class and add the following ...

``` dart
import 'package:flutter/services.dart';

class RelayHelper {
  static const MethodChannel _relayMethodChannel = MethodChannel('com.eclypses.mteRelay');

  static final RelayHelper _relayInstance = RelayHelper._internal();

  factory RelayHelper() => _relayInstance;

  RelayHelper._internal() {
    initializeRelay();
  }

  Future<void> initializeRelay() async {
    await _relayMethodChannel.invokeMethod('initializeRelay');
  }

  Future<String> relayDataTask(String url, String method, Map<String, String> headers,
      String body, List<String> headersToEcrypt) async {
    final String result = await _relayMethodChannel.invokeMethod('relayDataTask', {
      'url': url,
      'method': method,
      'headers': headers,
      'headersToEncrypt': headersToEcrypt,
      'body': body
    });
    return result;
  }

  Future<String> uploadFileStream(Map<String, dynamic> requestData, 
                                  List<String> headersToEcrypt,) async {
    final String result = await _relayMethodChannel.invokeMethod('relayUploadFile', {
      'requestData': requestData,
      'headersToEncrypt': headersToEcrypt,
    });
    return result;
  }

}
```

 - Then, in the class from where you make your network calls ...

- If you have request headers that you wish to conceal, create a String array with the header names as the elements in the array. Content-Type will always be encrypted if it exists. The encrypted headers will be decrypted before being sent on the the original destination Server.

``` dart
final headersToEncrypt = ['Content-Type', '<any_other_header_name>'];
```
<br><br>

### IMPORTANT - - Update your Request
- For any call you want to route through MteRelay, edit your Request URL to point to your MteServer API, i.e. https://aws-mte-server.myCompany.com/

<br><br>


```dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:poc_flutter_relay/relay_helper.dart';
import 'package:poc_flutter_relay/multipart_helper.dart';

import 'dart:io';
import 'package:poc_flutter_relay/local_file_helper.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';

String? _result; // Variable to hold the result of the API call
var authToken = "";
final RelayHelper _relayHelper = RelayHelper();


// Sample POST request
  Future<void> login() async {
    String urlWithPath = "$relayServerUrl/<loginPath>";
    final postLoginBody =
        jsonEncode({'email': 'email.com', 'password': 'secret'});
    try {
      final result = await _relayHelper.relayDataTask(
        urlWithPath,
        'POST',
        {'Content-Type': 'application/json'},
        postLoginBody,
        headersToEncrypt,
      );


      // Example - Retrieve AuthToken
      authToken = 'Bearer ${jsonDecode(result)['data']['access_token']}';

        // Display Result
    _showResult("Received Access Token\n\n $authToken");
    } catch (error) {
      _showResult("Error: $error");
    }
  }

  // Sample GET request
Future<void> getUsers() async {
    String urlWithPath =
        "$relayServerUrl/<query string>";
    try {
    final result = await _relayHelper.relayDataTask(
        urlWithPath,
        'GET',
        {'Content-Type': 'application/json', 'Authorization': authToken},
        "",
        headersToEncrypt,
    );

    // Display Result
    _showResult(result);
    } catch (error) {
    _showResult("Error: $error");
    }
}

  // Sample Multipart POST request
Future<void> multipartSample() async {
    String urlWithPath = "$relayServerUrl/<multipartPath>";

    // Boundary string for multipart data
    final boundary = 'Boundary-${DateTime.now().millisecondsSinceEpoch}';

    // Create body
    final body = BytesBuilder();
    for (final param in parameters) {
        if (param['disabled'] != null) continue;

        final paramName = param['key'];
        body.add(utf8.encode('--$boundary\r\n'));
        body.add(
            utf8.encode('Content-Disposition: form-data; name="$paramName"'));

        if (param['contentType'] != null) {
            body.add(utf8.encode('\r\nContent-Type: ${param['contentType']}\r\n'));
        }
        final paramType = param['type'];
        if (paramType == 'text') {
            final paramValue = param['value'];
            body.add(utf8.encode('\r\n\r\n$paramValue\r\n'));
        } else if (paramType == 'file') {
            final file = await getFileToUpload("small");
            if (await file.exists()) {
            String filename = file.path.split(Platform.pathSeparator).last;
            body.add(utf8.encode('; filename="$filename"\r\n'));
            body.add(
                utf8.encode('Content-Type: application/octet-stream\r\n\r\n'));
            body.add(await file.readAsBytes());
            body.add(utf8.encode('\r\n'));
            }
        }
    }
    body.add(utf8.encode('--$boundary--\r\n'));

    final bodyBytes = body.toBytes();

    // Send to relay
    try {
        final result = await _relayHelper.relayDataTask(
        urlWithPath,
        'POST',
        {
        'Content-Type': 'multipart/form-data; boundary=$boundary',
        'Authorization': authToken
        },
        bodyBytes.toString(),
        headersToEncrypt,
    );

    // Display Result
    _showResult(result);
    } catch (error) {
    _showResult("Error: $error");
    }
}
```
### To include streamed file uploads, add the following.

- In <YourProject/lib> directory, create a new multipart_helper.dart class and add the following ...

``` dart
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
```
Then, in the class where you will make your calls to the Relay for streamed file uploads, add the following.
``` dart
    // Probably in the init function for this class,
    // Set a listener for messages from Swift
    platform.setMethodCallHandler((call) async {
    switch (call.method) {
        case "getFileStream":
        String streamID = call.arguments;
        startStreaming(streamID);
        return builder.calculateContentLength(file);
        case "relayResponseMessage":
        String message = call.arguments;
        _showResult(message);
    }
    });

    void startStreaming(String streamID) async {
        
    // Write data to the request stream
    final writeStream = builder.assembleMultipartWithFile(file);
    await for (final chunk in writeStream) {
        platform.invokeMethod("writeToStream", {
            "streamID": streamID,
            "data": Uint8List.fromList(chunk),
        });
    }

    // Notify Swift to close the stream
    await platform.invokeMethod("closeStream", {"streamID": streamID});
    }

Future<void> uploadFileStream(String filesize) async {
    file = await File(<pathToFile>)
    String filename = file.path.split(Platform.pathSeparator).last;

    String urlWithPath = "$relayServerUrl/uploadPath";
    final uri = Uri.parse(urlWithPath);

    builder = MultipartHelper(filename);
    final httpClientRequest = await HttpClient().postUrl(uri);

    // Set required headers
    httpClientRequest.headers.set(HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=${builder.boundary}');
    int contentLength = await builder.calculateContentLength(file);
    httpClientRequest.headers
        .set(HttpHeaders.contentLengthHeader, contentLength.toString());

    final requestData =
        await convertHttpRequestToMap(httpClientRequest, headersToEncrypt);
    var result = await platform.invokeMethod('relayUploadFile', requestData);

    // Display Result
    _showResult(result);
}

Future<void> downloadFileStream() async {
    final urlEncodedFilename = Uri.encodeComponent(lastUpload);
    final downloadLocation = await getDownloadUrl(lastUpload);
    print("Download Location:\n$downloadLocation");
    String urlWithPath =
        "$relayServerUrl/<downloadFilePath>/$urlEncodedFilename";
    try {
      final arguments = {
        'url': urlWithPath,
        'method': 'GET',
        'headers': {'Content-Type': 'application/json'},
        'headersToEncrypt': headersToEncrypt,
        'downloadLocation': downloadLocation,
      };
      var result = await platform.invokeMethod('relayDownloadFile', arguments);

      // Display Result
      _showResult(result);
    } catch (error) {
      _showResult("Error: $error");
    }
  }

    Future<void> rePair() async {
    try {
      var result = await platform.invokeMethod('rePair', {
      'url': relayServerUrl,
    });

      // Display Result
      _showResult(result);
    } catch (error) {
      _showResult("Error: $error");
    }
  }

  Future<void> adjustSettings() async {
    try {
      var result = await platform.invokeMethod('adjustRelaySettings', {
        // Any argument not included or that is the same as the existing RelaySetting is disregarded
      'uploadChunkSize': 1024*1024, // current default
      'pairPoolSize': 3, // current default
      'persistPairs': false // current default
    });

      // Display Result
      _showResult(result);
    } catch (error) {
      _showResult("Error: $error");
    }
  }

  // Convenience method
    Future<Map<String, dynamic>> convertHttpRequestToMap(
        HttpClientRequest request, List<String> headersToEncrypt) async {

        // Get headers as a Map
        final headers = <String, String>{};
        request.headers.forEach((name, values) {
            headers[name] = values.join(','); 
        });

        // Extract other properties
        final map = {
            'url': request.uri.toString(),
            'method': request.method,
            'headers': headers,
            'headersToEncrypt': headersToEncrypt,
        };
    return map;
    }
```
<br><br>

<div style="page-break-after: always; break-after: page;"></div>


# Contact Eclypses

<p align="center" style="font-weight: bold; font-size: 20pt;">Email: <a href="mailto:info@eclypses.com">info@eclypses.com</a></p>
<p align="center" style="font-weight: bold; font-size: 20pt;">Web: <a href="https://www.eclypses.com">www.eclypses.com</a></p>
<p align="center" style="font-weight: bold; font-size: 20pt;">Chat with us: <a href="https://developers.eclypses.com/dashboard">Developer Portal</a></p>
<p style="font-size: 8pt; margin-bottom: 0; margin: 100px 24px 30px 24px; " >
<b>All trademarks of Eclypses Inc.</b> may not be used without Eclypses Inc.'s prior written consent. No license for any use thereof has been granted without express written consent. Any unauthorized use thereof may violate copyright laws, trademark laws, privacy and publicity laws and communications regulations and statutes. The names, images and likeness of the Eclypses logo, along with all representations thereof, are valuable intellectual property assets of Eclypses, Inc. Accordingly, no party or parties, without the prior written consent of Eclypses, Inc., (which may be withheld in Eclypses' sole discretion), use or permit the use of any of the Eclypses trademarked names or logos of Eclypses, Inc. for any purpose other than as part of the address for the Premises, or use or permit the use of, for any purpose whatsoever, any image or rendering of, or any design based on, the exterior appearance or profile of the Eclypses trademarks and or logo(s).
</p>
