import 'package:prism_ui/icons/icons.dart';

/// 应用自己的图标。prism_ui 只带通用 glyph，这里补上底栏、操作栏与设置页用得到的那些。
/// 路径取自 Material Icons（Apache-2.0），24 栅格、实心绘制，视觉上与 prism 的线条图标同一套网格。
abstract final class HoboGlyphs {
  static const home = Glyph([
    GlyphPath('M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z'),
  ]);

  static const explore = Glyph([
    GlyphPath(
      'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm2.19 12.19L6 18l3.81-8.19L18 6l-3.81 8.19z',
    ),
    GlyphCircle(12, 12, 1.1, role: GlyphRole.detail, solid: true),
  ]);

  static const messages = Glyph([
    GlyphPath(
      'M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z',
    ),
  ]);

  static const person = Glyph([
    GlyphPath(
      'M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z',
    ),
  ]);

  static const add = Glyph([
    GlyphPath('M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z'),
  ]);

  static const like = Glyph([
    GlyphPath(
      'M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z',
    ),
  ]);

  static const likeOutline = Glyph([
    GlyphPath(
      'M16.5 3c-1.74 0-3.41.81-4.5 2.09C10.91 3.81 9.24 3 7.5 3 4.42 3 2 5.42 2 8.5c0 3.78 3.4 6.86 8.55 11.54L12 21.35l1.45-1.32C18.6 15.36 22 12.28 22 8.5 22 5.42 19.58 3 16.5 3z',
      role: GlyphRole.line,
    ),
  ]);

  static const comment = Glyph([
    GlyphPath(
      'M21.99 4c0-1.1-.89-2-1.99-2H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h14l4 4-.01-18z',
    ),
  ]);

  static const repost = Glyph([
    GlyphPath(
      'M7 7h10v3l4-4-4-4v3H5v6h2V7zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4z',
    ),
  ]);

  static const bookmark = Glyph([
    GlyphPath(
      'M17 3H7c-1.1 0-1.99.9-1.99 2L5 21l7-3 7 3V5c0-1.1-.9-2-2-2z',
    ),
  ]);

  static const bookmarkOutline = Glyph([
    GlyphPath(
      'M17 3H7c-1.1 0-1.99.9-1.99 2L5 21l7-3 7 3V5c0-1.1-.9-2-2-2zm0 15l-5-2.18L7 18V5h10v13z',
      role: GlyphRole.line,
    ),
  ]);

  static const more = Glyph([
    GlyphCircle(6, 12, 1.8, solid: true),
    GlyphCircle(12, 12, 1.8, solid: true),
    GlyphCircle(18, 12, 1.8, solid: true),
  ]);

  static const play = Glyph([
    GlyphPath('M8 5v14l11-7z'),
  ]);

  static const image = Glyph([
    GlyphPath(
      'M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z',
    ),
  ]);

  static const tune = Glyph([
    GlyphPath(
      'M3 17v2h6v-2H3zM3 5v2h10V5H3zm10 16v-2h8v-2h-8v-2h-2v6h2zM7 9v2H3v2h4v2h2V9H7zm14 4v-2H11v2h10zm-6-4h2V7h4V5h-4V3h-2v6z',
    ),
  ]);

  /// 扳手：Material 的 build 轮廓，线性描边后和其它顶栏图标一致。
  static const wrench = Glyph([
    GlyphPath(
      'M22.7 19l-9.1-9.1c.9-2.3.4-5-1.5-6.9-2-2-5-2.4-7.4-1.3L9 6 6 9 1.6 4.7C.4 7.1.9 10.1 2.9 12.1c1.9 1.9 4.6 2.4 6.9 1.5l9.1 9.1c.4.4 1 .4 1.4 0l2.3-2.3c.5-.4.5-1.1.1-1.4z',
    ),
  ]);

  static const edit = Glyph([
    GlyphPath(
      'M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04a1 1 0 0 0 0-1.41l-2.34-2.34a1 1 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z',
    ),
  ]);

  static const delete = Glyph([
    GlyphPath(
      'M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z',
    ),
  ]);

  static const location = Glyph([
    GlyphPath(
      'M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5a2.5 2.5 0 0 1 0-5 2.5 2.5 0 0 1 0 5z',
    ),
  ]);

  static const clock = Glyph([
    GlyphCircle(12, 12, 9, role: GlyphRole.line),
    GlyphPath('M11.5 7H13v6l4.2 2.5-0.8 1.3-4.9-3z'),
  ]);

  static const logout = Glyph([
    GlyphPath(
      'M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h8v-2H4V5z',
    ),
  ]);

