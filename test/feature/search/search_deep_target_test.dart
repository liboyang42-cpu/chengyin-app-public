import 'package:chengyin_app/feature/search/search_controller.dart';
import 'package:chengyin_app/feature/search/search_result_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('搜索结果四种类型保留真实四级落点', () {
    expect(
      searchResultRoute(
        const SearchResultRow(
          type: SearchResultType.topic,
          id: 1,
          title: '',
          detail: '',
        ),
      ),
      '/topic/1',
    );
    expect(
      searchResultRoute(
        const SearchResultRow(
          type: SearchResultType.activity,
          id: 2,
          title: '',
          detail: '',
        ),
      ),
      '/activity/2',
    );
    expect(
      searchResultRoute(
        const SearchResultRow(
          type: SearchResultType.club,
          id: 3,
          title: '',
          detail: '',
        ),
      ),
      '/club/3',
    );
    expect(
      searchResultRoute(
        const SearchResultRow(
          type: SearchResultType.merchant,
          id: 4,
          memberId: 44,
          title: '',
          detail: '',
        ),
      ),
      '/user/44',
    );
    expect(
      searchResultRoute(
        const SearchResultRow(
          type: SearchResultType.merchant,
          id: 4,
          title: '',
          detail: '',
        ),
      ),
      isNull,
    );
  });
}
