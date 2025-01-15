import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:poc_flutter_relay/relay_helper.dart';
import 'package:poc_flutter_relay/multipart_helper.dart';

import 'dart:io';
import 'package:poc_flutter_relay/local_file_helper.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure binding for async calls
  final fileManager = LocalFileManager();

  await fileManager.copyAssetsToDocumentsDirectory(); // Copy files at startup
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const platform = MethodChannel('com.eclypses.mteRelay');

  @override
  void initState() {
    super.initState();

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
  }

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

  final RelayHelper _relayHelper = RelayHelper();
  late MultipartHelper builder;
  late File file;

  var endpointServerUrl = "<your endpoint server url>";
  var authToken = "";
  int lastNoteId = 0;

  Future<void> loginDirect() async {
    String urlWithPath = "$endpointServerUrl/<route>";
    final postLoginBody =
        jsonEncode({"email": "<email address>", "password": "<password>"});
    try {
      final response = await http.post(
        Uri.parse(urlWithPath),
        headers: {
          "Content-Type": "application/json",
        },
        body: postLoginBody,
      );

      if (response.statusCode == 200) {
        // Retrieve AuthToken
        authToken =
            'Bearer ${jsonDecode(response.body)['data']['access_token']}';
        // Display Result
        _showResult("Received Access Token\n\n $authToken");
      } else {
        _showResult("Error: ${response.body}");
      }

;
    } catch (error) {
      _showResult("Error: $error");
    }
  }

  Future<void> getECardsDirect() async {
    String urlWithPath = "$endpointServerUrl/<route>";
    try {
      final response = await http.get(
        Uri.parse(urlWithPath),
        headers: {
          "Content-Type": "application/json",
          'Authorization': authToken,
        },
      );

      if (response.statusCode == 200) {
        _showResult(response.body);
      } else {
        _showResult("Error: ${response.body}");
      }
    } catch (error) {
      _showResult("Error: $error");
    }
  }

  Future<void> login() async {
    String urlWithPath = "$relayServerUrl/api/v3/users/auth";
    final postLoginBody =
        jsonEncode({"email": "aziz@willport.com", "password": "Willport@2023"});
    try {
      final result = await _relayHelper.relayDataTask(
        urlWithPath,
        'POST',
        {'Content-Type': 'application/json'},
        postLoginBody,
        headersToEncrypt,
      );

      // Retrieve AuthToken
      authToken = 'Bearer ${jsonDecode(result)['data']['access_token']}';

// Display Result
      _showResult("Received Access Token\n\n $authToken");
    } catch (error) {
      _showResult("Error: $error");
    }
  }

  Future<void> getECards() async {
    String urlWithPath =
        "$relayServerUrl/api/v3/e_greeting_cards?page=1&per_page=10";
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

  Future<void> multipartSample() async {
    String urlWithPath = "$relayServerUrl/api/v3/orders/multipart";

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
        // bodyBytes.toString(),
        utf8.decode(bodyBytes),
        headersToEncrypt,
      );

      // Display Result
      _showResult(result);
    } catch (error) {
      _showResult("Error: $error");
    }
  }

  Future<void> createNote() async {
    String urlWithPath = "$relayServerUrl/api/v3/users/profile/276/note";
    final postLoginBody = jsonEncode({"note": "He is my best friend!"});
    try {
      final result = await _relayHelper.relayDataTask(
        urlWithPath,
        'POST',
        {'Content-Type': 'application/json', 'Authorization': authToken},
        postLoginBody,
        headersToEncrypt,
      );

      // Retrieve Note Id to use in subsequent requests
      lastNoteId = jsonDecode(result)['data']['id'];

      // Display Result
      _showResult(result);
    } catch (error) {
      _showResult("Error: $error");
    }
  }

  Future<void> getNotes() async {
    String urlWithPath = "$relayServerUrl/api/v3/users/profile/276/notes";

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

  Future<void> editNote() async {
    String urlWithPath =
        "$relayServerUrl/api/v3/users/profile/276/note/$lastNoteId";

    // Define parameters for the multipart form-data
    final parameters = [
      {
        "key": "note",
        "value": "He is NOT my best friend anymore!",
        "type": "text",
      },
    ];

// Boundary string for multipart data
    final boundary = 'Boundary-${DateTime.now().millisecondsSinceEpoch}';

// Prepare body data
    final body = StringBuffer();
    for (final param in parameters) {
      if (param["disabled"] != null) continue; // Skip if disabled

      final paramName = param["key"];
      body.write('--$boundary\r\n');
      body.write('Content-Disposition: form-data; name="$paramName"');

      if (param["type"] == "text") {
        final paramValue = param["value"];
        body.write('\r\n\r\n$paramValue\r\n');
      }
      body.write('--$boundary--\r\n');
    }

// Send to relay
    try {
      final result = await _relayHelper.relayDataTask(
        urlWithPath,
        'PUT',
        {
          'Content-Type': 'multipart/form-data; boundary=$boundary',
          'Authorization': authToken
        },
        body.toString(),
        headersToEncrypt,
      );

// Display Result
      _showResult(result);
    } catch (error) {
      _showResult("Error: $error");
    }
  }

  Future<void> deleteNote() async {
    String urlWithPath =
        "$relayServerUrl/api/v3/users/profile/276/note/$lastNoteId";

// Send to relay
    try {
      final result = await _relayHelper.relayDataTask(
        urlWithPath,
        'DELETE',
        {'Authorization': authToken},
        "",
        headersToEncrypt,
      );

// Display Result
      _showResult(result);
    } catch (error) {
      _showResult("Error: $error");
    }
  }

  var relayServerUrl = "<RelayServerUrl>";

  final headersToEncrypt = ['Content-Type'];
  final dataTaskHeaders = {
    'Content-Type': 'application/json',
  };

  String? _result; // Variable to hold the result of the API call

  Future<File> getFileToUpload(String filesize) async {
    final directory = await getApplicationDocumentsDirectory();
    String dirStr = directory.path;
    return File("$dirStr/The Gettysburg Address.txt");
  }

  // String lastUpload = "";

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
      await platform.invokeMethod('adjustRelaySettings', {
        // Any argument not included or that is the same as the existing RelaySetting is disregarded
        'serverUrl': relayServerUrl,
        'streamChunkSize': 1024 * 512, // current default
        'pairPoolSize': 5, // current default
        'persistPairs': false // current default
      });

      //   // Display Result
      //   _showResult(result);
    } catch (error) {
      _showResult("Error: $error");
    }
  }

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

  void _showResult(String message) {
    setState(() {
      _result = message;
    });

    // Hide the response text after 2 seconds
    Timer(Duration(seconds: 2), () {
      setState(() {
        _result = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      darkTheme: ThemeData(
        brightness: Brightness.dark, // Dark theme
        primarySwatch: Colors.deepOrange,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text("Server Response")),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Display the result above the buttons
            if (_result != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _result!,
                  textAlign: TextAlign.left,
                  style: const TextStyle(fontSize: 16, color: Colors.green),
                ),
              ),
            const Text(
              'Direct-To-Endpoint Calls',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: loginDirect,
                  child: const Text(
                    "Direct Login",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF6531E),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: getECardsDirect,
                  child: const Text(
                    "Direct E-Cards",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF6531E),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Eclypses MTE Calls',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: login,
                  child: const Text(
                    "Login",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF6531E),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: getECards,
                  child: const Text(
                    "Get E-Cards",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF6531E),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: multipartSample,
                  child: const Text(
                    "Multipart Sample",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF6531E),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: createNote,
                  child: const Text(
                    "Create Note",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF6531E),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: getNotes,
                  child: const Text(
                    "Get Notes",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF6531E),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: editNote,
                  child: const Text(
                    "Edit Note",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF6531E),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: deleteNote,
                  child: const Text(
                    "Delete Note",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF6531E),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'MTE Utility Calls',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    await rePair();
                  },
                  child: const Text(
                    "Re-Pair",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF6531E),
                    ),
                  ),
                ),
                              ElevatedButton(
                  onPressed: () async {
                    await adjustSettings();
                  },
                  child: const Text(
                    "Adjust Settings",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF6531E),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
              ],
            ),
          ],
        ),
      ),
    );
  }

  final List<Map<String, dynamic>> parameters = [
    {
      "key": "order[details][payment_method_id]",
      "value": "127",
      "type": "text",
    },
    {
      "key": "order[details][delivery_date]",
      "value": "2024-11-19",
      "type": "text",
    },
    {
      "key": "order[details][order_type]",
      "value": "immediate",
      "type": "text",
    },
    {
      "key": "order[details][recipients][][id]",
      "value": "112",
      "type": "text",
    },
    {
      "key": "order[details][recipients][][type]",
      "value": "User",
      "type": "text",
    },
    {
      "key": "order[details][recipients][][address][address_line_1]",
      "value": "10768 Scripps Ranch Blvd",
      "type": "text",
    },
    {
      "key": "order[details][recipients][][address][address_line_2]",
      "value": "",
      "type": "text",
    },
    {
      "key": "order[details][recipients][][address][state]",
      "value": "California",
      "type": "text",
    },
    {
      "key": "order[details][recipients][][address][city]",
      "value": "San Diego",
      "type": "text",
    },
    {
      "key": "order[details][recipients][][address][country]",
      "value": "US",
      "type": "text",
    },
    {
      "key": "order[details][recipients][][address][zip]",
      "value": "92131",
      "type": "text",
    },
    {
      "key": "order[items][][item_id]",
      "value": "41222",
      "type": "text",
    },
    {
      "key": "order[items][][item_type]",
      "value": "CustomCard",
      "type": "text",
    },
    {
      "key": "order[items][][quantity]",
      "value": "1",
      "type": "text",
    },
    {
      "key": "order[items][][message]",
      "value": "Heloo First Gift",
      "type": "text",
    },
    {
      "key": "order[items][][amount]",
      "value": "0",
      "type": "text",
    },
    {
      "key": "order[items][][41222][image]",
      "src":
          "/Users/usmanimam/Downloads/fb8f94f5-8bbd-4b68-82c0-164fb16652aa.webp",
      "type": "file",
    },
    {
      "key": "multipart",
      "value": "true",
      "type": "text",
    },
  ];
}
