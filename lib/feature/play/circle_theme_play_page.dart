import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_action_sheet.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_system_text_input_alert.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/page_parity_api.dart';
import '../auth/auth_controller.dart';
import 'circle_write_readback.dart';

class CircleThemePlayPage extends ConsumerStatefulWidget {
  const CircleThemePlayPage({
    super.key,
    required this.topicId,
    this.themeCode,
    this.inviteCode,
  });

  final int topicId;
  final String? themeCode;
  final String? inviteCode;

  @override
  ConsumerState<CircleThemePlayPage> createState() =>
      _CircleThemePlayPageState();
}

class _CircleThemePlayPageState extends ConsumerState<CircleThemePlayPage> {
  Map<String, dynamic>? _card;
  List<Map<String, dynamic>> _offers = const <Map<String, dynamic>>[];
  Object? _sessionId;
  bool _loading = true;
  bool _busy = false;
  String _receipt = 'ready';
  String _receiptText = '';
  Map<String, dynamic>? _pendingReadback;
  String? _error;

  bool get _writesLocked => _busy || _receipt == 'unknown';
  bool get _missingTopic => widget.topicId <= 0;

  String get _storageKey => 'circle_session_${widget.topicId}';

  String get _pendingStorageKey {
    final int memberId = ref.read(authControllerProvider).user?.id ?? 0;
    return 'circle_unknown_write_v1_${memberId}_${widget.topicId}';
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (_missingTopic) {
      _loading = false;
      _error = '探索链接不完整';
      return;
    }
    final String? encoded = await ref
        .read(secureStorageProvider)
        .read(key: _pendingStorageKey);
    if (!mounted) return;
    if (encoded != null) {
      try {
        final Object? value = jsonDecode(encoded);
        if (value is Map<String, dynamic>) {
          setState(() {
            _receipt = 'unknown';
            _receiptText = '上次操作结果待确认，请先核对服务端记录';
            _pendingReadback = value;
          });
        }
      } on FormatException {
        await ref.read(secureStorageProvider).delete(key: _pendingStorageKey);
      }
    }
    await _load();
    final Map<String, dynamic>? pending = _pendingReadback;
    if (mounted && pending != null && _card != null) {
      await _finishReadback(pending);
    }
  }

