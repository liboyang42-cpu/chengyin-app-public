import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

/// 足迹卡的平台边界：页面只负责生成 PNG，系统相册与分享面板
/// 由这里承接。测试可注入记录实现，不伪造成功 Toast。
/// ★ 分享出去的是**这张图本身**，所以不接小程序的足迹分享快照
/// （`/api/roam/share/snapshot`、`/api/roam/share/revoke`）：那两条的令牌只被
/// 微信小程序页面 `subpackageRoam/session/index` 的 `shareToken` 入口消费
/// （分享 path 出了微信打不开），App 没有承载令牌的入站路由 —— 发了也没人能用，
/// 还会白传一份轨迹。决策与证据登记在 `tool/endpoint_parity.py` 的
/// DOCUMENTED_EQUIVALENTS。
abstract interface class RoamShareActions {
  Future<void> saveToAlbum(Uint8List pngBytes, {required String fileName});

  Future<void> share(
    Uint8List pngBytes, {
    required String fileName,
    required Rect sharePositionOrigin,
  });
}

abstract interface class RoamShareCardEncoder {
  Future<Uint8List> capture(RenderRepaintBoundary boundary);
}

final class BoundaryRoamShareCardEncoder implements RoamShareCardEncoder {
  const BoundaryRoamShareCardEncoder();

  @override
  Future<Uint8List> capture(RenderRepaintBoundary boundary) async {
    final Image image = await boundary.toImage(pixelRatio: 3);
    try {
      final ByteData? data = await image.toByteData(
        format: ImageByteFormat.png,
      );
      if (data == null) throw StateError('足迹卡生成失败');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}

final class SystemRoamShareActions implements RoamShareActions {
  const SystemRoamShareActions();

  @override
  Future<void> saveToAlbum(Uint8List pngBytes, {required String fileName}) {
    return Gal.putImageBytes(pngBytes, name: fileName);
  }

  @override
  Future<void> share(
    Uint8List pngBytes, {
    required String fileName,
    required Rect sharePositionOrigin,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile.fromData(pngBytes, mimeType: 'image/png', name: fileName),
        ],
        fileNameOverrides: <String>[fileName],
        subject: '我的城市漫游足迹',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}
