import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../data/api/roam_api.dart';
import '../../data/models/roam.dart';
import '../../data/models/roam_social.dart';
import 'city_stamp_logic.dart';

/// 城市贴纸 / 今日城市签(对齐小程序 `subpackageRoam/citystamp`)。
///
/// ★ **投一张换一张** —— 三步一页:拍照 → 写签 → 换票。
///   顺序不能反:先 `/api/roam/stamp/create` 存下自己那张,
///   再拿它的 id 去 `/api/roam/stamp/exchange` 换回别人那张。
///   没投成就不换(那是这个玩法唯一的资损面)。
///
/// ★ 外观是 iOS 原生化取舍:把「拖留言条进信箱 / 撕纸 / 刮开」这些
///   自绘手势换成原生控件与明确的按钮(点按查看、系统相册)。字段、文案、
///   状态与接口 1:1 照搬 —— 待视觉规则手册落地后统一。
class CityStampPage extends ConsumerStatefulWidget {
  const CityStampPage({super.key, this.kind = 'sign', this.place, this.shot});

  /// sticker = 城市贴纸;sign = 今日城市签。两端共用同一套实现,只有入口不同。
  final String kind;

  /// 从哪一站进来(漫游打卡后的这一站)。
  final String? place;

  /// 地图截图底垫(可选)。没有就画素底。
  final String? shot;

  @override
  ConsumerState<CityStampPage> createState() => _CityStampPageState();
}

enum _StampStep { cam, write, print }

class _CityStampPageState extends ConsumerState<CityStampPage> {
  _StampStep _step = _StampStep.cam;
  XFile? _photo;
  String _note = '';
  bool _sent = false;
  bool _sending = false;
  String _hint = '把它投进信箱,换回上一个人留的那张';
  bool _privacyExplained = false;

  bool _got = false;
  String _gotReason = '';
  String _gotPic = '';
  String _gotCaption = '';
  String _gotAt = '';
  int _serial = 0;
  bool _revealed = false;

  String get _title => widget.kind == 'sticker' ? '城市贴纸' : '今日城市签';
  String get _place => (widget.place ?? '').isEmpty ? '这一站' : widget.place!;
  String get _dateLabel {
    final DateTime now = DateTime.now();
    return '${now.month}.${now.day.toString().padLeft(2, '0')}';
  }

  String get _timeLabel {
    final DateTime now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    CyNativeNotice.show(context, message, isError: isError);
  }

  // ══ ① 拍照 ═════════════════════════════════════════════════════════

