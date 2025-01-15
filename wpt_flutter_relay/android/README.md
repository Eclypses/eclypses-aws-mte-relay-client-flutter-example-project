<link rel="stylesheet" type="text/css" href="../../eclypses.css">

<center>
<img src="../../Eclypses.png" style="width:50%;"/>
</center>

<div align="center" style="font-size:40pt; font-weight:900; font-family:arial; margin-top:50px;" >
Android Java MteRelay Library for Amazon Web Services</div>

<div align="center" style="font-size:30pt; font-weight:900; font-family:arial; margin-top:50px;" >
Flutter Implementation</div>
<br><br><br>

# Introduction 
This AAR library provides the Java language Eclypses MteRelay Client library, allowing quick integration with very minimal code changes.  This Amazon Web Services (AWS) Client Package requires a corresponding AWS MteRelay Server API to receive the encoded requests and relay them onto the original API. This Documentation focuses on Flutter integration specifically.

## Overview 
When you have integrated this Client library into the Android sub application of your Flutter application and have set up and configured the corresponding MteRelay Server API, your application will make its network calls just as before except that they are now routed through the MteRelay. 

There, the URLRequest is inspected and the relevant information captured. The MteRelay checks for a corresponding MteRelay API and if not found, returns an error. However, if the MteRelay IS found, a new request is created, the original data is encoded with MTE and sent to the MteRelay API where is it decoded. 

