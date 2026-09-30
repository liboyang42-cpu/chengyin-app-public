import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_system_text_input_alert.dart';

/// 据点核销:扫玩家出示的据点码 → 给他发券。
///
/// ★★★ 后端的拒绝话术**自带可执行信息**,一律原文透传(API 注释写死了):
///   · 「玩家未到店打卡,或该券已核销」→ **那是保护不是故障**。
///     笼统换成「核销失败,请重试」会让商家一直重扫一张不可能成功的码;
///     换成「网络错误」更糟 —— 他会去查 wifi。
///   · 库存耗尽 → 后端会整体回滚,补货后可重扫,所以话里带着下一步。
///
/// ⇒ 这一页**不自己造任何失败文案**,只把后端那句原样摆出来。
class CityNodeRedeemPage extends ConsumerStatefulWidget {
  const CityNodeRedeemPage({super.key});

  @override
  ConsumerState<CityNodeRedeemPage> createState() => _CityNodeRedeemPageState();
}

class _CityNodeRedeemPageState extends ConsumerState<CityNodeRedeemPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handling = false;
  bool _ok = false;
  String? _msg;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    for (final Barcode b in capture.barcodes) {
      final String? raw = b.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;
      setState(() => _handling = true);
      await _controller.stop();
      await _redeem(raw.trim());
      return;
    }
  }

  Future<void> _redeem(String code) async {
    try {
      final String msg = await ref
          .read(roamApiProvider)
          .redeemCityNodeCode(code);
      if (!mounted) return;
      setState(() {
        _ok = true;
        // 成功也用后端原话:它会说清给玩家发了什么。
        _msg = msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ok = false;
        // ★ 原文透传。别加「请重试」——有些情况重试永远不会成功。
        _msg = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _next() async {
    setState(() {
      _handling = false;
      _msg = null;
    });
    await _controller.start();
  }

  /// 码扫不出时的手工回落(光线差 / 屏幕反光 / 玩家截图模糊)。
  Future<void> _manual() async {
    final String? code = await showCySystemTextInputAlert(
      context: context,
      title: '手动输入核销码',
      placeholder: '玩家出示的那串字符',
      confirmText: '核销',
      keyboardKind: CySystemKeyboardKind.ascii,
    );
    if (code == null || code.isEmpty || !mounted) return;
    setState(() => _handling = true);
    await _controller.stop();
    await _redeem(code);
  }

  @override
  Widget build(BuildContext context) {
    final p = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('据点核销'),
        trailing: CupertinoButton(
          key: const Key('citynode-manual'),
          onPressed: _manual,
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          child: Semantics(
            button: true,
            label: '手动输入',
            child: const Icon(CupertinoIcons.keyboard),
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('扫玩家的据点码'),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    MobileScanner(controller: _controller, onDetect: _onDetect),
                    if (_msg != null)
                      CityNodeRedeemResult(
                        ok: _ok,
                        message: _msg!,
                        onNext: _next,
                      ),
                    if (_handling && _msg == null)
                      ColoredBox(
                        color: p.overlay,
                        child: const Center(
                          child: CupertinoActivityIndicator(),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 结果浮层。★ 公开只为一件事:让「后端那句话有没有被原样显示」能被真渲染测到
/// —— 整页要相机,widget 测试里起不来。
class CityNodeRedeemResult extends StatelessWidget {
  const CityNodeRedeemResult({
    super.key,
    required this.ok,
    required this.message,
    required this.onNext,
  });

  final bool ok;
  final String message;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = CyPalette.of(context);
    return ColoredBox(
      color: p.overlay,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(CyTokens.space5),
          padding: const EdgeInsets.all(CyTokens.space5),
          decoration: BoxDecoration(
            color: p.bgSurface,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                ok ? Icons.check_circle : Icons.error_outline,
                size: 44,
                color: ok ? p.statusSuccess : p.statusDanger,
              ),
              const SizedBox(height: CyTokens.space3),
              Text(
                // ★ 后端原话,一个字不改。
                message,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: CyTokens.space4),
              SizedBox(
                width: double.infinity,
                child: CyNativeButton(
                  key: const Key('citynode-next'),
                  onPressed: onNext,
                  label: '继续扫描',
                  width: double.infinity,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
