import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../data/models/club.dart';
import '../../data/models/publish_draft.dart';
import 'publish_draft_logic.dart';
import 'publish_pro_utils.dart';

/// 票务与档期页(对齐小程序 fabu/step3.wxml,第 2 页)。
/// 档期 + 商家池开关(仅俱乐部主理人可见)+ 票种列表与就地展开的票种编辑器
/// + 自玩票(仅城市定向)。
class PublishTicketTab extends StatefulWidget {
  const PublishTicketTab({
    super.key,
    required this.draft,
    required this.merchantPoolEditable,
    required this.myClubs,
    required this.onChanged,
  });

  final PublishDraft draft;
  final bool merchantPoolEditable;
  final List<Club> myClubs;
  final VoidCallback onChanged;

  @override
  State<PublishTicketTab> createState() => _PublishTicketTabState();
}

class _PublishTicketTabState extends State<PublishTicketTab> {
  int _editingIndex = -1;

  PublishDraft get draft => widget.draft;
  bool get isCity => draft.productType == kProductCity;

  void _openEditor(int index) {
    setState(() {
      if (index >= draft.tickets.length) {
        draft.tickets.add(defaultTicket(draft.productType));
      }
      _editingIndex = index;
      widget.onChanged();
    });
  }

  void _saveTicket() {
    final ticket = draft.tickets[_editingIndex];
    if (!canSaveTicket(ticket)) {
      if (textOf(ticket.name).isEmpty) {
        _toast('请填写票种名称');
      } else {
        final issue = cityOrientationScheduleIssues(ticket);
        if (issue.isNotEmpty) {
          _toast(issue.first.message);
        } else {
          _toast('请选择集合地点');
        }
      }
      return;
    }
    setState(() {
      _editingIndex = -1;
      widget.onChanged();
    });
  }

  void _removeTicket(int index) {
    setState(() {
      draft.tickets.removeAt(index);
      if (_editingIndex == index) _editingIndex = -1;
      widget.onChanged();
    });
  }

