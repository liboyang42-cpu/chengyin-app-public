import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_palette.dart';
import '../../../../core/theme/cy_tokens.dart';
import '../../../../core/widgets/cy_native_button.dart';
import '../../../../core/widgets/cy_net_image.dart';
import '../../../../core/widgets/cy_scratch.dart';
import '../playkit_fullscreen.dart';
import '../playkit_projection.dart';
import 'playkit_timer_parts.dart';

/// 票面字段 —— 与真源 `utils/playkit-view.js#buildDailySign` 逐字段对齐。
///
/// 真源头注原文:「票面全是服务端给的 —— 地址来自这一站,那句/照片来自**上一个来这里的人**
/// (没人来过是发起人的开场签)。**这里不写任何兜底文案**:签名为空时组件自己标
/// 『这一站的发起人』,那是标签不是数据」。
@immutable
class PlayKitDailySignTicket {
  const PlayKitDailySignTicket({
    required this.dateLabel,
    required this.address,
    required this.lines,
    required this.signer,
    required this.leftAt,
    required this.serialLabel,
    required this.textMax,
    required this.photoUrl,
    required this.claimed,
    required this.myText,
    required this.myPhotoUrl,
  });

  final String dateLabel;
  final String address;
  final List<String> lines;
  final String signer;
  final String leftAt;
  final String serialLabel;
  final int textMax;
  final String photoUrl;
  final bool claimed;
  final String myText;
  final String myPhotoUrl;

  /// 从服务端段里取。`now` 只为 `dateLabel` 用(真源 `buildDailySign(seg, now)`)。
  factory PlayKitDailySignTicket.fromSegment(
    Map<String, Object?> segment, {
    DateTime? now,
  }) {
    final DateTime date = now ?? DateTime.now();
    final String claimedDate = _text(segment['claimedDate']);
    final List<String> lines = (segment['lines'] is List
            ? segment['lines']! as List<Object?>
            : const <Object?>[])
        .map((Object? line) => '$line'.trim())
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);
    final int max = _int(segment['textMax']);
    return PlayKitDailySignTicket(
      dateLabel:
          '${_pad2(date.month)} / ${_pad2(date.day)}',
      address: _text(segment['address']),
      lines: lines,
      signer: _text(segment['signer']),
      leftAt: _text(segment['leftAt']),
      serialLabel: 'NO. ${_pad4(_int(segment['serial']))}',
      textMax: max > 0 ? max : 40,
      photoUrl: _text(segment['photoUrl']),
      claimed: claimedDate.isNotEmpty,
      myText: _text(segment['myText']),
      myPhotoUrl: _text(segment['myPhotoUrl']),
    );
  }

  /// 出票时刻。真源在打开这一刻现算(`pad2(now.getHours()) + ':' + pad2(now.getMinutes())`)。
  static String openTimeLabel(DateTime now) =>
      '${_pad2(now.hour)}:${_pad2(now.minute)}';
}

/// `cy-playkit-dailysign` · 今日城市签(接力签)。
///
/// 真源:`~/城瘾app/xcx-ref/pages/play/components/playkit-dailysign/`。
///
/// ## 三段式(真源 `_syncStep` 的原文口径)
/// 没刮开 → 等;刮开没留 → 写;留过 → 回看。
/// CTA 的可用性是三段里唯一一条规则:**写了字才能「留下」**;
/// 已经留过就只剩回看(真源那颗「出发」是关闭,App 侧关闭由宿主的退出钮负责)。
///
/// ## 与真源的已知差异(§7.2 accepted)
/// * **打印机与撕纸整段不做**:真源是「从槽里滚出来 → 按住往下拉 → 拉过 80px 撕断」
///   三拍动画(1.5s 出纸 + transform 跟手)。那一套是**外观与动效**,
///   按 D8「外观 iOS 27 原生」不做;「撕下来之前刮不动」这道门也随之取消 ——
///   票面直接就是撕下来的状态,刮层立刻可用。
/// * **条形码不做**:真源按签号做种子生成 46 根装饰条,是票面的「像」,不承载信息。
/// * **保存到相册不做**:真源那颗按钮在页面侧**没有处理分支**
///   (`pages/play/index.js#onPlayKitAction` 的 default → `ACTION_OF` 里没有
///   `dailysign:save`),点了不会有任何反应。补一个能用的是新功能,不是 1:1。
/// * **顺手拍一张不做**:真源上传走 `app.chooseImage`;App 侧上传要走 provider,
///   而缝的契约写明「组件不许自己去读 provider」,需要在宿主层补一个上传回调 ——
///   留到下一批。缺它不影响本条(真源自己标着「可不拍」)。
class PlayKitDailySignView extends StatefulWidget {
  const PlayKitDailySignView({super.key, required this.data});

