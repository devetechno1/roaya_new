import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:active_ecommerce_cms_demo_app/helpers/main_helpers.dart';
import 'package:active_ecommerce_cms_demo_app/locale/custom_localization.dart';
import 'package:active_ecommerce_cms_demo_app/main.dart';
import 'package:active_ecommerce_cms_demo_app/middlewares/group_middleware.dart';
import 'package:active_ecommerce_cms_demo_app/middlewares/middleware.dart';
import 'package:active_ecommerce_cms_demo_app/repositories/aiz_api_response.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_config.dart';
import '../custom/toast_component.dart';

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName(
    'downloader_send_port',
  );
  send?.send([id, status, progress]);
}

class ApiRequest {
  static Future<http.Response> get({
    required String url,
    Map<String, String>? headers,
    Middleware? middleware,
    GroupMiddleware? groupMiddleWare,
  }) async {
    final Uri uri = Uri.parse(url);
    final Map<String, String> headerMap = commonHeader;
    headerMap.addAll(currencyHeader);
    if (headers != null) {
      headerMap.addAll(headers);
    }
    if (kDebugMode) print("api request url: $url headers: $headerMap");
    final response = await http.get(uri, headers: headerMap);
    if (kDebugMode) log("api response url: $url response: ${response.body}");
    return AIZApiResponse.check(
      response,
      middleware: middleware,
      groupMiddleWare: groupMiddleWare,
    );
  }

  static Future<http.Response> post({
    required String url,
    Map<String, String>? headers,
    required String body,
    Middleware? middleware,
    GroupMiddleware? groupMiddleWare,
  }) async {
    final Uri uri = Uri.parse(url);
    final Map<String, String> headerMap = commonHeader;
    headerMap.addAll(currencyHeader);
    if (headers != null) {
      headerMap.addAll(headers);
    }
    if (kDebugMode)
      log("post api request url: $url headers: $headerMap body: $body");
    final response = await http.post(uri, headers: headerMap, body: body);
    if (kDebugMode)
      log("post api response url: $url response: ${response.body}");
    return AIZApiResponse.check(
      response,
      middleware: middleware,
      groupMiddleWare: groupMiddleWare,
    );
  }

  static Future<http.Response> delete({
    required String url,
    Map<String, String>? headers,
    Middleware? middleware,
    GroupMiddleware? groupMiddleWare,
  }) async {
    final Uri uri = Uri.parse(url);
    final Map<String, String> headerMap = commonHeader;
    headerMap.addAll(currencyHeader);
    if (headers != null) {
      headerMap.addAll(headers);
    }
    final response = await http.delete(uri, headers: headerMap);
    return AIZApiResponse.check(
      response,
      middleware: middleware,
      groupMiddleWare: groupMiddleWare,
    );
  }

  /// Downloads file from the given [endPoint] and saves it to a local directory.
  /// Returns the task ID if the download is successfully initiated, otherwise returns null.
  static Future<String?> downloadFile(String endPoint) async {
    _init();

    final String folder = await _createFolder();
    try {
      ToastComponent.showDialog(
        "download_started".tr(),
        color: Colors.green,
        gravity: ToastGravity.BOTTOM,
      );
      // محتاج اشغل فاير بيز crashlitics عشان اشوف الاخطاء اللي بتحصل في الداونلود او في اي ريكويست
      final String? taskId = await FlutterDownloader.enqueue(
        url: AppConfig.BASE_URL + endPoint,
        openFileFromNotification: true,
        saveInPublicStorage: true,
        showNotification: true,
        headers: commonHeader,
        savedDir: folder,
      );
      _close();
      return taskId;
    } on Exception catch (e) {
      ToastComponent.showDialog("download_failed".tr(), isError: true);

      recordError(e, StackTrace.current);

      print("e.toString()");
      print(e.toString());
    }
    _close();
    return null;
  }

  static Future<String> _createFolder() async {
    String mPath = "storage/emulated/0/Download/";
    if (Platform.isIOS) {
      final Directory iosPath = await getApplicationDocumentsDirectory();
      mPath = iosPath.path;
    }
    final Directory dir = Directory(mPath);

    final PermissionStatus status = await Permission.storage.status;
    if (!status.isGranted) {
      await Permission.storage.request();
    }

    await dir.create(recursive: true);
    return dir.path;
  }

  static void _init() {
    final ReceivePort _port = ReceivePort();

    IsolateNameServer.registerPortWithName(
      _port.sendPort,
      'downloader_send_port',
    );

    FlutterDownloader.registerCallback(downloadCallback);
  }

  static void _close() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
  }
}
