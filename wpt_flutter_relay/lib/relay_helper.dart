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