  Future<void> _load() async {
    if (_missingTopic) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(pageParityApiProvider);
      Object? sessionId;
      Map<String, dynamic>? card;
      final String invite = widget.inviteCode?.trim().toUpperCase() ?? '';
      if (invite.isEmpty) {
        final String? stored = await ref
            .read(secureStorageProvider)
            .read(key: _storageKey);
        sessionId = stored;
        if (sessionId != null && '$sessionId'.isNotEmpty) {
          try {
            card = await api.circleCard(sessionId);
          } catch (_) {
            sessionId = null;
          }
        }
      }

      final List<Map<String, dynamic>> offers = await api.circleOffers(
        widget.topicId,
      );
      final bool supplyOpen = offers.length >= 3;
      if (invite.isNotEmpty) {
        if (!supplyOpen) {
          throw Exception('当前有效商家不足3家，城市实例暂不开放');
        }
        final joined = await api.joinCircleSession(invite);
        sessionId = joined['id'] ?? joined['sessionId'];
      } else if (sessionId == null) {
        if (!supplyOpen) {
          throw Exception('当前有效商家不足3家，城市实例暂不开放');
        }
        final created = await api.createCircleSession(widget.topicId);
        sessionId = created['id'] ?? created['sessionId'];
      }
      if (sessionId == null) throw Exception('无法开始本次探索');
      card ??= await api.circleCard(sessionId);
      await ref
          .read(secureStorageProvider)
          .write(key: _storageKey, value: '$sessionId');
      if (!mounted) return;
      setState(() {
        _sessionId = sessionId;
        _offers = offers;
        _card = card;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _leaveMissingTopic() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/feed');
    }
  }

  Future<void> _record(Map<String, dynamic> offer) async {
    final String? note = await showCySystemTextInputAlert(
      context: context,
      title: '加入私人记录卡',
      placeholder: '写一句只属于你的记录（选填）',
      confirmText: '保存',
      keyboardKind: CySystemKeyboardKind.text,
    );
    if (note == null || _sessionId == null) return;
    await _run(
      () => ref.read(pageParityApiProvider).recordCircle(<String, dynamic>{
        'sessionId': _sessionId,
        'offerId': offer['id'] ?? offer['offerId'],
        'note': note.trim(),
      }),
      '已加入私人记录卡',
      pending: <String, dynamic>{
        'kind': 'record',
        'offerId': offer['id'] ?? offer['offerId'],
      },
    );
  }

  Future<void> _openOfferAction(Map<String, dynamic> offer) async {
    final String value = '${offer['actionValue'] ?? ''}'.trim();
    if (value.isEmpty) {
      CyNativeNotice.show(context, '商家暂未填写行动入口', isError: true);
      return;
    }
    if (RegExp(r'^1\d{10}$').hasMatch(value)) {
      final bool opened = await launchUrl(Uri(scheme: 'tel', path: value));
      if (!opened && mounted) {
        CyNativeNotice.show(context, '暂时无法拨号', isError: true);
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) CyNativeNotice.show(context, '商家行动入口已复制');
  }

  Future<void> _answer(_CircleStage interaction) async {
    if (_sessionId == null) return;
    final String theme = (_card?['themeCode'] ?? widget.themeCode ?? '')
        .toString()
        .toUpperCase();
    String? value;
    if (theme == 'FITNESS' || theme == 'FRIENDS') {
      value = await _pickValue(interaction.title, <String, String>{
        for (final offer in _offers)
          if ('${offer['candidateCode'] ?? ''}'.isNotEmpty)
            '${offer['candidateCode']}':
                '${offer['candidateName'] ?? offer['supplyName'] ?? '探索商家'}',
      });
    } else if (theme == 'DATE') {
      value = await _pickValue(interaction.title, const <String, String>{
        'Q1': '最近一次觉得对方很可爱的瞬间？',
        'Q2': '最近一次被对方照顾到是什么时候？',
        'Q3': '下一次想一起认真做什么？',
      });
    } else if (theme == 'SHANGHAI') {
      final List<Map<String, dynamic>> records = _maps(_card?['records']);
      if (records.isEmpty) {
        CyNativeNotice.show(context, '请先记录一家商家', isError: true);
        return;
      }
      final List<String> pairs = <String>[];
      for (final record in records.take(4)) {
        final String code = '${record['candidateCode'] ?? ''}';
        if (code.isEmpty || !mounted) continue;
        final String? keyword = await _pickValue(
          '${record['candidateName'] ?? '已记录商家'} 像哪个上海词？',
          const <String, String>{
            '味道': '味道',
            '穿搭': '穿搭',
            '声音': '声音',
            '夜色': '夜色',
            '人情': '人情',
          },
        );
        if (keyword == null) return;
        pairs.add('$code:$keyword');
      }
      value = pairs.join(',');
    } else {
      value = await showCySystemTextInputAlert(
        context: context,
        // 标题给题面、输入框给引导语 —— 与小程序一致(题面在上、placeholder 是「写下这一刻」),
        // 原来把题面塞进 placeholder,一开始打字题目就没了。
        title: interaction.prompt,
        placeholder: '写下这一刻',
        confirmText: '保存',
        keyboardKind: CySystemKeyboardKind.text,
      );
    }
    if (value == null || value.trim().isEmpty) return;
    await _run(
      () => ref.read(pageParityApiProvider).answerCircle(<String, dynamic>{
        'sessionId': _sessionId,
        'stage': interaction.stage,
        'value': value!.trim(),
      }),
      '轻互动已保存',
      pending: <String, dynamic>{
        'kind': 'answer',
        'stage': interaction.stage,
        'value': value.trim(),
      },
    );
  }

  Future<String?> _pickValue(String title, Map<String, String> values) {
    if (values.isEmpty) return Future<String?>.value(null);
    return showCyNativeActionSheet<String>(
      context: context,
      title: title,
      actions: values.entries
          .map(
            (entry) =>
                CyNativeAction<String>(value: entry.key, label: entry.value),
          )
          .toList(growable: false),
    );
  }

  Future<void> _run(
    Future<Object?> Function() task,
    String done, {
    required Map<String, dynamic> pending,
  }) async {
    if (_writesLocked) return;
    setState(() {
      _busy = true;
      _receipt = 'submitting';
      _receiptText = '';
    });
    try {
      await ref
          .read(secureStorageProvider)
          .write(key: _pendingStorageKey, value: jsonEncode(pending));
      if (!mounted) return;
      _pendingReadback = pending;
      await task();
      if (!mounted) return;
      await _clearPendingReadback();
      if (!mounted) return;
      setState(() {
        _receipt = 'confirmed';
      });
      CyNativeNotice.show(context, done);
      await _load();
    } on PageParityApiException catch (e) {
      if (!mounted) return;
      if (pending['kind'] == 'record' && e.message.contains('已经记录过')) {
        await _clearPendingReadback();
        if (!mounted) return;
        setState(() {
          _receipt = 'confirmed';
        });
        await _refreshCard();
        return;
      }
      await _clearPendingReadback();
      if (!mounted) return;
      setState(() => _receipt = 'failed');
      CyNativeNotice.show(context, e.message, isError: true);
    } on DioException {
      await _resolveUnknown(pending);
    } catch (_) {
      await _resolveUnknown(pending);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolveUnknown(Map<String, dynamic> pending) async {
    if (!mounted) return;
    setState(() {
      _receipt = 'unknown';
      _receiptText = '操作结果待确认，请勿重复提交';
      _pendingReadback = pending;
    });
    final bool refreshed = await _refreshCard();
    if (!mounted) return;
    if (!refreshed) {
      setState(() {
        _receiptText = '还是没核对上，网络恢复后再试；期间请勿重复提交';
      });
      return;
    }
    await _finishReadback(pending);
  }

  Future<void> _finishReadback(Map<String, dynamic> pending) async {
    final bool landed = circleWriteLanded(_card, pending);
    if (!landed) {
      if (!mounted) return;
      setState(() {
        _receipt = 'unknown';
        _receiptText = '服务端暂未显示这一笔，请稍后再核对；期间请勿重复提交';
      });
      return;
    }
    await _clearPendingReadback();
    if (!mounted) return;
    setState(() {
      _receipt = 'confirmed';
      _receiptText = '';
    });
    CyNativeNotice.show(context, '刚才那一笔服务端已经记下了');
  }

  Future<void> _clearPendingReadback() async {
    await ref.read(secureStorageProvider).delete(key: _pendingStorageKey);
    _pendingReadback = null;
  }

  Future<void> _retryReceiptReadback() async {
    final Map<String, dynamic>? pending = _pendingReadback;
    if (_receipt != 'unknown' || pending == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _resolveUnknown(pending);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _refreshCard() async {
    final Object? sessionId = _sessionId;
    if (sessionId == null) return false;
    try {
      final Map<String, dynamic> card = await ref
          .read(pageParityApiProvider)
          .circleCard(sessionId);
      if (!mounted) return false;
      setState(() => _card = card);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _share() async {
    final String invite = (_card?['inviteCode'] ?? '').toString();
    await SharePlus.instance.share(
      ShareParams(
        title: '一起加入「${_card?['themeName'] ?? '自由探索'}」',
        text: invite.isEmpty ? '城瘾自由探索' : '城瘾同行邀请码：$invite',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> records = _maps(_card?['records']);
    final Set<String> recordedOfferIds = records
        .map((record) => '${record['offerId']}')
        .where((id) => id.isNotEmpty && id != 'null')
        .toSet();
    final bool completed = _card?['completed'] == true;
    final bool readOnly = completed || _offers.length < 3;
    final String theme = (_card?['themeCode'] ?? widget.themeCode ?? '')
        .toString()
        .toUpperCase();
    final int recordedCount =
        _number(_card?['recordedMerchantCount']) ?? records.length;
    final List<_CircleStage> interactions = _circleStages(theme)
        .where(
          (interaction) => switch (interaction.stage) {
            'PRE_CHOICE' || 'PRE_WISH' => recordedCount == 0,
            'POST_CHOICE' || 'NEXT_PICK' => recordedCount >= 2,
            _ => true,
          },
        )
        .toList(growable: false);
    final List<String> memoryLines = _memoryLines(_card, theme, _offers);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('自由探索'),
        trailing: _missingTopic
            ? null
            : Semantics(
                button: true,
                label: '邀请同行加入',
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _share,
                  child: const Icon(CupertinoIcons.share),
                ),
              ),
      ),
      child: SafeArea(
        bottom: false,
        child: _missingTopic
            ? _MissingCircleLink(onBack: _leaveMissingTopic)
            : _loading && _card == null
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CupertinoActivityIndicator(),
                    SizedBox(height: CyTokens.space3),
                    Text(
                      '正在准备自由探索',
                      style: TextStyle(
                        color: CyTokens.textTertiary,
                        fontSize: CyTokens.typeCaption,
                      ),
                    ),
                  ],
                ),
              )
            : _error != null && _card == null
            ? StatusView(
                message: '探索卡暂时不可用',
                sub: _error!,
                large: true,
                onRetry: _load,
              )
            : Material(
                color: Colors.transparent,
                child: RefreshIndicator.adaptive(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      CyTokens.pageX,
                      CyTokens.space3,
                      CyTokens.pageX,
                      CyTokens.space6,
                    ),
                    children: <Widget>[
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.only(bottom: CyTokens.space2),
                          child: Text(
                            '正在核对探索状态…',
                            style: TextStyle(
                              color: CyTokens.textTertiary,
                              fontSize: CyTokens.typeCaption,
                            ),
                          ),
                        ),
                      const Text(
                        '玩家自助记录',
                        style: TextStyle(
                          color: CyTokens.textTertiary,
                          fontSize: CyTokens.typeCaption,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: CyTokens.space1),
                      Text(
                        (_card?['themeName'] ?? _card?['name'] ?? '自由探索')
                            .toString(),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: CyTokens.space1),
                      Text(
                        _offers
                            .map((e) => e['candidateName'])
                            .whereType<String>()
                            .join('＋'),
                      ),
                      const SizedBox(height: CyTokens.space4),
                      if (_receipt == 'unknown' || _receiptText.isNotEmpty)
                        CupertinoListSection.insetGrouped(
                          children: <Widget>[
                            CupertinoListTile(
                              title: Text(
                                _receipt == 'unknown' ? '操作结果待确认' : '操作未生效',
                              ),
                              subtitle: Text(_receiptText),
                              trailing: _receipt == 'unknown'
                                  ? CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      onPressed: _busy
                                          ? null
                                          : _retryReceiptReadback,
                                      child: const Text('再核对一次'),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      Text(
                        '这次可探索的商家',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: CyTokens.space2),
                      ..._offers.map(
                        (
                          Map<String, dynamic> offer,
                        ) => CupertinoListSection.insetGrouped(
                          children: <Widget>[
                            CupertinoListTile(
                              title: Text(
                                (offer['candidateName'] ??
                                        offer['supplyName'] ??
                                        '探索商家')
                                    .toString(),
                              ),
                              subtitle: Text(
                                (offer['supplyName'] ??
                                        offer['description'] ??
                                        '到店后按提示自助记录')
                                    .toString(),
                              ),
                            ),
                            if ('${offer['actionValue'] ?? ''}'
                                .trim()
                                .isNotEmpty)
                              CupertinoListTile(
                                title: Text(
                                  RegExp(r'^1\d{10}$').hasMatch(
                                        '${offer['actionValue']}'.trim(),
                                      )
                                      ? '拨打预约电话'
                                      : '打开商家行动入口',
                                ),
                                trailing: const CupertinoListTileChevron(),
                                onTap: () => _openOfferAction(offer),
                              ),
                            CupertinoListTile(
                              title: Text(
                                recordedOfferIds.contains(
                                      '${offer['offerId'] ?? offer['id']}',
                                    )
                                    ? '已记录'
                                    : '自助记录这家',
                              ),
                              trailing: const CupertinoListTileChevron(),
                              onTap:
                                  readOnly ||
                                      _writesLocked ||
                                      recordedOfferIds.contains(
                                        '${offer['offerId'] ?? offer['id']}',
                                      )
                                  ? null
                                  : () => _record(offer),
                            ),
                          ],
                        ),
                      ),
                      if (interactions.isNotEmpty) ...<Widget>[
                        Text(
                          '主题轻互动',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: CyTokens.space2),
                        ...interactions.map(
                          (interaction) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: CyTokens.space2,
                            ),
                            child: CyNativeButton(
                              label: interaction.title,
                              width: double.infinity,
                              onPressed: readOnly || _writesLocked
                                  ? null
                                  : () => _answer(interaction),
                            ),
                          ),
                        ),
                      ],
                      if (!completed && !(_offers.length >= 3))
                        const Text('当前有效商家不足3家，本次记录暂不可继续；已有记录仍会保留。'),
                      if (completed) ...<Widget>[
                        const SizedBox(height: CyTokens.space4),
                        Text(
                          (_card?['memoryTitle'] ?? '共同记忆卡').toString(),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        ...memoryLines.map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(
                              top: CyTokens.space2,
                            ),
                            child: Text(e),
                          ),
                        ),
                        if (memoryLines.isEmpty) const Text('本次探索已完成，记录卡已生成。'),
                      ],
                      if (records.isNotEmpty) ...<Widget>[
                        const SizedBox(height: CyTokens.space4),
                        Text(
                          '我的探索记录',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        CupertinoListSection.insetGrouped(
                          children: records
                              .map(
                                (e) => CupertinoListTile(
                                  title: Text(
                                    (e['candidateName'] ??
                                            e['supplyName'] ??
                                            '已记录商家')
                                        .toString(),
                                  ),
                                  subtitle: Text((e['note'] ?? '').toString()),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ],
                      const SizedBox(height: CyTokens.space4),
                      const Text('本卡仅记录玩家自助选择，不代表商家确认到店、预约、核销或成交。'),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _MissingCircleLink extends StatelessWidget {
  const _MissingCircleLink({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.space6,
        136,
        CyTokens.space6,
        CyTokens.space6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            CupertinoIcons.info_circle,
            key: const Key('circle-missing-info'),
            size: 44,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: CyTokens.space4),
          Text(
            '探索链接不完整',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: CyTokens.space1_5),
          Text(
            '请从圈层主题或同行人分享的邀请重新进入',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: CyTokens.space4),
          CyNativeButton(label: '返回首页', onPressed: onBack, width: 128),
        ],
      ),
    ),
  );
}

List<Map<String, dynamic>> _maps(dynamic value) =>
    (value is List ? value : const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();

int? _number(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value');

List<String> _memoryLines(
  Map<String, dynamic>? card,
  String theme,
  List<Map<String, dynamic>> offers,
) {
  final List<String> supplied =
      ((card?['memoryLines'] as List<dynamic>?) ?? const <dynamic>[])
          .map((value) => '$value'.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
  if (supplied.isNotEmpty) return supplied;
  final Map<String, String> names = <String, String>{
    for (final offer in offers)
      if ('${offer['candidateCode'] ?? ''}'.isNotEmpty)
        '${offer['candidateCode']}':
            '${offer['candidateName'] ?? offer['supplyName'] ?? offer['candidateCode']}',
  };
  const Map<String, String> stageNames = <String, String>{
    'PRE_CHOICE': '出发前',
    'POST_CHOICE': '完成后',
    'SELF_MOMENT': '像自己的时刻',
    'QUESTION_CARD': '一起选的问题',
    'PRE_WISH': '今天最想做',
    'NEXT_PICK': '下次还会来',
  };
  final List<String> lines = <String>[];
  for (final answer in _maps(card?['answers'])) {
    final String value = '${answer['answerValue'] ?? answer['value'] ?? ''}'
        .trim();
    if (value.isEmpty) continue;
    if (theme == 'SHANGHAI') {
      for (final token in value.split(RegExp('[,，]'))) {
        final parts = token.split(':');
        if (parts.length == 2) {
          lines.add('${names[parts.first] ?? parts.first} · ${parts.last}');
        }
      }
      continue;
    }
    final String stage = '${answer['answerStage'] ?? answer['stage'] ?? ''}';
    final bool showMember =
        theme == 'FITNESS' ||
        theme == 'MIDLIFE' ||
        (theme == 'FRIENDS' && stage == 'PRE_WISH');
    final String member = showMember
        ? '${answer['memberLabel'] ?? ''}'.trim()
        : '';
    final String prefix = member.isEmpty ? '' : '$member · ';
    final String stageLabel = stageNames[stage] ?? '';
    lines.add(
      '$prefix${stageLabel.isEmpty ? '' : '$stageLabel：'}${names[value] ?? value}',
    );
  }
  return lines.toSet().toList(growable: false);
}

typedef _CircleStage = ({String stage, String title, String prompt});

List<_CircleStage> _circleStages(String theme) => switch (theme) {
  'FITNESS' => const <_CircleStage>[
    (stage: 'PRE_CHOICE', title: '出发前的选择', prompt: '今天最想长期坚持哪一项？'),
    (stage: 'POST_CHOICE', title: '完成后的选择', prompt: '现在最想长期坚持哪一项？'),
  ],
  'MIDLIFE' => const <_CircleStage>[
    (stage: 'SELF_MOMENT', title: '一句话记忆', prompt: '今天哪一刻最像我自己？'),
  ],
  'DATE' => const <_CircleStage>[
    (stage: 'QUESTION_CARD', title: '约会问题卡', prompt: '一起选一张，慢慢聊。'),
  ],
  'FRIENDS' => const <_CircleStage>[
    (stage: 'PRE_WISH', title: '出发前的愿望', prompt: '今天最想做哪件事？'),
    (stage: 'NEXT_PICK', title: '下次还会来', prompt: '共同投一个“下次还会来”。'),
  ],
  'SHANGHAI' => const <_CircleStage>[
    (stage: 'CITY_KEYWORDS', title: '保存城市关键词', prompt: '为已记录商家选一个词。'),
  ],
  _ => const <_CircleStage>[],
};
