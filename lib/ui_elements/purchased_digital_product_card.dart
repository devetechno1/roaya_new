import 'dart:isolate';
import 'dart:ui';

import 'package:active_ecommerce_cms_demo_app/app_config.dart';
import 'package:active_ecommerce_cms_demo_app/custom/toast_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';

import 'package:active_ecommerce_cms_demo_app/locale/custom_localization.dart';

import '../repositories/api-request.dart';

class PurchasedDigitalProductCard extends StatefulWidget
    with WidgetsBindingObserver {
  final int? id;
  final String? image;
  final String? name;

  PurchasedDigitalProductCard({Key? key, this.id, this.image, this.name})
      : super(key: key);

  @override
  _PurchasedDigitalProductCardState createState() =>
      _PurchasedDigitalProductCardState();
}

class _PurchasedDigitalProductCardState
    extends State<PurchasedDigitalProductCard> {
  final ReceivePort _port = ReceivePort();

  @pragma('vm:entry-point')
  static void downloadCallback(String id, int status, int progress) {
    final SendPort? send =
        IsolateNameServer.lookupPortByName('downloader_send_port');
    send?.send([id, status, progress]);
  }

  @override
  void initState() {
    super.initState();
    IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');
    _port.listen((dynamic data) {
      if (data[2] >= 100) {
        ToastComponent.showDialog(
          'file_download_success'.tr(context: context),
        );
      }
      setState(() {});
    });
    FlutterDownloader.registerCallback(downloadCallback);
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // decoration: BoxDecoration(color: Colors.white),
      child: Column(
        children: <Widget>[
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              width: double.infinity,
              child: ClipRRect(
                clipBehavior: Clip.hardEdge,
                borderRadius: BorderRadius.circular(AppDimensions.radiusNormal),
                child: FadeInImage.assetNetwork(
                  placeholder: AppImages.placeholder,
                  image: widget.image ?? AppImages.placeholder,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            child: Text(
              widget.name ?? 'no_name'.tr(context: context),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: const TextStyle(
                color: Color(0xff6B7377),
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          InkWell(
            onTap: () {
              ApiRequest.downloadFile(
                "/purchased-products/download/${widget.id}",
              );
            },
            child: Container(
              height: 24,
              width: 170,
              margin: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xffE5411C),
                borderRadius:
                    BorderRadius.circular(AppDimensions.radiusSmallExtra),
              ),
              child: Center(
                child: Text(
                  'download'.tr(context: context),
                  style: const TextStyle(
                    fontFamily: 'Public Sans',
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    height: 1.8,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
