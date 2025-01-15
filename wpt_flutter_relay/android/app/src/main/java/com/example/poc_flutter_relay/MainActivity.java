// The MIT License (MIT)
//
// Copyright (c) Eclypses, Inc.
//
// All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package com.example.poc_flutter_relay;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;

import com.android.volley.AuthFailureError;
import com.android.volley.Request;
import com.android.volley.VolleyError;
import com.android.volley.toolbox.JsonArrayRequest;
import com.android.volley.toolbox.JsonObjectRequest;
import com.android.volley.toolbox.StringRequest;
import com.mte.relay.Relay;
import com.mte.relay.RelayDataTaskListener;
import com.mte.relay.RelayResponseListener;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {

    // Class variables
    private Relay relay;
    private static final String CHANNEL = "com.eclypses.mteRelay";
    private MethodChannel methodChannel;

    // RelayResponse callback
    RelayResponseListener relayResponseListener = new RelayResponseListener() {
        @Override
        public void onCompletion(Boolean success, String message) {
            relayResponse(success, message, null);
        }
    };

    // MethodChannel method to return RelayResponse to Flutter
    private void relayResponse(boolean success, String responseStr, String errorMessage) {
        String resultMessage = "Relay Response: " + success + " " + responseStr + " " + (errorMessage != null ? errorMessage : "");

        new Handler(Looper.getMainLooper()).post(() -> {
            if (methodChannel != null) {
                methodChannel.invokeMethod("relayResponseMessage", resultMessage);
            }
        });
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
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
    }

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

    private void relayFileStreamUpload(Map<String, Object> args) {
        relayResponse(
                false,
                "\nError Code 418",
                "NOT IMPLEMENTED"
        );
    }

    private void relayFileStreamDownload(Map<String, Object> args) {
        relayResponse(
                false,
                "\nError Code 418",
                "NOT IMPLEMENTED"
        );
    }

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

}