Then, the original request is sent on to the original destination API. Any response will follow the same path in reverse.
<br><br>
## Add AWS MteRelay Android library to your Flutter application:
- This guide assumes a working knowledge of including an AAR library (either from a local directory on your computer or directly from Maven Central) in your Android project. [HowTo](https://developer.android.com/build/dependencies#groovy)
1. In your Flutter project, go to the android folder. This folder contains the project for the Android part of your Flutter app.
1. Open the android project in Android Studio.
1. The simplest way to use the library is to list it as a dependency for your app (Module build.gradle / Dependencies). Add 'implementation 'com.eclypses:eclypses-aws-mte-relay-client-android-release:x.x.x' and confirm that MavenCentral is one of your listed repositories.
1. Alternatively, you can add a 'libs' directory to the same level as the src directory n your app, then download the Relay Library from https://github.com/Eclypses/eclypses-aws-mte-relay-client-android.git and compile it. Add the resulting .aar (eclypses-aws-mte-relay-client-android-release-x.x.x-release.aar) to the libs dir you just created and add - implementation files('libs/eclypses-aws-mte-relay-client-android-release-x.x.x-release.aar') - line to your module build.gradle file's dependancies block.

<br><br>

## MteRelay Package Integration
### Overview

- Since Flutter’s main code is in Dart, you’ll need to bridge any Java functionality to Dart using a [Method Channel](https://docs.flutter.dev/platform-integration/platform-channels) (see below).
- In the Java files (e.g., in MainActivity.java) in the Android portion of your project, you can import and use the Android MteRelay library’s code as needed.

### Android Integration (See code examples below)
- In MainActivity.java or other appropriate class ...
    - import com.mte.relay.Relay;
    - import com.mte.relay.RelayDataTaskListener;
    - import com.mte.relay.RelayResponseListener;
    - Create a Relay class variable, e.g. <private Relay relay;> 
    - Create a name constant for the Method Channel
    - Create the Method Channel
    - Add the method channel handler to distinguish between different methods based on the method parameter
    - Add the method to receive the dataTask call from the MethodChannel, create the request and call the Relay module. 
    - Add RelayResponseCallback and RelayResponse method to return certain Relay responses back to Flutter 


    Your class interacting with MteRelay Client must contain these elements
   ``` java
    private Relay relay;
    private static final String CHANNEL = "com.eclypses.mteRelay";
    private MethodChannel methodChannel;

    // Add the RelayResponseListener callback and relayResponse method to return certain responses to Flutter

    RelayResponseListener relayResponseListener = new RelayResponseListener() {
        @Override
        public void onCompletion(Boolean success, String message) {
            relayResponse(success, message, null);
        }
    };

    private void relayResponse(boolean success, String responseStr, String errorMessage) {
        String resultMessage = "Relay Response: " + success + " " + responseStr + " " + (errorMessage != null ? errorMessage : "");

        new Handler(Looper.getMainLooper()).post(() -> {
            if (methodChannel != null) {
                methodChannel.invokeMethod("relayResponseMessage", resultMessage);
            }
        });
    }

   ```
   - In the configureFlutterEngine method, instantiate the MethodChannel and set the handler.
   ``` java
   methodChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);
    methodChannel.setMethodCallHandler(
                (call, result) -> {
                    switch (call.method) {
                        case "initializeRelay":
                            relay = Relay.getInstance(MainActivity.this, relayResponseListener);
                            break;

                        case "relayDataTask":
                            try {
                                Map<String, Object> args = ensureArgumentsMap(call.arguments);
                                relayDataTask(args, result);
                            } catch (IllegalArgumentException e) {
                                result.error("INVALID_ARGUMENTS", e.getMessage(), null);
                            }
                            break;

                        case "relayUploadFile":
                            Log.d("MTE", "relayUploadFile called from Flutter.");
                            Map<String, Object> uploadArgs = ensureArgumentsMap(call.arguments);
                            relayFileStreamUpload(uploadArgs);
                            break;

                        case "relayDownloadFile":
                            Log.d("MTE", "relayDownloadFile called from Flutter.");
                            Map<String, Object> downloadArgs = ensureArgumentsMap(call.arguments);
                            relayFileStreamUpload(downloadArgs);
                            break;

                        case "rePair":
                            try {
                                Map<String, Object> rePairArgs = ensureArgumentsMap(call.arguments);
                                rePair(rePairArgs, result);
                            } catch (IllegalArgumentException e) {
                                result.error("INVALID_ARGUMENTS", e.getMessage(), null);
                            }
                            break;

                        case "adjustRelaySettings":
                            try {
                                Map<String, Object> adjustRelayArgs = ensureArgumentsMap(call.arguments);
                                adjustRelaySettings(adjustRelayArgs);
                            } catch (IllegalArgumentException e) {
                                result.error("INVALID_ARGUMENTS", e.getMessage(), null);
                            }
                            break;

                        case "writeToStream":
                            Log.d("MTE", "writeToStream called from Flutter. Method not implemented yet");
                            result.error("418", "NOT IMPLEMENTED", null);
                            break;

                        case "closeStream":
                            Log.d("MTE", "closeStream called from Flutter. Method not implemented yet");
                            result.error("418", "NOT IMPLEMENTED", null);
                            break;

                        default:
                            result.notImplemented();
                            break;
                    }
                }
        );
   ```

- Create the methods necessary to receive the procedural calls from Flutter and create the Java objects necessary to interact with the Java MteRelay Client library

``` java
@SuppressWarnings("unchecked")
    private void relayDataTask(Map<String, Object> args, MethodChannel.Result result) {
        VolleyResponseListener listener = new VolleyResponseListener() {
            @Override
            public void onError(String message) {
                result.error("", message, null);
            }

            @Override
            public void onJsonResponse(JSONObject response) {
                result.success(response.toString());
            }

            @Override
            public void onJsonArrayResponse(JSONArray response) {
                result.success(response.toString());
            }

            @Override
            public void onStringResponse(String response) {
                result.success(response);
            }
        };

        String[] headersToEncrypt = new String[0];
        try {
            // Extract arguments from the `args` map
            String urlString = (String) args.get("url");
            String pathnamePrefix = (String) args.get("pathnamePrefix");
            String methodString = (String) args.get("method");
            Map<String, String> headers = (Map<String, String>) args.get("headers");
            String body = (String) args.get("body");
            List<String> headersToEncryptList = (List<String>) args.get("headersToEncrypt");
            if (headersToEncryptList != null) {
                headersToEncrypt = headersToEncryptList.toArray(new String[0]);
            }

            // Confirm that we got values in our args
            if (urlString == null || methodString == null || headers == null || body == null) {
                result.error("INVALID_ARGUMENTS", "Invalid arguments", null);
                return;
            }
            int method = getRequestMethod(methodString);

            if (body.isEmpty() || body.trim().startsWith("{")) {
                createJsonRequest(
                        urlString,
                        pathnamePrefix,
                        method,
                        body.isEmpty() ? null : new JSONObject(body),
                        headers,
                        headersToEncrypt,
                        listener);
            } else if (body.trim().startsWith("[")) {
                createJsonArrayRequest(
                        urlString,
                        pathnamePrefix,
                        method,
                        new JSONArray(body),
                        headers,
                        headersToEncrypt,
                        listener);
            } else {
                createStringRequest(
                        urlString,
                        pathnamePrefix,
                        method,
                        body,
                        headers,
                        headersToEncrypt,
                        listener);
            }
        } catch (Exception e) {
            listener.onError(e.getMessage());
        }
    }

    private void createJsonRequest(
            String urlString,
            String pathnamePrefix,
            int method,
            JSONObject body,
            Map<String, String> headers,
            String[] headerArray,
            VolleyResponseListener listener) {
        JsonObjectRequest request = new JsonObjectRequest(
                method,
                urlString,
                body,
                listener::onJsonResponse,
                error -> listener.onError(error.toString())) {

            @Override
            public Map<String, String> getHeaders() throws AuthFailureError {
                return headers;
            }
        };
        sendToRelay(request, headerArray, pathnamePrefix, listener);
    }

    private void createJsonArrayRequest(
            String urlString,
            String pathnamePrefix,
            int method,
            JSONArray body,
            Map<String, String> headers,
            String[] headerArray,
            VolleyResponseListener listener) {
        JsonArrayRequest request = new JsonArrayRequest(
                method,
                urlString,
                body,
                listener::onJsonArrayResponse,
                error -> listener.onError(error.toString())) {

            @Override
            public Map<String, String> getHeaders() throws AuthFailureError {
                return headers;
            }
        };
        sendToRelay(request, headerArray, pathnamePrefix, listener);
    }

    private void createStringRequest(
            String urlString,
            String pathnamePrefix,
            int method,
            String body,
            Map<String, String> headers,
            String[] headerArray,
            VolleyResponseListener listener) {
        StringRequest request = new StringRequest(
                method,
                urlString,
                listener::onStringResponse,
                error -> {
                    String errorMessage = getVolleyErrorString(error);
                    listener.onError(errorMessage);
                }) {
            @Override
            public byte[] getBody() {
                return body != null ? body.getBytes(StandardCharsets.UTF_8) : null;
            }

            @Override
            public Map<String, String> getHeaders() throws AuthFailureError {
                return headers;
            }
        };
        sendToRelay(request, headerArray, pathnamePrefix, listener);
    }

    private <T> void sendToRelay(Request<T> request, String[] headerArray, String pathnamePrefix, VolleyResponseListener listener) {
        relay.addToMteRequestQueue(request, headerArray, null, new RelayDataTaskListener() {
            @Override
            public void onError(String message, Map<String, List<String>> responseHeaders) {
                listener.onError(message);
            }

            @Override
            public void onResponse(byte[] responseBytes, Map<String, List<String>> responseHeaders) {
                try {
                    String jsonString = new String(responseBytes);

                    if (jsonString.trim().startsWith("{")) {
                        JSONObject jsonObject = new JSONObject(jsonString);
                        listener.onJsonResponse(jsonObject);
                    } else if (jsonString.trim().startsWith("[")) {
                        JSONArray jsonArray = new JSONArray(jsonString);
                        listener.onJsonArrayResponse(jsonArray);
                    } else {
                        listener.onError("Response Byte[] contains INVALID JSON");
                    }
                } catch (JSONException e) {
                    listener.onError(e.getMessage());
                }
            }

            @Override
            public void onResponse(JSONObject responseJson, Map<String, List<String>> responseHeaders) {
                listener.onJsonResponse(responseJson);
            }
        });
    }

```
- Below are helper methods used by methods above
``` java

private void rePair(Map<String, Object> args, MethodChannel.Result result) {
        String urlString = (String) args.get("url");
        relay.rePairWithRelayServer(urlString);
    }

    private void adjustRelaySettings(Map<String, Object> args) {
        String serverUrl = null;
        int newStreamChunkSize = 0;
        int newPairPoolSize = 0;
        Boolean persistPairs = false;

        try {
            if (args.containsKey("serverUrl")) {
                Object serverUrlObj = args.get("serverUrl");
                if (serverUrlObj instanceof String) {
                    serverUrl = (String) serverUrlObj;
                }
            }
            if (args.containsKey("streamChunkSize")) {
                Object streamChunkSizeObj = args.get("streamChunkSize");
                if (streamChunkSizeObj instanceof Integer) {
                    newStreamChunkSize = (Integer) streamChunkSizeObj;
                }
            }
            if (args.containsKey("pairPoolSize")) {
                Object pairPoolSizeObj = args.get("pairPoolSize");
                if (pairPoolSizeObj instanceof Integer) {
                    newPairPoolSize = (Integer) pairPoolSizeObj;
                }
            }

            if (args.containsKey("persistPairs")) {
                Object persistPairsObj = args.get("persistPairs");
                if (persistPairsObj instanceof Boolean) {
                    persistPairs = (Boolean) persistPairsObj;
                }
            }
            String responseMessage = relay.adjustRelaySettings(serverUrl,
                    newStreamChunkSize,
                    newPairPoolSize,
                    persistPairs);
            relayResponse(
                    true,
                    responseMessage,
                    null
            );
        } catch (Exception e) {
            relayResponse(
                    false,
                    "\nAdjust RelaySettings Failed",
                    "Error: " + e.getMessage()
            );
        }
    }

    private String getVolleyErrorString(VolleyError error) {
        if (error.networkResponse != null && error.networkResponse.data != null) {
            try {
                // Attempt to parse error response data as a string
                return new String(error.networkResponse.data, StandardCharsets.UTF_8);
            } catch (Exception e) {
                return "Error parsing error response: " + e.getMessage();
            }
        } else if (error.getMessage() != null) {
            return error.getMessage();
        } else {
            return "Unknown error occurred";
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> ensureArgumentsMap(Object arguments) {
        if (arguments instanceof Map) {
            try {
                return (Map<String, Object>) arguments; // Suppressed internally
            } catch (ClassCastException e) {
                throw new IllegalArgumentException("Invalid argument map structure", e);
            }
        } else {
            throw new IllegalArgumentException("Expected arguments of type Map<String, Object>");
        }
    }

    public static int getRequestMethod(String method) {
        switch (method.toUpperCase()) {
            case "GET":
                return Request.Method.GET;
            case "POST":
                return Request.Method.POST;
            case "PUT":
                return Request.Method.PUT;
            case "DELETE":
                return Request.Method.DELETE;
            case "HEAD":
                return Request.Method.HEAD;
            case "OPTIONS":
                return Request.Method.OPTIONS;
            case "TRACE":
                return Request.Method.TRACE;
            case "PATCH":
                return Request.Method.PATCH;
            default:
                throw new IllegalArgumentException("Invalid HTTP method: " + method);
        }
    }
```
- And finially, here is the VolleyResponseListener interface used in the above methods. Add this to your project as a new Java interface.
``` java
    public interface VolleyResponseListener {

        void onError(String message);
        void onJsonResponse(JSONObject response);
        void onJsonArrayResponse(JSONArray response);
        void onStringResponse(String response);
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

<br><br>

<div style="page-break-after: always; break-after: page;"></div>


# Contact Eclypses

<p align="center" style="font-weight: bold; font-size: 20pt;">Email: <a href="mailto:info@eclypses.com">info@eclypses.com</a></p>
<p align="center" style="font-weight: bold; font-size: 20pt;">Web: <a href="https://www.eclypses.com">www.eclypses.com</a></p>
<p align="center" style="font-weight: bold; font-size: 20pt;">Chat with us: <a href="https://developers.eclypses.com/dashboard">Developer Portal</a></p>
<p style="font-size: 8pt; margin-bottom: 0; margin: 100px 24px 30px 24px; " >
<b>All trademarks of Eclypses Inc.</b> may not be used without Eclypses Inc.'s prior written consent. No license for any use thereof has been granted without express written consent. Any unauthorized use thereof may violate copyright laws, trademark laws, privacy and publicity laws and communications regulations and statutes. The names, images and likeness of the Eclypses logo, along with all representations thereof, are valuable intellectual property assets of Eclypses, Inc. Accordingly, no party or parties, without the prior written consent of Eclypses, Inc., (which may be withheld in Eclypses' sole discretion), use or permit the use of any of the Eclypses trademarked names or logos of Eclypses, Inc. for any purpose other than as part of the address for the Premises, or use or permit the use of, for any purpose whatsoever, any image or rendering of, or any design based on, the exterior appearance or profile of the Eclypses trademarks and or logo(s).
</p>