  final PlayKitFullscreenContext data;

  @override
  State<PlayKitDailySignView> createState() => _PlayKitDailySignViewState();
}

class _PlayKitDailySignViewState extends State<PlayKitDailySignView> {
  final TextEditingController _text = TextEditingController();

  /// 刮开过了(真源 `_unlocked`)。已留过签的直接算揭开 ——
  /// 真源 `dailySignRevealState` 原文:「昨天擦过的今天重开还要再擦一遍是折磨」。
  bool _revealed = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final PlayKitCard card = widget.data.card;
    final PlayKitDailySignTicket ticket = PlayKitDailySignTicket.fromSegment(
      card.kit,
    );
    final String timeLabel = PlayKitDailySignTicket.openTimeLabel(
      DateTime.now(),
    );
    // 三段式:留过 → 回看;刮开没留 → 写;没刮开 → 等(留言条还没上来)
    final bool writing = (_revealed || ticket.claimed) && !ticket.claimed;
    final String draft = _text.text.trim();
    final bool canAccept =
        widget.data.enabled &&
        !widget.data.acting &&
        writing &&
        draft.isNotEmpty;

    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.space4,
            CyTokens.space3,
            CyTokens.space4,
            CyTokens.space5,
          ),
          children: <Widget>[
            PlayKitEyebrow('今日城市签', color: palette.textSecondary),
            const SizedBox(height: CyTokens.space3),
            _Ticket(
              ticket: ticket,
              palette: palette,
              timeLabel: timeLabel,
              revealed: ticket.claimed || _revealed,
              onReveal: () => setState(() => _revealed = true),
            ),
            const SizedBox(height: CyTokens.space3),
            Text(
              ticket.claimed
                  ? '留下了，下一个来的人会看到'
                  : writing
                  ? '也给下一个来这里的人留一句'
                  : '刮开 TA 留给你的那句',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: CyTokens.typeCaption,
              ),
            ),
            if (writing || ticket.claimed) ...<Widget>[
              const SizedBox(height: CyTokens.space4),
              _NoteSection(
                ticket: ticket,
                palette: palette,
                controller: _text,
                claimed: ticket.claimed,
                enabled: widget.data.enabled && !widget.data.acting,
                acting: widget.data.acting,
                canAccept: canAccept,
                onChanged: () => setState(() {}),
                onAccept: () => widget.data.onAction?.call(
                  PlayKitAction(
                    label: '留下,出发',
                    action: 'CLAIM_DAILY_SIGN',
                    // 真源 `serverPayload` 原文:`{text, photoUrl}`。
                    // photoUrl 见类注释(这一批不接顺手拍)。
                    payload: <String, Object?>{'text': draft, 'photoUrl': ''},
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 白色热敏小票的**信息顺序**(真源 `index.wxml` 的 `.ds__slip`),
/// 拉丝银打印机与锯齿纸头是外观,不做。
class _Ticket extends StatelessWidget {
  const _Ticket({
    required this.ticket,
    required this.palette,
    required this.timeLabel,
    required this.revealed,
    required this.onReveal,
  });

  final PlayKitDailySignTicket ticket;
  final CyPalette palette;
  final String timeLabel;
  final bool revealed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(CyTokens.space4),
    decoration: BoxDecoration(
      color: palette.bgSurface,
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      border: Border.all(color: palette.borderSubtle),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '今日城市签',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: CyTokens.typeBody,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              ticket.dateLabel,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: CyTokens.typeCaption,
              ),
            ),
          ],
        ),
        _Rule(palette: palette),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _Field(
                palette: palette,
                label: '出发',
                value: ticket.address.isEmpty ? '这一站' : ticket.address,
                note: timeLabel,
              ),
            ),
            Expanded(
              child: _Field(
                palette: palette,
                label: '签号',
                value: ticket.serialLabel,
                note: '你是第几位',
                alignEnd: true,
              ),
            ),
          ],
        ),
        _Rule(palette: palette),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _Field(
                palette: palette,
                label: '留签人',
                // 真源:「签名为空时组件自己标『这一站的发起人』,那是标签不是数据」
                value: ticket.signer.isEmpty ? '这一站的发起人' : ticket.signer,
              ),
            ),
            Expanded(
              child: _Field(
                palette: palette,
                label: '留于',
                value: ticket.leftAt.isEmpty ? '这一站开场' : ticket.leftAt,
              ),
            ),
          ],
        ),
        // 上一个人拍的那张:服务端给了才印,没给就没有这一段,不放占位图
        if (ticket.photoUrl.isNotEmpty) ...<Widget>[
          _Rule(palette: palette),
          ClipRRect(
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: CyNetImage(ticket.photoUrl, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            '${ticket.signer.isEmpty ? 'TA' : ticket.signer} 拍的 · ${ticket.leftAt}',
            style: TextStyle(
              color: palette.textTertiary,
              fontSize: CyTokens.typeCaption,
            ),
          ),
        ],
        // 签文没下发时整段不渲染:真源那里也是一个空容器 ——
        // 与其盖一层刮不出东西的雾,不如不出现。
        if (ticket.lines.isNotEmpty) ...<Widget>[
          _Rule(palette: palette),
          Text(
            '留给你的一句',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: CyTokens.typeCaption,
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          CyScratch(
            label: '留给你的一句',
            revealed: revealed,
            onReveal: onReveal,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: CyTokens.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final String line in ticket.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: CyTokens.space1),
                      child: Text(
                        line,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: CyTokens.typeSectionTitle,
                          height: CyTokens.leadingLoose,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// 留言条:写的时候是输入框 + 计数;留过之后只读回看。
class _NoteSection extends StatelessWidget {
  const _NoteSection({
    required this.ticket,
    required this.palette,
    required this.controller,
    required this.claimed,
    required this.enabled,
    required this.acting,
    required this.canAccept,
    required this.onChanged,
    required this.onAccept,
  });

  final PlayKitDailySignTicket ticket;
  final CyPalette palette;
  final TextEditingController controller;
  final bool claimed;
  final bool enabled;
  /// 「转圈」只表示这一单正在提交;整屏被禁不是忙碌。
  final bool acting;
  final bool canAccept;
  final VoidCallback onChanged;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(CyTokens.space4),
    decoration: BoxDecoration(
      color: palette.bgSurface,
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      border: Border.all(color: palette.borderSubtle),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                claimed ? '你留给下一个人的' : '给下一个来这里的人留一句',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: CyTokens.typeBody,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!claimed)
              Text(
                '${controller.text.length}/${ticket.textMax}',
                style: TextStyle(
                  color: palette.textTertiary,
                  fontSize: CyTokens.typeCaption,
                ),
              ),
          ],
        ),
        const SizedBox(height: CyTokens.space2),
        if (claimed) ...<Widget>[
          Text(
            ticket.myText,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: CyTokens.typeBody,
              height: CyTokens.leadingNormal,
            ),
          ),
          if (ticket.myPhotoUrl.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            ClipRRect(
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: CyNetImage(ticket.myPhotoUrl, fit: BoxFit.cover),
              ),
            ),
          ],
        ] else
          CupertinoTextField(
            key: const Key('playkit-daily-sign-note'),
            controller: controller,
            enabled: enabled,
            maxLength: ticket.textMax,
            maxLines: 3,
            minLines: 2,
            placeholder: '比如：巷口那家豆浆七点才开，别去早了',
            placeholderStyle: TextStyle(
              color: palette.textPlaceholder,
              fontSize: CyTokens.typeBody,
            ),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: CyTokens.typeBody,
            ),
            padding: const EdgeInsets.all(CyTokens.space2),
            decoration: BoxDecoration(
              color: palette.inputBgEmpty,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              border: Border.all(color: palette.borderSubtle),
            ),
            onChanged: (_) => onChanged(),
          ),
        if (!claimed) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          CyNativeButton(
            key: const Key('playkit-daily-sign-accept'),
            label: '留下,出发',
            width: double.infinity,
            loading: acting,
            onPressed: canAccept ? onAccept : null,
          ),
        ],
      ],
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.palette,
    required this.label,
    required this.value,
    this.note = '',
    this.alignEnd = false,
  });

  final CyPalette palette;
  final String label;
  final String value;
  final String note;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        label,
        style: TextStyle(
          color: palette.textTertiary,
          fontSize: CyTokens.typeCaption,
        ),
      ),
      const SizedBox(height: CyTokens.space1),
      Text(
        value,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: CyTokens.typeBody,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (note.isNotEmpty)
        Text(
          note,
          style: TextStyle(
            color: palette.textTertiary,
            fontSize: CyTokens.typeCaption,
          ),
        ),
    ],
  );
}

class _Rule extends StatelessWidget {
  const _Rule({required this.palette});

  final CyPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: CyTokens.space3),
    color: palette.borderSubtle,
  );
}

String _text(Object? value) => value?.toString().trim() ?? '';

String _pad2(int value) => value.toString().padLeft(2, '0');

String _pad4(int value) => value.toString().padLeft(4, '0');

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}
