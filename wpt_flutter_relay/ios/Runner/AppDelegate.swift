import Flutter
import UIKit
import MteRelay

@main
@objc class AppDelegate: FlutterAppDelegate, RelayResponseDelegate, RelayStreamDelegate, RelayStreamResponseDelegate, RelayStreamCompletionDelegate {
    
    // Class Variables
    var streamingResult: FlutterResult!
    var outputStreams: [String: OutputStream] = [:]
    var count: Int = 0
    var methodChannel: FlutterMethodChannel!
    private var relay: Relay!
    
    // Relay Delegates
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
    
    func relayResponse(success: Bool, responseStr: String, errorMessage: String?) {
        DispatchQueue.main.async {
            self.methodChannel?.invokeMethod("relayResponseMessage", arguments: "Relay Response: \(success) \(responseStr) \(errorMessage ?? "")");
        }
    }
    
    func streamCompletionPercentage(bytesCompleted: Double, totalBytes: Double) {
        let streamCompletionPercentage = (bytesCompleted/totalBytes)
        DispatchQueue.main.async {
            self.methodChannel?.invokeMethod("streamCompletionPercentage", arguments: streamCompletionPercentage);
        }
    }
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
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
                        result(FlutterError(code: "ERROR", message: "Relay not initialized", details: nil))
                    }
                }
                result(nil) // No result needed for initialization
            case "relayDataTask":
                if let args = call.arguments as? [String: Any],
                    let instance = self?.relay {
                    self?.relayDataTask(args, instance, result)
                } else {
                    result(FlutterError(code: "ERROR", message: "Relay not initialized or invalid parameters", details: nil))
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
                    result(FlutterError(code: "ERROR", message: "Relay not initialized or invalid parameters", details: nil))
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
        
        
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
}
