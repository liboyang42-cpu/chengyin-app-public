import 'package:chengyin_app/data/models/im.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> row(Object? muted) => <String, dynamic>{
    'conversationId': 7,
    'type': 1,
    'muted': muted,
    'counterparty': <String, dynamic>{'id': 8, 'nickname': '阿林', 'avatar': ''},
  };

  test('muted 严格解析服务端 0/1，并保留未知态', () {
    expect(Conversation.fromJson(row(1)).muted, isTrue);
    expect(Conversation.fromJson(row('1')).muted, isTrue);
    expect(Conversation.fromJson(row(0)).muted, isFalse);
    expect(Conversation.fromJson(row('0')).muted, isFalse);
    expect(Conversation.fromJson(row(null)).muted, isNull);
    expect(Conversation.fromJson(row(2)).muted, isNull);
    expect(Conversation.fromJson(row('true')).muted, isNull);
  });
}
