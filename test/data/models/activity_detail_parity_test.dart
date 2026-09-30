import 'package:chengyin_app/data/models/activity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('活动详情保留 Mini 页面所有可见列表与取消事实', () {
    final ActivityDetail detail = ActivityDetail.fromJson(<String, dynamic>{
      'id': 18,
      'name': '城市夜行',
      'averageRating': 4.8,
      'endDate': '2026-09-12 22:00:00',
      'latitude': 31.23,
      'longitude': 121.47,
      'cancelTime': '2026-09-01 10:00:00',
      'cancelReason': '天气原因',
      'sysCategoryList': <Map<String, dynamic>>[
        <String, dynamic>{'categoryName': '夜游'},
      ],
      'collaboratorsList': <Map<String, dynamic>>[
        <String, dynamic>{
          'memberId': 7,
          'memberRealName': '林野',
          'memberAvatar': 'host.png',
        },
      ],
      'registrationList': <Map<String, dynamic>>[
        <String, dynamic>{
          'memberId': 8,
          'nickname': '阿辰',
          'avatar': 'player.png',
        },
      ],
      'memberTemplateList': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 9,
          'title': '密码墙',
          'players': 4,
          'duration': 20,
        },
      ],
      'commentList': <Map<String, dynamic>>[
        <String, dynamic>{
          'memberNickname': '城市夜行家',
          'rating': 5,
          'contents': '路线很有趣',
        },
      ],
      'omsTicketList': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'name': '早鸟票',
          'startTime': '2026-09-12 19:00:00',
          'endTime': '2026-09-12 20:00:00',
          'description': '含一份饮品',
          'remainingInventory': 3,
          'cmsRegistrationList': <Map<String, dynamic>>[
            <String, dynamic>{'memberId': 8, 'nickname': '阿辰'},
          ],
        },
      ],
    });

    expect(detail.rating, 4.8);
    expect(detail.endDate, '2026-09-12 22:00:00');
    expect(detail.hasCoordinates, isTrue);
    expect(detail.cancelReason, '天气原因');
    expect(detail.categoryNames, <String>['夜游']);
    expect(detail.collaborators.single.name, '林野');
    expect(detail.registrants.single.nickname, '阿辰');
    expect(detail.nodes.single.title, '密码墙');
    expect(detail.comments.single.contents, '路线很有趣');
    expect(detail.tickets.single.registrants.single.nickname, '阿辰');
  });
}