  static const refresh = Glyph([
    GlyphPath(
      'M17.65 6.35A7.958 7.958 0 0 0 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08A5.99 5.99 0 0 1 12 18c-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z',
    ),
  ]);

  static const send = Glyph([
    GlyphPath('M2.01 21L23 12 2.01 3 2 10l15 2-15 2z'),
  ]);

  static const vote = Glyph([
    GlyphPath(
      'M19 3h-1V1h-2v2H8V1H6v2H5c-1.11 0-1.99.9-1.99 2L3 19c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-1 16H6V8h12v11z',
    ),
  ]);

  static const trending = Glyph([
    GlyphPath('M16 6l2.29 2.29-4.88 4.88-4-4L2 16.59 3.41 18l6-6 4 4 6.3-6.29L22 12V6z'),
  ]);

  static const topic = Glyph([
    GlyphPath('M16 6l2.29 2.29-4.88 4.88-4-4L2 16.59 3.41 18l6-6 4 4 6.3-6.29L22 12V6h-6z'),
  ]);

  static const tag = Glyph([
    GlyphPath(
      'M17.63 5.84C17.27 5.33 16.67 5 16 5L5 5.01C3.9 5.01 3 5.9 3 7v10c0 1.1.9 1.99 2 1.99L16 19c.67 0 1.27-.33 1.63-.84L22 12l-4.37-6.16z',
    ),
  ]);

  static const people = Glyph([
    GlyphPath(
      'M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z',
    ),
  ]);

  static const star = Glyph([
    GlyphPath(
      'M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z',
    ),
  ]);

  static const info = Glyph([
    GlyphCircle(12, 12, 9, role: GlyphRole.line),
    GlyphCircle(12, 7.4, 1.1, solid: true),
    GlyphPath('M11.2 10.4h1.6v6.2h-1.6z'),
  ]);

  static const download = Glyph([
    GlyphPath('M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z'),
  ]);

  static const moon = Glyph([
    GlyphPath(
      'M12.34 2.02C6.59 1.82 2 6.42 2 12c0 5.52 4.48 10 10 10 3.71 0 6.93-2.02 8.66-5.02-7.51-.25-12.09-8.43-8.32-14.96z',
    ),
  ]);

  static const textSize = Glyph([
    GlyphPath('M9 4v3h5v12h3V7h5V4H9zm-5 6v3h3v6h3v-6h3v-3H4z'),
  ]);

  static const palette = Glyph([
    GlyphPath(
      'M12 3a9 9 0 0 0 0 18c.83 0 1.5-.67 1.5-1.5 0-.39-.15-.74-.39-1.01-.23-.26-.38-.61-.38-.99 0-.83.67-1.5 1.5-1.5H16a5 5 0 0 0 5-5c0-4.42-4.03-8-9-8zm-5.5 9a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zm3-4a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zm5 0a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zm3 4a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3z',
    ),
  ]);

  static const share = Glyph([
    GlyphPath(
      'M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11c.54.5 1.25.81 2.04.81a3 3 0 1 0-3-3c0 .24.04.47.09.7L8.04 9.81A3 3 0 1 0 6 15c.79 0 1.5-.31 2.04-.81l7.12 4.16c-.05.21-.08.43-.08.65a2.92 2.92 0 1 0 2.92-2.92z',
    ),
  ]);

  static const link = Glyph([
    GlyphPath(
      'M3.9 12c0-1.71 1.39-3.1 3.1-3.1h4V7H7c-2.76 0-5 2.24-5 5s2.24 5 5 5h4v-1.9H7c-1.71 0-3.1-1.39-3.1-3.1zM8 13h8v-2H8v2zm9-6h-4v1.9h4c1.71 0 3.1 1.39 3.1 3.1s-1.39 3.1-3.1 3.1h-4V17h4c2.76 0 5-2.24 5-5s-2.24-5-5-5z',
    ),
  ]);

  static const camera = Glyph([
    GlyphPath(
      'M12 15.2a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4zM9 2L7.17 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2h-3.17L15 2H9zm3 15a5 5 0 1 1 0-10 5 5 0 0 1 0 10z',
    ),
  ]);

  static const check = Glyph([
    GlyphPath('M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z'),
  ]);

  static const top = Glyph([
    GlyphPath('M4 12l1.41 1.41L11 7.83V20h2V7.83l5.58 5.59L20 12l-8-8-8 8z'),
  ]);

  static const list = Glyph([
    GlyphPath('M3 13h2v-2H3v2zm0 4h2v-2H3v2zm0-8h2V7H3v2zm4 4h14v-2H7v2zm0 4h14v-2H7v2zM7 7v2h14V7H7z'),
  ]);
}