  void _toast(String text) {
    CyNativeNotice.show(context, text, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(height: CyTokens.space3),
        CySectionTitle(widget.merchantPoolEditable ? '档期与商家池' : '档期'),
        SizedBox(height: CyTokens.space3),
        _scheduleCard(),
        if (widget.merchantPoolEditable) ...<Widget>[
          SizedBox(height: CyTokens.space3),
          _merchantPoolCard(),
        ],
        SizedBox(height: CyTokens.space4),
        const CySectionTitle('票务'),
        SizedBox(height: CyTokens.space3),
        for (var i = 0; i < draft.tickets.length; i++) _ticketCard(i),
        if (_editingIndex >= 0 && _editingIndex < draft.tickets.length)
          _TicketEditor(
            key: ValueKey<int>(_editingIndex),
            ticket: draft.tickets[_editingIndex],
            isCity: isCity,
            onChanged: widget.onChanged,
            onSave: _saveTicket,
            onCancel: () => setState(() => _editingIndex = -1),
          ),
        if (_editingIndex < 0) _addTicketRow(),
        if (isCity && draft.tickets.isNotEmpty) ...<Widget>[
          SizedBox(height: CyTokens.space4),
          const CySectionTitle('自玩票'),
          SizedBox(height: CyTokens.space3),
          _SelfPlayCard(draft: draft, onChanged: widget.onChanged),
        ],
      ],
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        border: Border.all(color: CyPalette.of(context).borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _cardRow({
    required String title,
    required String value,
    IconData? icon,
    Widget? trailing,
    VoidCallback? onTap,
    bool required = false,
  }) {
    final Widget row = Padding(
      padding: EdgeInsets.symmetric(vertical: CyTokens.space2),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 20, color: CyPalette.of(context).textPrimary),
            SizedBox(width: CyTokens.space3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      if (required)
                        TextSpan(
                          text: '* ',
                          style: TextStyle(
                            color: CyPalette.of(context).statusDanger,
                          ),
                        ),
                      TextSpan(
                        text: title,
                        style: TextStyle(
                          fontSize: CyTokens.typeBody,
                          color: CyPalette.of(context).textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
          if (onTap != null)
            Text('选择 ›', style: TextStyle(color: CyPalette.of(context).textTertiary)),
        ],
      ),
    );
    if (onTap == null) return row;
    return CupertinoButton(
      minimumSize: const Size.fromHeight(44),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: row,
    );
  }

  Widget _divider() => Divider(height: 1, color: CyPalette.of(context).borderSubtle);

  Widget _scheduleCard() {
    return _card(
      children: <Widget>[
        _cardRow(
          icon: Icons.calendar_today_outlined,
          title: '开始日期',
          value: draft.startDate.isEmpty ? '选择开始日期' : draft.startDate,
          required: true,
          onTap: () async {
            final d = await pickDate(context);
            if (d == null) return;
            setState(() {
              draft.startDate = fmtDate(d);
              widget.onChanged();
            });
          },
        ),
        _divider(),
        _cardRow(
          icon: Icons.calendar_today_outlined,
          title: '结束日期',
          value: draft.endDate.isEmpty ? '选择结束日期' : draft.endDate,
          required: true,
          onTap: () async {
            final d = await pickDate(context);
            if (d == null) return;
            setState(() {
              draft.endDate = fmtDate(d);
              widget.onChanged();
            });
          },
        ),
        if (!isCity) ...<Widget>[
          _divider(),
          _cardRow(
            icon: Icons.schedule_outlined,
            title: '招商截止日期',
            value: draft.recruitDeadline == null
                ? '自由探索需先完成招商与锁价'
                : draft.recruitDeadline!,
            required: true,
            onTap: () async {
              final d = await pickDate(context);
              if (d == null) return;
              setState(() {
                draft.recruitDeadline = fmtDate(d);
                widget.onChanged();
              });
            },
          ),
        ],
      ],
    );
  }

  Widget _merchantPoolCard() {
    return _card(
      children: <Widget>[
        _cardRow(
          icon: Icons.storefront_outlined,
          title: '开放给商家市场',
          value: draft.openMerchantPool ? '商家可报名承接' : '仅自己发布管理',
          trailing: CupertinoSwitch(
            value: draft.openMerchantPool,
            onChanged: (v) {
              setState(() {
                draft.openMerchantPool = v;
                widget.onChanged();
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _ticketCard(int index) {
    final ticket = draft.tickets[index];
    final price = ticket.price ?? 0;
    return Container(
      margin: EdgeInsets.only(bottom: CyTokens.space3),
      decoration: BoxDecoration(
        border: Border.all(color: CyPalette.of(context).borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: CupertinoButton(
        minimumSize: const Size.fromHeight(44),
        padding: EdgeInsets.all(CyTokens.space3),
        onPressed: () => _openEditor(index),
        child: Padding(
          padding: EdgeInsets.zero,
          child: Row(
            children: <Widget>[
              Icon(
                Icons.confirmation_number_outlined,
                size: 20,
                color: CyPalette.of(context).textPrimary,
              ),
              SizedBox(width: CyTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      ticket.name.isEmpty ? '未命名票种' : ticket.name,
                      style: TextStyle(
                        fontSize: CyTokens.typeBody,
                        color: CyPalette.of(context).textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '${price > 0 ? '¥$price' : '免费'} · '
                      '${ticket.mode == 1 ? '城市定向' : '自由探索'} · '
                      '${ticket.totalStock} 张',
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        color: CyPalette.of(context).textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (draft.tickets.length > 1)
                Semantics(
                  button: true,
                  label: '删除票种',
                  child: ExcludeSemantics(
                    child: CupertinoButton(
                      minimumSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      onPressed: () => _removeTicket(index),
                      child: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: CyPalette.of(context).textTertiary,
                      ),
                    ),
                  ),
                ),
              Text('编辑 ›', style: TextStyle(color: CyPalette.of(context).textTertiary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addTicketRow() {
    return CupertinoButton(
      minimumSize: const Size.fromHeight(44),
      padding: EdgeInsets.zero,
      onPressed: () => _openEditor(draft.tickets.length),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: CyTokens.space3),
        child: Row(
          children: <Widget>[
            Icon(Icons.add, size: 18, color: CyPalette.of(context).textPrimary),
            SizedBox(width: CyTokens.space2),
            Text(
              draft.tickets.isEmpty ? '添加票种' : '添加新票种',
              style: TextStyle(
                fontSize: CyTokens.typeBody,
                color: CyPalette.of(context).textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 票种编辑器(就地展开)。独立 StatefulWidget:输入框持有自己的控制器,
/// 父层 setState 不会把光标抽走。
class _TicketEditor extends StatefulWidget {
  const _TicketEditor({
    super.key,
    required this.ticket,
    required this.isCity,
    required this.onChanged,
    required this.onSave,
    required this.onCancel,
  });

  final PublishTicket ticket;
  final bool isCity;
  final VoidCallback onChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  State<_TicketEditor> createState() => _TicketEditorState();
}

class _TicketEditorState extends State<_TicketEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.ticket.name,
  );
  late final TextEditingController _price = TextEditingController(
    text: widget.ticket.price == null ? '' : '${widget.ticket.price}',
  );
  late final TextEditingController _stock = TextEditingController(
    text: '${widget.ticket.totalStock}',
  );
  late final TextEditingController _team = TextEditingController(
    text: '${widget.ticket.teamSize}',
  );
  late final TextEditingController _desc = TextEditingController(
    text: widget.ticket.description,
  );

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _stock.dispose();
    _team.dispose();
    _desc.dispose();
    super.dispose();
  }

  PublishTicket get ticket => widget.ticket;

  BoxDecoration _inputDecoration() {
    final CyPalette palette = CyPalette.of(context);
    return BoxDecoration(
      color: palette.inputBgEmpty,
      border: Border.all(color: palette.borderSubtle),
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
    );
  }

  Future<void> _pickMeetingPoint() async {
    final poi = await context
        .push<({String name, double latitude, double longitude})>(
          '/publish/poi',
        );
    if (poi == null || !mounted) return;
    setState(() {
      ticket.meetingPoint = poi.name;
      ticket.meetingPointAddress = poi.name;
      ticket.meetingPointLongitude = poi.longitude.toString();
      ticket.meetingPointLatitude = poi.latitude.toString();
      widget.onChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCity = widget.isCity;
    return Container(
      margin: EdgeInsets.only(bottom: CyTokens.space3),
      padding: EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '编辑票种',
                style: TextStyle(
                  fontSize: CyTokens.typeLabel,
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
              CupertinoButton(
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                onPressed: widget.onCancel,
                child: Text(
                  '收起',
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: CyTokens.space3),
          _labelField(
            '票种名称',
            required: true,
            child: CupertinoTextField(
              key: const Key('ticket-editor-name'),
              controller: _name,
              onChanged: (v) {
                ticket.name = v;
                widget.onChanged();
              },
              maxLength: 20,
              textInputAction: TextInputAction.next,
              autocorrect: true,
              enableSuggestions: true,
              placeholder: '例如：早鸟票、团体票',
              padding: const EdgeInsets.all(CyTokens.space3),
              decoration: _inputDecoration(),
            ),
          ),
          SizedBox(height: CyTokens.space3),
          Row(
            children: <Widget>[
              Expanded(
                child: _labelField(
                  '票单价格 (¥)',
                  required: true,
                  child: CupertinoTextField(
                    key: const Key('ticket-editor-price'),
                    controller: _price,
                    onChanged: (v) {
                      // ★ 清空 = null(「没填」),不是 0(「免费」)—— 两种含义不能合并。
                      ticket.price = v.trim().isEmpty
                          ? null
                          : double.tryParse(v);
                      widget.onChanged();
                    },
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    placeholder: '0.00',
                    padding: const EdgeInsets.all(CyTokens.space3),
                    decoration: _inputDecoration(),
                  ),
                ),
              ),
              SizedBox(width: CyTokens.space3),
              Expanded(
                child: _labelField(
                  '发行数量 (张)',
                  child: CupertinoTextField(
                    key: const Key('ticket-editor-stock'),
                    controller: _stock,
                    onChanged: (v) {
                      ticket.totalStock = int.tryParse(v.trim()) ?? 0;
                      widget.onChanged();
                    },
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    textInputAction: TextInputAction.next,
                    placeholder: '100',
                    padding: const EdgeInsets.all(CyTokens.space3),
                    decoration: _inputDecoration(),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: CyTokens.space3),
          _box(
            children: <Widget>[
              _row(
                icon: Icons.schedule_outlined,
                title: '售票开始',
                value: ticket.saleStartTime.isEmpty
                    ? '选择日期'
                    : ticket.saleStartTime,
                required: true,
                onTap: () async {
                  final d = await pickDate(context);
                  if (d == null) return;
                  setState(() {
                    ticket.saleStartTime = fmtDate(d);
                    widget.onChanged();
                  });
                },
              ),
              _hr(),
              _row(
                icon: Icons.schedule_outlined,
                title: '售票结束',
                value: ticket.saleEndTime.isEmpty ? '选择日期' : ticket.saleEndTime,
                required: true,
                onTap: () async {
                  final d = await pickDate(context);
                  if (d == null) return;
                  setState(() {
                    ticket.saleEndTime = fmtDate(d);
                    widget.onChanged();
                  });
                },
              ),
              _hr(),
              Padding(
                padding: EdgeInsets.only(top: CyTokens.space2),
                child: Text(
                  '建议结票时间设置在活动开始前 1 小时。',
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    color: CyPalette.of(context).textTertiary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: CyTokens.space3),
          _box(
            children: <Widget>[
              Text(
                isCity ? '定向活动配置' : '探索有效期',
                style: TextStyle(
                  fontSize: CyTokens.typeLabel,
                  fontWeight: FontWeight.w700,
                  color: CyPalette.of(context).textPrimary,
                ),
              ),
              SizedBox(height: CyTokens.space2),
              if (isCity) ...<Widget>[
                _hr(),
                _row(
                  title: '集合时间',
                  value: ticket.startTime.isEmpty ? '选择开始时间' : ticket.startTime,
                  required: true,
                  onTap: () async {
                    final d = await pickDateTime(context);
                    if (d == null) return;
                    setState(() {
                      ticket.startTime = fmtDateTime(d);
                      widget.onChanged();
                    });
                  },
                ),
                _hr(),
                _row(
                  title: '集合结束',
                  value: ticket.endTime.isEmpty ? '选择结束时间' : ticket.endTime,
                  required: true,
                  onTap: () async {
                    final d = await pickDateTime(context);
                    if (d == null) return;
                    setState(() {
                      ticket.endTime = fmtDateTime(d);
                      widget.onChanged();
                    });
                  },
                ),
                _hr(),
                _labelField(
                  '建议组队 (人)',
                  child: CupertinoTextField(
                    key: const Key('ticket-editor-team-size'),
                    controller: _team,
                    onChanged: (v) {
                      ticket.teamSize = int.tryParse(v.trim()) ?? 0;
                      widget.onChanged();
                    },
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    textInputAction: TextInputAction.next,
                    placeholder: '不限',
                    padding: const EdgeInsets.all(CyTokens.space3),
                    decoration: _inputDecoration(),
                  ),
                ),
                _hr(),
                _row(
                  title: '集合地点',
                  value: ticket.meetingPoint.isEmpty
                      ? '请选择地点'
                      : ticket.meetingPoint,
                  required: true,
                  onTap: _pickMeetingPoint,
                ),
              ] else ...<Widget>[
                _hr(),
                _row(
                  title: '与主题日期保持一致',
                  value: '自动同步无需单独设置',
                  trailing: CupertinoSwitch(
                    value: ticket.syncWithTheme,
                    onChanged: (v) {
                      setState(() {
                        ticket.syncWithTheme = v;
                        widget.onChanged();
                      });
                    },
                  ),
                ),
                if (!ticket.syncWithTheme) ...<Widget>[
                  _hr(),
                  _row(
                    title: '开始日期',
                    value: ticket.startTime.isEmpty
                        ? '选择开始时间'
                        : ticket.startTime,
                    onTap: () async {
                      final d = await pickDateTime(context);
                      if (d == null) return;
                      setState(() {
                        ticket.startTime = fmtDateTime(d);
                        widget.onChanged();
                      });
                    },
                  ),
                  _hr(),
                  _row(
                    title: '结束日期',
                    value: ticket.endTime.isEmpty ? '选择结束时间' : ticket.endTime,
                    onTap: () async {
                      final d = await pickDateTime(context);
                      if (d == null) return;
                      setState(() {
                        ticket.endTime = fmtDateTime(d);
                        widget.onChanged();
                      });
                    },
                  ),
                ],
              ],
            ],
          ),
          SizedBox(height: CyTokens.space3),
          _box(
            children: <Widget>[
              _row(
                icon: Icons.lock_outline,
                title: '支持随时退款',
                value: '活动前 24 小时无理由退款',
                trailing: CupertinoSwitch(
                  value: ticket.refundSupported,
                  onChanged: (v) {
                    setState(() {
                      ticket.refundSupported = v;
                      widget.onChanged();
                    });
                  },
                ),
              ),
              _hr(),
              SizedBox(height: CyTokens.space2),
              _labelField(
                '特别提示',
                child: CupertinoTextField(
                  key: const Key('ticket-editor-description'),
                  controller: _desc,
                  onChanged: (v) {
                    ticket.description = v;
                    widget.onChanged();
                  },
                  maxLines: 3,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  autocorrect: true,
                  enableSuggestions: true,
                  placeholder: '例如：建议穿着运动鞋，自备饮用水…',
                  padding: const EdgeInsets.all(CyTokens.space3),
                  decoration: _inputDecoration(),
                ),
              ),
            ],
          ),
          SizedBox(height: CyTokens.space4),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              minimumSize: const Size.fromHeight(44),
              color: CyPalette.of(context).actionPrimaryBg,
              disabledColor: CyPalette.of(context).actionSecondaryBg,
              onPressed: canSaveTicket(ticket) ? widget.onSave : null,
              child: Text(
                '保存票种',
                style: TextStyle(
                  color: canSaveTicket(ticket)
                      ? CyPalette.of(context).actionPrimaryFg
                      : CyPalette.of(context).textDisabled,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box({required List<Widget> children}) => Container(
    padding: EdgeInsets.all(CyTokens.space3),
    decoration: BoxDecoration(
      border: Border.all(color: CyPalette.of(context).borderSubtle),
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Widget _hr() => Divider(height: 1, color: CyPalette.of(context).borderSubtle);

  Widget _row({
    required String title,
    required String value,
    IconData? icon,
    Widget? trailing,
    VoidCallback? onTap,
    bool required = false,
  }) {
    final Widget row = Padding(
      padding: EdgeInsets.symmetric(vertical: CyTokens.space2),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 20, color: CyPalette.of(context).textPrimary),
            SizedBox(width: CyTokens.space3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      if (required)
                        TextSpan(
                          text: '* ',
                          style: TextStyle(
                            color: CyPalette.of(context).statusDanger,
                          ),
                        ),
                      TextSpan(
                        text: title,
                        style: TextStyle(
                          fontSize: CyTokens.typeBody,
                          color: CyPalette.of(context).textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
          if (onTap != null)
            Text('选择 ›', style: TextStyle(color: CyPalette.of(context).textTertiary)),
        ],
      ),
    );
    if (onTap == null) return row;
    return CupertinoButton(
      minimumSize: const Size.fromHeight(44),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: row,
    );
  }

  Widget _labelField(
    String label, {
    required Widget child,
    bool required = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              if (required)
                TextSpan(
                  text: '* ',
                  style: TextStyle(color: CyPalette.of(context).statusDanger),
                ),
              TextSpan(
                text: label,
                style: TextStyle(
                  fontSize: CyTokens.typeLabel,
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: CyTokens.space1_5),
        child,
      ],
    );
  }
}

/// 自玩票(仅城市定向露出)。
class _SelfPlayCard extends StatefulWidget {
  const _SelfPlayCard({required this.draft, required this.onChanged});

  final PublishDraft draft;
  final VoidCallback onChanged;

  @override
  State<_SelfPlayCard> createState() => _SelfPlayCardState();
}

class _SelfPlayCardState extends State<_SelfPlayCard> {
  late final TextEditingController _price = TextEditingController(
    text: widget.draft.selfPlayPrice,
  );
  late final TextEditingController _quota = TextEditingController(
    text: widget.draft.selfPlayQuota,
  );

  @override
  void dispose() {
    _price.dispose();
    _quota.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final CyPalette palette = CyPalette.of(context);
    final BoxDecoration inputDecoration = BoxDecoration(
      color: palette.inputBgEmpty,
      border: Border.all(color: palette.borderSubtle),
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
    );
    return Container(
      padding: EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        border: Border.all(color: CyPalette.of(context).borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.directions_walk_outlined,
                size: 20,
                color: CyPalette.of(context).textPrimary,
              ),
              SizedBox(width: CyTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '开放自玩票',
                      style: TextStyle(
                        fontSize: CyTokens.typeBody,
                        color: CyPalette.of(context).textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '玩家可单独买通行证',
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        color: CyPalette.of(context).textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoSwitch(
                value: draft.selfPlay,
                onChanged: (v) {
                  setState(() {
                    draft.selfPlay = v;
                    widget.onChanged();
                  });
                },
              ),
            ],
          ),
          if (draft.selfPlay) ...<Widget>[
            Divider(height: CyTokens.space4, color: CyPalette.of(context).borderSubtle),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '自玩票价格 (¥)',
                        style: TextStyle(
                          fontSize: CyTokens.typeLabel,
                          color: CyPalette.of(context).textSecondary,
                        ),
                      ),
                      SizedBox(height: CyTokens.space1_5),
                      CupertinoTextField(
                        key: const Key('ticket-self-play-price'),
                        controller: _price,
                        onChanged: (v) {
                          draft.selfPlayPrice = v;
                          widget.onChanged();
                        },
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        placeholder: '如 19.9',
                        padding: const EdgeInsets.all(CyTokens.space3),
                        decoration: inputDecoration,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: CyTokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '自玩票数 (张)',
                        style: TextStyle(
                          fontSize: CyTokens.typeLabel,
                          color: CyPalette.of(context).textSecondary,
                        ),
                      ),
                      SizedBox(height: CyTokens.space1_5),
                      CupertinoTextField(
                        key: const Key('ticket-self-play-quota'),
                        controller: _quota,
                        onChanged: (v) {
                          draft.selfPlayQuota = v;
                          widget.onChanged();
                        },
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        textInputAction: TextInputAction.done,
                        placeholder: '不限',
                        padding: const EdgeInsets.all(CyTokens.space3),
                        decoration: inputDecoration,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
