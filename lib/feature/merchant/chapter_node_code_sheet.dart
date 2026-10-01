import '../../l10n/strings.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../data/api/merchant_api.dart';

/// 两种点位码。★ 不是同一张码的两种画法:
///   · [poster] = 店里贴的那张(长期有效,可保存到相册);
///   · [liveCheckin] = 现场出示给玩家扫的那张(秒级过期,到期自动换新)。
/// 小程序把它们放在不同页(`pages/topic/merchantinfo` / `pages/merchant/game-node`),
/// App 收在同一个弹层里,但取码端点、有效期、动作都各按各的来。
enum ChapterNodeCodeKind { poster, liveCheckin }

/// 把二维码图写进系统相册。
///
/// ★ 抽成函数是为了让页面在测试里能替换掉这次系统调用 ——
///   相册权限弹框在 widget test 里不存在,直接调会静默失败并被当成
///   「保存成功」的假绿。
Future<void> Function(Uint8List bytes, String name) saveQrImageToAlbum =
    (Uint8List bytes, String name) => Gal.putImageBytes(bytes, name: name);

/// 弹一张点位码(海报码 / 现场打卡码)。
Future<void> showChapterNodeCodeSheet(
  BuildContext context, {
  required int nodeId,
  required ChapterNodeCodeKind kind,
}) {
  return showCupertinoModalPopup<void>(
    context: context,
    semanticsDismissible: true,
    builder: (BuildContext sheetContext) =>
        _ChapterNodeCodeSheet(nodeId: nodeId, kind: kind),
  );
}

class _ChapterNodeCodeSheet extends ConsumerStatefulWidget {
  const _ChapterNodeCodeSheet({required this.nodeId, required this.kind});

  final int nodeId;
  final ChapterNodeCodeKind kind;

  @override
  ConsumerState<_ChapterNodeCodeSheet> createState() =>
      _ChapterNodeCodeSheetState();
}

class _ChapterNodeCodeSheetState extends ConsumerState<_ChapterNodeCodeSheet> {
  bool _loading = true;
  String? _error;
  bool _hasLocalCodeError = false;

  /// 图片地址(后端直接给图,客户端不生成二维码)。
  String _qrUrl = '';

  /// 图上没有图时的文本防伪码兜底(现场打卡码会带回 `code`)。
  String _code = '';

  /// 这张码还能用多久。live-checkin 才有;到 0 自动重新取。
  int _ttlSeconds = 0;
  Timer? _ticker;

  bool _saving = false;

  /// 异步取码的世代号:旧的响应回来时,只要世代已经翻过就丢掉。
  /// ★ 没有它,「刷新」按钮连点两下会让**先发后到**的那张旧码盖掉新码 ——
  ///   而打卡码是给玩家扫的,盖错会扫到一张已过期的码。
  int _epoch = 0;

