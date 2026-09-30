import 'package:chengyin_app/data/models/im.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('群会话保留业务键以供频道归类', () {
    final Conversation conversation = Conversation.fromJson(<String, dynamic>{
      'conversationId': 12,
      'type': 4,
      'counterparty': <String, dynamic>{
        'nickname': '夜行俱乐部',
        'bizKey': 'club_7',
      },
    });

    expect(conversation.isGroup, isTrue);
    expect(conversation.counterparty.bizKey, 'club_7');
  });
}