  Future<void> _takePhoto() async {
    if (!_privacyExplained) {
      final bool accepted =
          await showCupertinoModalPopup<bool>(
            context: context,
            builder: (BuildContext sheetContext) => CupertinoActionSheet(
              key: const Key('citystamp-camera-purpose'),
              title: const Text('开启相机拍一张'),
              message: const Text('相机只用于拍这一张城市贴纸,不会录音,也不会后台拍摄。'),
              actions: <Widget>[
                CupertinoActionSheetAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: const Text('继续'),
                ),
              ],
              cancelButton: CupertinoActionSheetAction(
                onPressed: () => Navigator.of(sheetContext).pop(false),
                child: const Text('暂不'),
              ),
            ),
          ) ??
          false;
      if (!mounted) return;
      if (!accepted) return;
      setState(() => _privacyExplained = true);
    }
    try {
      final XFile? file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
      );
      if (!mounted || file == null) return;
      setState(() {
        _photo = file;
        _step = _StampStep.write;
      });
    } catch (_) {
      _toast('相机没打开,检查一下相机权限', isError: true);
    }
  }

  void _retake() {
    if (_sent) return;
    setState(() {
      _photo = null;
      _step = _StampStep.cam;
    });
  }

  // ══ ② 写签 → 投进信箱(先存票,再换票)═════════════════════════════

  Future<void> _deliver() async {
    if (_sent || _sending) return;
    final XFile? photo = _photo;
    if (photo == null) {
      _toast('先拍一张');
      return;
    }
    setState(() {
      _sending = true;
      _hint = '换 TA 那张…';
    });
    final String idem =
        'cs-${DateTime.now().millisecondsSinceEpoch}-'
        '${(DateTime.now().microsecond % 100000)}';
    try {
      // 图先上传换成可外链的 URL,再存票 —— 本地路径别人看不到。
      final String url = await ref
          .read(publishApiProvider)
          .uploadImage(photo.path);
      final RoamStampCreated created = await ref
          .read(roamApiProvider)
          .createStamp(picUrl: url, caption: _note, idempotencyKey: idem);
      final RoamStampExchangeResult exchanged = await ref
          .read(roamApiProvider)
          .stampExchange(created.id);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sending = false;
        _step = _StampStep.print;
        _got = exchanged.exchanged;
        _gotReason = exchanged.reason ?? '';
        final RoamStamp? stamp = exchanged.stamp;
        _gotPic = stamp?.picUrl ?? '';
        _gotCaption = stamp?.caption ?? '';
        _gotAt = cityStampAtLabel(stamp?.createTime);
        _serial = stamp?.id ?? 0;
        _hint = exchanged.exchanged ? '看看 TA 留给你的那几句' : '';
      });
    } on RoamApiException catch (error) {
      _failDeliver(error.message);
    } catch (_) {
      _failDeliver('没存上,回去重试一次');
    }
  }

  /// 投出去了但没换成:说清断在哪一步,把按钮还回去,不把人困在空屏上。
  void _failDeliver(String message) {
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = false;
      _hint = message;
    });
    _toast(message, isError: true);
  }

  void _reveal() {
    setState(() {
      _revealed = true;
      _hint = '收下就走 · 你留的那句已经在等下一个人';
    });
  }

  Future<void> _saveToAlbum() async {
    if (_gotPic.isEmpty) {
      _toast('这张没有图可存');
      return;
    }
    try {
      final Response<List<int>> resp = await ref
          .read(dioClientProvider)
          .dio
          .get<List<int>>(
            _gotPic,
            options: Options(responseType: ResponseType.bytes),
          );
      final List<int> bytes = resp.data ?? const <int>[];
      if (bytes.isEmpty) throw StateError('empty');
      await Gal.putImageBytes(
        Uint8List.fromList(bytes),
        name: 'citystamp-$_serial',
      );
      _toast('已存进相册');
    } catch (_) {
      _toast('没存进相册,检查一下相册权限', isError: true);
    }
  }

  void _done() {
    if (_got && !_revealed) {
      _toast('先看看 TA 留给你的那句');
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CyTokens.bgPage,
      navigationBar: CupertinoNavigationBar(
        middle: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_title),
            Text(
              '$_dateLabel · $_place',
              style: TextStyle(
                fontSize: CyTokens.typeMicro,
                color: CyPalette.of(context).textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(child: _body()),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_step) {
      case _StampStep.cam:
        return _camStep();
      case _StampStep.write:
        return _writeStep();
      case _StampStep.print:
        return _printStep();
    }
  }

  Widget _camStep() {
    final CyPalette palette = CyPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CyTokens.pageX),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: palette.bgElevated,
                borderRadius: BorderRadius.circular(CyTokens.radiusXl),
                border: Border.all(color: palette.borderSubtle),
              ),
              child: Icon(
                CupertinoIcons.camera,
                size: 56,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space4),
            Text(
              '拍一张 $_place 的样子',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: CyTokens.typeSectionTitle,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: CyTokens.space1),
            Text(
              '投一张,换一张 —— 写是代价,看是回报。',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: CyTokens.typeBody,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _writeStep() {
    final CyPalette palette = CyPalette.of(context);
    return ListView(
      padding: const EdgeInsets.all(CyTokens.pageX),
      children: <Widget>[
        // 可点的照片卡是裸手势,不包语义 VoiceOver 只念静态文本(§9.4-10)。
        Semantics(
          button: true,
          label: '点击重拍',
          child: GestureDetector(
            onTap: _retake,
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                color: palette.bgElevated,
                borderRadius: BorderRadius.circular(CyTokens.radiusXl),
                border: Border.all(color: palette.borderSubtle),
              ),
              clipBehavior: Clip.antiAlias,
              child: _photo == null
                  ? const SizedBox.shrink()
                  : Image.file(
                      File(_photo!.path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
            ),
          ),
        ),
        const SizedBox(height: CyTokens.space1),
        Text(
          '点照片可以重拍',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: CyTokens.typeMicro,
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '给下一个来这里的人留一句',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: CyTokens.typeCardTitle,
                ),
              ),
            ),
            Text(
              '${_note.length}/$kCityStampCaptionMax',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: CyTokens.typeLabel,
              ),
            ),
          ],
        ),
        const SizedBox(height: CyTokens.space2),
        // 读屏文案照小程序 citystamp/index.wxml 的 aria-label(不显示,别改可见的字)。
        Semantics(
          label: '留一句给下一个人',
          child: CupertinoTextField(
            key: const Key('citystamp-note'),
            placeholder: '比如：巷口那家豆浆七点才开，别去早了',
            maxLength: kCityStampCaptionMax,
            maxLines: 3,
            enabled: !_sent,
            onChanged: (String value) => setState(() => _note = value),
          ),
        ),
        const SizedBox(height: CyTokens.space2),
        Row(
          children: <Widget>[
            Text(
              _place,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: CyTokens.typeLabel,
              ),
            ),
            const Spacer(),
            Text(
              _timeLabel,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: CyTokens.typeLabel,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _printStep() {
    final CyPalette palette = CyPalette.of(context);
    if (!_got) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(CyTokens.pageX),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _gotReason.isEmpty ? '还没有可以换的票' : _gotReason,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: CyTokens.typeSectionTitle,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: CyTokens.space2),
              Text(
                '你留的那句已经投进去了，等下一个人来换。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: CyTokens.typeBody,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(CyTokens.pageX),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(CyTokens.space4),
          decoration: BoxDecoration(
            color: palette.bgElevated,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: _ticketField('出发', _place, _timeLabel)),
                  Expanded(
                    child: _ticketField(
                      '签号',
                      cityStampSerialLabel(_serial),
                      '你是第几位',
                    ),
                  ),
                ],
              ),
              _hairline(palette),
              Row(
                children: <Widget>[
                  Expanded(child: _ticketField('留签人', '这一站的某个人', '')),
                  Expanded(child: _ticketField('留于', _gotAt, '')),
                ],
              ),
              _hairline(palette),
              if (_gotPic.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                  child: CyNetImage(_gotPic, height: 160),
                ),
              const SizedBox(height: CyTokens.space3),
              Text(
                '留给你的一句',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: CyTokens.typeMicro,
                ),
              ),
              const SizedBox(height: CyTokens.space1),
              if (!_revealed)
                CupertinoButton.filled(
                  key: const Key('citystamp-reveal'),
                  minimumSize: const Size.fromHeight(44),
                  onPressed: _reveal,
                  child: const Text('看看 TA 留下的那句'),
                )
              else
                Text(
                  _gotCaption.isEmpty ? '（这一位没留字，只留了一张照片）' : _gotCaption,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: CyTokens.typeBody,
                    height: 1.5,
                  ),
                ),
              const SizedBox(height: CyTokens.space3),
              _Barcode(
                bars: cityStampBarcode(_serial),
                color: palette.textPrimary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hairline(CyPalette palette) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: CyTokens.space3),
    color: palette.borderSubtle,
  );

  Widget _ticketField(String key, String value, String sub) {
    final CyPalette palette = CyPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          key,
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: CyTokens.typeMicro,
          ),
        ),
        const SizedBox(height: CyTokens.space1),
        Text(
          value,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: CyTokens.typeCardTitle,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (sub.isNotEmpty)
          Text(
            sub,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: CyTokens.typeMicro,
            ),
          ),
      ],
    );
  }

  Widget _footer() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.pageX,
        MediaQuery.viewPaddingOf(context).bottom + CyTokens.space2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_step == _StampStep.print && _got)
            CupertinoButton(
              key: const Key('citystamp-save-album'),
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              onPressed: () => unawaited(_saveToAlbum()),
              child: const Text('保存到相册'),
            ),
          if (_step == _StampStep.cam)
            SizedBox(
              height: CyTokens.btnH,
              child: CyNativeButton(
                key: const Key('citystamp-shoot'),
                label: '拍一张',
                onPressed: () => unawaited(_takePhoto()),
              ),
            )
          else if (_step == _StampStep.write)
            SizedBox(
              height: CyTokens.btnH,
              child: CyNativeButton(
                key: const Key('citystamp-deliver'),
                label: _sending ? '换 TA 那张…' : '投进信箱',
                loading: _sending,
                onPressed: _sending ? null : () => unawaited(_deliver()),
              ),
            )
          else
            SizedBox(
              height: CyTokens.btnH,
              child: CyNativeButton(
                key: const Key('citystamp-done'),
                label: '收下，出发',
                onPressed: _done,
              ),
            ),
          if (_hint.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space1),
            Text(
              _hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CyPalette.of(context).textSecondary,
                fontSize: CyTokens.typeLabel,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Barcode extends StatelessWidget {
  const _Barcode({required this.bars, required this.color});

  final List<({int width, int gap})> bars;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final ({int width, int gap}) bar in bars)
            Container(
              width: bar.width.toDouble(),
              margin: EdgeInsets.only(right: bar.gap.toDouble()),
              color: color,
            ),
        ],
      ),
    );
  }
}
