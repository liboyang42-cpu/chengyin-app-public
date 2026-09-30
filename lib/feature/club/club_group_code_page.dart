import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/group_code_api.dart';
import '../../data/models/club_manage.dart';

/// 把团码图写进系统相册。
///
/// ★ 抽成可替换的函数是为了让测试能拦下这次系统调用 —— 相册权限弹框在
///   widget test 里不存在,直接调会静默失败并被当成「保存成功」的假绿。
Future<void> Function(Uint8List bytes, String name) saveGroupCodeToAlbum =
    (Uint8List bytes, String name) => Gal.putImageBytes(bytes, name: name);

/// 团核销码:主理人/管理员出示给合作商家扫码。码过期后自动换新,权限与团归属只由服务端判定。
///
/// 对齐小程序 `pages/club/group-code`:
/// - 带 activityId(正整数)→ 直接出码;
/// - 只带 topicId → 拉该路线可出码场次,唯一则自动出码,多个则先选场次,
///   空则提示「暂无可带队的场次」;
/// - 出码成功后倒计时,归零自动刷新出码。
class ClubGroupCodePage extends ConsumerStatefulWidget {
  const ClubGroupCodePage({
    super.key,
    this.activityId,
    this.topicId,
    this.activityName,
    this.topicName,
  });

  final int? activityId;
  final int? topicId;
  final String? activityName;
  final String? topicName;

  @override
  ConsumerState<ClubGroupCodePage> createState() => _ClubGroupCodePageState();
}

/// `invalid`(缺参)与 `noPermission`(无权限)都是**终态**:
/// 重试必然再失败,出路只有「进入俱乐部管理」 —— 对齐小程序 E-12 之后的四态。
/// 别把它们并进 `error`:那正是小程序修掉的老毛病(通用失败 + 重试,
/// 用户点一辈子也出不来)。
enum _GcState { loading, ready, error, selecting, empty, invalid, noPermission }

