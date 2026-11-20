import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../data/repo.dart';

/// 微博的图片。附件域名（`attachment.api.weibo.com`）不带 cookie 直接 403，
/// 所以给微博域名挂上当前会话的 cookie 与 UA。
class RemoteImage extends StatelessWidget {
  const RemoteImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = 0,
    this.placeholderColor,
    this.filterQuality = FilterQuality.low,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;
  final Color? placeholderColor;
  final FilterQuality filterQuality;

  Map<String, String>? _headers(BuildContext context) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    if (host.isEmpty) return null;
    if (!(host == 'weibo.com' || host.endsWith('.weibo.com'))) return null;
    final cookie = context.read<Repo>().cookie();
    if (cookie == null || cookie.isEmpty) return null;
    return {'Cookie': cookie, 'User-Agent': 'Mozilla/5.0'};
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = placeholderColor ??
        context.surfaceLevel.next.colorOf(context.colorScheme);
    // 按实际显示尺寸解码：微博原图动辄几千像素，列表里全尺寸解码会把
    // 模拟器/低端机的显存吃光。只在调用方给了明确宽度时下采样。
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = width == null || !width!.isFinite
        ? null
        : (width! * dpr).round().clamp(64, 1440);
    Widget image;
    if (url.isEmpty) {
      image = ColoredBox(color: placeholder);
    } else {
      image = Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        headers: _headers(context),
        filterQuality: filterQuality,
        gaplessPlayback: true,
        cacheWidth: cacheWidth,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          // 加载中只铺底色：不能在这里套 Stack(expand)，调用方可能给的是无界约束。
          return ColoredBox(color: placeholder);
        },
        errorBuilder: (context, error, stack) => ColoredBox(
          color: placeholder,
          child: Center(
            child: GlyphIcon(
              Glyphs.eyeOff,
              size: 20,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    if (radius <= 0) return image;
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(radius),
      child: image,
    );
  }
}

/// 圆形头像，带一个同色占位。
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.url, this.size = 40, this.onTap});

  final String url;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final image = RemoteImage(
      url: url,
      width: size,
      height: size,
      radius: size / 2,
      placeholderColor: context.colorScheme.surfaceContainerHighest,
    );
    if (onTap == null) return image;
    return GestureDetector(onTap: onTap, child: image);
  }
}

/// 带边框的「V」认证标，和微博网页端一样挂在昵称后面。
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: context.colorScheme.primary,
        shape: AppShape.full,
      ),
      child: Text(
        'V',
        style: TextStyle(
          fontSize: size * 0.62,
          height: 1,
          fontWeight: FontWeight.w700,
          color: context.colorScheme.onPrimary,
        ),
      ),
    );
  }
}

/// 会员角标：VIP / SVIP。
class MemberBadge extends StatelessWidget {
  const MemberBadge({super.key, required this.svip});

  final bool svip;

  @override
  Widget build(BuildContext context) {
    final color = svip ? const Color(0xFFE8B339) : const Color(0xFFE38C2D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: ShapeDecoration(color: color, shape: AppShape.full),
      child: Text(
        svip ? 'SVIP' : 'VIP',
        style: TextStyle(
          fontSize: 9,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: Color(0xFF3B2400),
        ),
      ),
    );
  }
}
