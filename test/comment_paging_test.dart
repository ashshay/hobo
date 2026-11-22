// 评论翻页去重：热门页之间本来就重叠，按时间翻的列表还会被新评论往下挤。
//
// 详情页与楼中楼都用 models.dart 的 appendUnique 兜底，这里钉住它的行为。
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/models.dart';

void main() {
  test('没有重复时原样追加', () {
    final list = <String>['a'];
    final added = appendUnique(list, ['b', 'c'], (s) => s);
    expect(added, 2);
    expect(list, ['a', 'b', 'c']);
  });

  test('已经在列表里的不再追加', () {
    final list = <String>['a', 'b'];
    final added = appendUnique(list, ['b', 'c'], (s) => s);
    expect(added, 1, reason: '只有 c 是新的');
    expect(list, ['a', 'b', 'c'], reason: 'b 不能被放第二遍');
  });

  test('同一页里自己重复也只留一条', () {
    final list = <String>[];
    final added = appendUnique(list, ['x', 'x', 'y'], (s) => s);
    expect(added, 2);
    expect(list, ['x', 'y']);
  });

  test('整页都是旧的返回 0（详情页据此判定「这一页没新东西」）', () {
    final list = <String>['a', 'b'];
    final added = appendUnique(list, ['a', 'b'], (s) => s);
    expect(added, 0);
    expect(list, ['a', 'b']);
  });

  test('空页不动列表', () {
    final list = <String>['a'];
    expect(appendUnique(list, const <String>[], (s) => s), 0);
    expect(list, ['a']);
  });
}