class _ClubGroupCodePageState extends ConsumerState<ClubGroupCodePage> {
  _GcState _state = _GcState.loading;
  String _errMsg = '';
  String _title = '';
  GroupCodeIssue? _issue;
  List<GroupCodeActivity> _options = const <GroupCodeActivity>[];
  int? _selectedActivityId;
  int _countdown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _title = widget.activityName?.isNotEmpty ?? false
        ? widget.activityName!
        : (widget.topicName?.isNotEmpty ?? false ? widget.topicName! : '本团');
    if (widget.activityId != null && widget.activityId! > 0) {
      _issueWithActivity();
    } else if (widget.topicId != null && widget.topicId! > 0) {
      _selectActivity();
    } else {
      setState(() => _state = _GcState.invalid);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _selectActivity() async {
    setState(() {
      _state = _GcState.loading;
      _errMsg = '';
    });
    final topicId = widget.topicId!;
    try {
      final activities = await ref
          .read(groupCodeApiProvider)
          .activities(topicId);
      if (!mounted) return;
      if (activities.isEmpty) {
        setState(() => _state = _GcState.empty);
        return;
      }
      if (activities.length == 1) {
        setState(() {
          _title = activities.first.name;
          _options = activities;
          _selectedActivityId = activities.first.id;
        });
        await _issueWith(activities.first.id);
        return;
      }
      setState(() {
        _options = activities;
        _state = _GcState.selecting;
      });
    } on GroupCodePermissionException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _GcState.noPermission;
        _errMsg = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _GcState.error;
        _errMsg = '场次加载失败';
      });
    }
  }

  Future<void> _issueWithActivity() async {
    _selectedActivityId = widget.activityId;
    await _issueWith(widget.activityId!);
  }

  Future<void> _issueWith(int activityId) async {
    _timer?.cancel();
    setState(() {
      _state = _GcState.loading;
      _errMsg = '';
    });
    try {
      final issue = await ref.read(groupCodeApiProvider).issue(activityId);
      if (!mounted) return;
      setState(() {
        _issue = issue;
        _state = _GcState.ready;
        _countdown = issue.ttlMs > 0 ? issue.ttlMs ~/ 1000 : 300;
      });
      _startCountdown();
    } on GroupCodePermissionException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _GcState.noPermission;
        _errMsg = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _GcState.error;
        _errMsg = '出码失败';
      });
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdown <= 1) {
        final selected = _selectedActivityId ?? widget.activityId;
        if (selected != null && selected > 0) {
          _issueWith(selected);
        }
        return;
      }
      setState(() => _countdown--);
    });
  }

  void _onSelectActivity(GroupCodeActivity a) {
    setState(() {
      _title = a.name;
      _selectedActivityId = a.id;
    });
    _issueWith(a.id);
  }

  void _onRetry() {
    final selected = _selectedActivityId ?? widget.activityId;
    if (selected != null && selected > 0) {
      _issueWith(selected);
    } else {
      _selectActivity();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CyPageTitle(
                _selecting ? '选择场次' : '团核销码',
                subtitle: switch (_state) {
                  _GcState.selecting || _GcState.empty => '选择本次带队场次',
                  _GcState.invalid => '请从俱乐部管理进入具体场次',
                  _GcState.noPermission => '当前账号不能出示这一场的团码',
                  _ => null,
                },
              ),
              Expanded(
                child: switch (_state) {
                  _GcState.selecting || _GcState.empty => _buildSelector(),
                  _GcState.invalid => _buildTerminal(
                    title: '缺少路线或场次信息',
                    sub: '返回俱乐部，选择具体场次后再出示团码',
                    icon: CupertinoIcons.exclamationmark_triangle,
                  ),
                  _GcState.noPermission => _buildTerminal(
                    title: '当前账号没有出码权限',
                    sub: _errMsg.isEmpty
                        ? '出码按下单归属只给主理人、管理员或本场领队，回俱乐部管理可以查看自己名下的场次。'
                        : _errMsg,
                    icon: CupertinoIcons.lock,
                  ),
                  _ => _buildVoucher(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _selecting =>
      _state == _GcState.selecting || _state == _GcState.empty;

  /// 终态页:说明 + 唯一的出路。没有重试键 —— 重试键在这里是骗人的。
  Widget _buildTerminal({
    required String title,
    required String sub,
    required IconData icon,
  }) {
    return Column(
      children: <Widget>[
        Expanded(
          child: StatusView(message: title, sub: sub, icon: icon, large: true),
        ),
        Padding(
          padding: const EdgeInsets.all(CyTokens.space4),
          child: CupertinoButton(
            key: const Key('group-code-manage'),
            onPressed: () => context.go(kClubsRoute),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('进入俱乐部管理'),
                SizedBox(width: CyTokens.space1),
                Icon(CupertinoIcons.chevron_forward, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelector() {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(CyTokens.space4),
      children: <Widget>[
        const CySectionTitle('选择场次'),
        const SizedBox(height: CyTokens.space1),
        Text(
          '选择本次带队场次',
          style: textTheme.labelSmall?.copyWith(color: CyTokens.textTertiary),
        ),
        const SizedBox(height: CyTokens.space1),
        Text(
          '团码只登记当前场次，不能跨场次使用。商家扫码后按人数核销。',
          style: textTheme.labelSmall?.copyWith(color: CyTokens.textTertiary),
        ),
        const SizedBox(height: CyTokens.space4),
        if (_state == _GcState.empty)
          const StatusView(
            message: '暂无可带队的场次',
            sub: '当前路线还没有开放报名的场次，开放后会显示在这里',
            icon: Icons.event_busy_outlined,
          )
        else
          ..._options.map(
            (GroupCodeActivity a) => Card(
              margin: const EdgeInsets.only(bottom: CyTokens.space2),
              child: CupertinoButton(
                onPressed: () => _onSelectActivity(a),
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                child: Padding(
                  padding: const EdgeInsets.all(CyTokens.space3),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          a.name,
                          style: textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: CyTokens.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVoucher() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CyTokens.space5),
        child: switch (_state) {
          _GcState.loading => const CupertinoActivityIndicator(),
          _GcState.error => StatusView(
            message: _errMsg.isEmpty ? '出码失败' : _errMsg,
            sub: '请重试',
            icon: CupertinoIcons.exclamationmark_triangle,
            onRetry: _onRetry,
          ),
          _ => _QrCard(title: '$_title · 团核销码', issue: _issue),
        },
      ),
    );
  }
}

class _QrCard extends ConsumerStatefulWidget {
  const _QrCard({required this.title, required this.issue});

  final String title;
  final GroupCodeIssue? issue;

  @override
  ConsumerState<_QrCard> createState() => _QrCardState();
}

class _QrCardState extends ConsumerState<_QrCard> {
  bool _saving = false;

  /// 保存到相册。小程序那张稿（335:1275）专门为它画了下载图标：
  /// 有些玩法要把码打印出来贴在站点上、现场靠纸质码核销 —— 不是装饰。
  Future<void> _saveToAlbum() async {
    final String url = widget.issue?.qrcodeUrl ?? '';
    if (url.isEmpty) {
      CyNativeNotice.show(context, '团码还没生成', isError: true);
      return;
    }
    setState(() => _saving = true);
    // ★ 下载失败与写相册失败**分开说**：前者是网络，重试有意义；
    //   后者是空间/系统权限，再说一遍「请重试」是骗人。
    final Uint8List bytes;
    try {
      bytes = await ref.read(groupCodeApiProvider).fetchQrBytes(url);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
      return;
    }
    try {
      await saveGroupCodeToAlbum(bytes, '团核销码');
      if (!mounted) return;
      CyNativeNotice.show(context, '已存到相册，可打印后贴在站点');
    } catch (_) {
      if (!mounted) return;
      CyNativeNotice.show(context, '没能存进相册，检查存储空间后再试', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final GroupCodeIssue? issue = widget.issue;
    final String qr = issue?.qrcodeUrl ?? '';
    final String code = issue?.code ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(widget.title, style: textTheme.titleMedium),
        const SizedBox(height: CyTokens.space2),
        Text(
          '仅限本场次合作商家扫码，登记本团接待',
          style: textTheme.labelSmall?.copyWith(color: CyTokens.textTertiary),
        ),
        const SizedBox(height: CyTokens.space4),
        // 白色码卡:商家扫码用,必须保留白底。
        Container(
          width: 260,
          height: 260,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          ),
          alignment: Alignment.center,
          clipBehavior: Clip.antiAlias,
          child: qr.isNotEmpty
              ? Image.network(
                  qr,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => _CodeFallback(code: code),
                )
              : _CodeFallback(code: code),
        ),
        // ★ 剩余时间**不上屏** —— 小程序那张稿没画,倒计时只是内部态
        //   (到期自动重出码);摆出来是在给一个没人答的承诺。
        if (qr.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space4),
          CyNativeButton(
            key: const Key('group-code-save'),
            label: _saving ? '保存中…' : '保存到相册',
            role: CyNativeButtonRole.secondary,
            loading: _saving,
            onPressed: _saving ? null : _saveToAlbum,
          ),
        ],
      ],
    );
  }
}

class _CodeFallback extends StatelessWidget {
  const _CodeFallback({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    if (code.isEmpty) {
      return const CupertinoActivityIndicator();
    }
    // 核销码回落态:等宽字体,商家要照着手输,能分清 0/O、1/l。
    return Text(
      code,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Color(0xFF0A0A0A),
      ),
    );
  }
}
