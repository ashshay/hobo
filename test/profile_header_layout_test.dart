import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/ui/widgets/profile_header.dart';

void main() {
  const topInset = 24.0;
  const nameLine = 22 * 1.3;

  ProfileHeaderLayout at(double p) => ProfileHeaderLayout.at(
    progress: p,
    topInset: topInset,
    nameLine: nameLine,
    textScale: 1,
    showBack: true,
    surfaceTint: const Color(0xFF121212),
    onSurface: const Color(0xFFFFFFFF),
  );

  test('折叠头每一帧都留在裁剪框里', () {
    for (var i = 0; i <= 100; i++) {
      final p = i / 100;
      final m = at(p);
      final reason = 'p=$p extent=${m.extent} avatar=${m.avatarTop}..'
          '${m.avatarTop + m.avatarSize} name=${m.nameTop}..'
          '${m.nameTop + m.nameHeight}';
      expect(
        m.avatarTop + m.avatarSize,
        lessThanOrEqualTo(m.extent + 0.01),
        reason: reason,
      );
      expect(
        m.nameTop + m.nameHeight,
        lessThanOrEqualTo(m.extent + 0.01),
        reason: reason,
      );
      expect(m.nameTop, greaterThanOrEqualTo(0), reason: reason);
      expect(m.avatarTop, greaterThanOrEqualTo(0), reason: reason);
    }
  });

  test('展开态名字在头像下方，折叠后一起进顶栏', () {
    final expanded = at(0);
    expect(
      expanded.nameTop,
      greaterThan(expanded.avatarTop + expanded.avatarSize),
    );
    final collapsed = at(1);
    const barBottom = topInset + ProfileHeaderDelegate.barHeight;
    expect(collapsed.coverBottom, 0);
    expect(
      collapsed.avatarTop + collapsed.avatarSize,
      lessThanOrEqualTo(barBottom),
    );
    expect(collapsed.nameTop + collapsed.nameHeight, lessThanOrEqualTo(barBottom));
    expect(collapsed.nameLeft, greaterThan(collapsed.avatarLeft));
  });

  test('几何随进度单调收拢', () {
    var previousAvatar = double.infinity;
    var previousExtent = double.infinity;
    for (var i = 0; i <= 100; i++) {
      final m = at(i / 100);
      expect(m.avatarSize, lessThanOrEqualTo(previousAvatar + 0.01));
      expect(m.extent, lessThanOrEqualTo(previousExtent + 0.01));
      previousAvatar = m.avatarSize;
      previousExtent = m.extent;
    }
  });
}