  bool get _isLive => widget.kind == ChapterNodeCodeKind.liveCheckin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final int epoch = ++_epoch;
    _ticker?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _hasLocalCodeError = false;
      _qrUrl = '';
      _code = '';
      _ttlSeconds = 0;
    });
    try {
      final MerchantApi api = ref.read(merchantApiProvider);
      final Map<String, dynamic> data = _isLive
          ? await api.chapterNodeLiveCheckinCode(widget.nodeId)
          : await api.chapterNodePosterCode(widget.nodeId);
      if (!mounted || epoch != _epoch) return;
      final String url = '${data['qrcodeUrl'] ?? ''}'.trim();
      final String code = '${data['code'] ?? ''}'.trim();
      if (url.isEmpty && code.isEmpty) {
        setState(() {
          _loading = false;
          _error = '打卡码暂时没能生成';
          _hasLocalCodeError = true;
        });
        return;
      }
      final int ttlMs = _isLive ? (data['ttlMs'] as num?)?.toInt() ?? 60000 : 0;
      setState(() {
        _loading = false;
        _qrUrl = url;
        _code = code;
        // ★ ttlMs 有可能是 0/负数(后端没给或时钟口径不同)——
        //   那样不摆倒计时,也别立刻当成"已过期"反复重取。
        _ttlSeconds = ttlMs > 0 ? (ttlMs / 1000).ceil() : 0;
      });
      if (_isLive) _startTicker();
    } catch (e) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    if (_ttlSeconds <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_ttlSeconds <= 1) {
        t.cancel();
        // 到期自己换新 —— 让商家手动刷新等于给玩家一张过期码。
        _load();
        return;
      }
      setState(() => _ttlSeconds -= 1);
    });
  }

  Future<void> _saveToAlbum() async {
    if (_qrUrl.isEmpty) {
      CyNativeNotice.show(context, stringsOf(context).merchantChapterCodeNotReady, isError: true);
      return;
    }
    final imageName = _isLive ? stringsOf(context).merchantChapterCodeLive : stringsOf(context).merchantChapterCodeStore;
    setState(() => _saving = true);
    try {
      final Uint8List bytes = await ref
          .read(merchantApiProvider)
          .fetchImageBytes(_qrUrl);
      await saveQrImageToAlbum(bytes, imageName);
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).merchantChapterCodeSaved);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return CupertinoPopupSurface(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space3,
            CyTokens.pageX,
            CyTokens.space4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Center(child: CySheetGrab()),
              const SizedBox(height: CyTokens.space3),
              Text(
                _isLive ? stringsOf(context).merchantChapterCodeLive : stringsOf(context).merchantChapterCodeStation,
                textAlign: TextAlign.center,
                style: t.titleMedium,
              ),
              const SizedBox(height: CyTokens.space1),
              Text(
                _isLive
                    ? stringsOf(context).merchantChapterCodeLiveHint
                    : stringsOf(context).merchantChapterCodePosterHint,
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: CyTokens.space4),
              _codeCard(p, t),
              const SizedBox(height: CyTokens.space4),
              if (!_isLive)
                CyNativeButton(
                  key: const Key('chapter-node-code-save'),
                  label: _saving ? stringsOf(context).merchantChapterCodeSaving : stringsOf(context).merchantChapterCodeSave,
                  role: CyNativeButtonRole.secondary,
                  loading: _saving,
                  onPressed: _loading || _error != null || _saving
                      ? null
                      : _saveToAlbum,
                ),
              if (_isLive) ...<Widget>[
                if (_ttlSeconds > 0)
                  Text(
                    stringsOf(context).merchantChapterCodeCountdown(_ttlSeconds),
                    key: const Key('chapter-node-code-countdown'),
                    textAlign: TextAlign.center,
                    style: t.bodySmall?.copyWith(color: p.textTertiary),
                  ),
                const SizedBox(height: CyTokens.space2),
                CyNativeButton(
                  key: const Key('chapter-node-code-refresh'),
                  label: stringsOf(context).merchantChapterCodeRefresh,
                  role: CyNativeButtonRole.secondary,
                  onPressed: _loading ? null : _load,
                ),
              ],
              const SizedBox(height: CyTokens.space2),
              CupertinoButton(
                key: const Key('chapter-node-code-close'),
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(stringsOf(context).merchantChapterCodeClose),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _codeCard(CyPalette p, TextTheme t) {
    // ★ 码卡恒浅色:扫码对比度是物理要求,深色底上放浅码会让部分机型扫不出来。
    const Color cardBg = Color(0xFFFFFFFF);
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 220,
            child: Center(
              child: _loading
                  ? const CupertinoActivityIndicator(radius: 14)
                  : _error != null
                  ? Text(
                      _hasLocalCodeError ? stringsOf(context).merchantChapterCodeMissing : _error!,
                      key: const Key('chapter-node-code-error'),
                      textAlign: TextAlign.center,
                      style: t.bodyMedium?.copyWith(color: p.textSecondary),
                    )
                  : _qrUrl.isNotEmpty
                  ? CyNetImage(
                      _qrUrl,
                      key: const Key('chapter-node-code-image'),
                      width: 220,
                      height: 220,
                      fit: BoxFit.contain,
                    )
                  : SelectableText(
                      _code,
                      key: const Key('chapter-node-code-text'),
                      textAlign: TextAlign.center,
                      style: t.headlineSmall,
                    ),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            CupertinoButton(
              key: const Key('chapter-node-code-retry'),
              padding: EdgeInsets.zero,
              minimumSize: const Size(88, 44),
              onPressed: _load,
              child: Text(stringsOf(context).merchantChapterCodeRetry),
            ),
          ],
        ],
      ),
    );
  }
}
