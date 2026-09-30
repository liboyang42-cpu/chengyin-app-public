import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI 策划入口透传当前俱乐部 id', () {
    final String source =
        File('lib/feature/club/club_detail_page.dart').readAsStringSync();
    expect(source, contains('showClubAiDesignSheet(context, clubId: club.id)'));
  });

  test('俱乐部详情的评论权限使用成员真源并透传给 sheet', () {
    final String section =
        File('lib/feature/club/club_posts_section.dart').readAsStringSync();
    final String tile =
        File('lib/feature/club/club_feed_page.dart').readAsStringSync();

    expect(section, contains('clubMembersProvider(clubId)'));
    expect(section, contains('viewerIsClubAdmin: viewerIsClubAdmin'));
    expect(section, contains('clubOwnerMemberId: clubOwnerMemberId'));
    expect(tile, contains('clubOwnerMemberId: clubOwnerMemberId'));
    expect(tile, contains('viewerIsClubAdmin: viewerIsClubAdmin'));
  });
}
