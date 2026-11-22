# Hobo

Hobo 是 Cobo 的 **Flutter / Dart 重写版**：同一个微博客户端，界面换成 FlClash 的
[`prism_ui`](https://github.com/chen08209/prism_ui) 设计语言（底栏 lens/jelly、卡片、
弹层、跟手返回转场），数据接口与容错规则逐项照搬 Kotlin 版。

- 应用名：**Hobo**
- 包名：`com.hobo.app`
- 版本：`1.07.0+9`（界面显示 `1.07`）
- 依赖：Flutter 3.47.6（Dart 3.13），`prism_ui` 以本地 path 依赖引入
- 仓库：<https://github.com/ashshay/hobo> · 站点：<https://ashshay.github.io/hobo/>

## 安装包

| 包 | 路径 | 说明 |
| --- | --- | --- |
| release | `build/app/outputs/flutter-apk/app-release.apk` | 约 20 MB，`1.07.0 (9)`，**arm64 手机专用**（AOT，含最新改动） |
| debug | `build/app/outputs/flutter-apk/app-debug.apk` | 约 232 MB，`1.07.0 (9)`，含三种 ABI，模拟器/调试用 |

公开下载走 GitHub Releases：<https://github.com/ashshay/hobo/releases/latest>
（资产名 `hobo-1.07.0-arm64.apk`）。

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
# 或者直接把 apk 拷到手机上点击安装
```

注意：

- release 包当前**用 debug 签名**（模板默认），要正式分发需换成自己的 keystore。
- 只打了 `arm64-v8a`：现代手机都是 arm64；要给 armeabi-v7a / x86_64 出包需要把对应
  `*_release.jar` 放进 `tool/engine-mirror` 再构建（见"构建注意"）。

## 快速开始

```powershell
# 环境：D:\tools\flutter（flutter config --android-sdk D:\Android\sdk）
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug
flutter install -d <device-id>
```

`android/local.properties` 里的 `sdk.dir` / `flutter.sdk` 按本机路径填写。

### 先处理 path 依赖

`pubspec.yaml` 里 `prism_ui` 与 `dynamic_color` 是**本地 path 依赖**，指向同机的
FlClash 检出目录（作者本机是 `D:/coding/repos/FlClash/plugins/...`）。刚 clone 下来时
这两个路径不存在，`flutter pub get` 会报 `Could not find a file named "pubspec.yaml"`。

两种办法任选：

```powershell
# 1) 把 FlClash 拉到同一个相对位置
git clone https://github.com/chen08209/FlClash.git D:\coding\repos\FlClash
```

```yaml
# 2) 或者用 pubspec_overrides.yaml 覆盖成本机路径（推荐，不改主 pubspec）
# pubspec_overrides.yaml
dependency_overrides:
  prism_ui:
    path: /path/to/FlClash/plugins/prism_ui
  dynamic_color:
    path: /path/to/FlClash/plugins/dynamic_color
```

`prism_ui` 是 GPL-3.0、`dynamic_color` 是 Apache-2.0，所以 Hobo 整体按 GPL-3.0 发布，
详见 [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)。

## 目录

```
lib/
├── main.dart                 启动：SharedPreferences → Settings → Store → Repo → Api.cache
├── app.dart                  PrismApp + provider 注入 + 主题（强调色 / 字号 / 深浅色）
├── app_dirs.dart             应用私有目录
├── data/                     数据层（对应 Kotlin 版 data/）
│   ├── api.dart              dio + UA/Referer/XSRF + Set-Cookie 回收 + GET 缓存
│   ├── cookie_vault.dart     域名 → cookie 表；原生 CookieManager 通道（hobo/cookies）
│   ├── models.dart           Status / Comment / User / Chat / Vote / 热搜解析（容错）
│   ├── repo.dart             时间线、详情、评论双排序、互动、发布、私信、通知、用户、搜索、超话
│   ├── store.dart            会话 / 账号 / 草稿 / 历史 / 收藏 / 关注标记 / 已读位置
│   ├── settings.dart         SharedPreferences 设置项 + ChangeNotifier
│   ├── media_saver.dart      图片 / 视频下载并写进系统相册（原生 hobo/media 通道）
│   ├── links.dart            正文链接：sinaweibo://、sinaurl、t.cn、视频、图片
│   ├── html_text.dart        HTML → 文本/链接/表情片段；stripHtml
│   ├── super_topic.dart      超话身份校验、栏目、分页
│   ├── emotions.dart         表情分组（接口 + 内置兜底）
│   ├── composer_models.dart  可见范围、话题联想、@/# 触发词
│   ├── system_browser.dart   把网址交给系统浏览器（原生 hobo/browser 通道）
│   └── update.dart           版本号 + GitHub 入口（站点 / Releases / API 地址的唯一真源）
└── ui/
    ├── shell.dart            底栏（微博/发现/消息/我）
    ├── routes.dart           所有页面入口 + 正文链接路由 + 卡片「更多」
    ├── theme.dart            prism seededColorScheme、强调色预设、Jeb_ 色相循环
    ├── nav.dart              CardPageRoute / sheet / dialog 封装
    ├── widgets/              卡片、评论、富文本、图片、列表、通用页骨架
    │   ├── refresh.dart      prism 风格下拉刷新（顶部小药丸指示器）
    │   └── scroll_anchor.dart 列表续看位置：记住 / 找回上次停下的那条微博
    └── pages/                19 个页面
android/app/src/main/kotlin/com/hobo/app/MainActivity.kt
                             系统 CookieManager 的读写通道（登录 WebView 与 App 共用）
                             + hobo/media 相册保存通道 + hobo/icon 图标形状通道
                             + hobo/browser 系统浏览器通道
assets/icon/
├── hobo_icon.png            应用图标方图（关于页、设置页按设置裁形状）
└── hobo_icon_512.png        商店用的 512 图
docs/                        GitHub Pages 站点根目录（见下）
├── index.html               落地页：功能 / 截图 / 安装 / 更新日志
├── assets/site.css          站点样式
├── assets/*.webp            站点截图（tool/make_site_images.py 生成）
└── .nojekyll                跳过 Jekyll，原样发布
tool/
├── smoke.dart                纯 Dart 冒烟：推荐流 / 详情 / 评论 / 热搜
├── make_icons.py             从方图生成两套启动图标（圆角矩形 / 圆形）
└── make_site_images.py       截图 → 站点用 WebP + 站点图标
```

## 已实现功能

| 模块 | 内容 |
| --- | --- |
| 信息流 | 关注、推荐（102803）、好友圈、特别关注、悄悄关注、本地关注、收藏、附近、自建关注分组；翻页游标与去重；下拉刷新；双击底栏「微博」刷新并回到最新一条；冷启动落回上次浏览到的那条微博；**卡片上直接点赞 / 转发 / 进评论**；下滑隐藏顶栏与底栏；顶栏左侧发布、右侧历史 / 收藏 / 搜索 / 设置（扳手）；**左右滑动切换栏目（带淡入位移动画）**；点进卡片会写入浏览历史 |
| 详情 | 正文、转发块（整块可点，进原微博）、九宫格、视频、投票入口、编辑记录；下拉刷新正文与评论；**评论配图**（九宫格，可点开、可长按保存）；评论按官方排版（头像/昵称/时间来源/正文/楼中楼/右上角点赞）、按热度与按时间切换（**翻页按 id 去重，不会重复贴同一页**）、楼中楼整页展开 |
| 主页 | **封面 + 头像随滚动折叠进顶栏**（见下）、资料卡、认证/会员标、关注/取关、关注/粉丝列表、特别/悄悄/本地标记 |
| 搜索 | 联想词（XSRF）、搜索历史、五类热搜榜、综合/用户/话题三分类、话题多频道 |
| 消息 | **顶栏四格胶囊：@我 / 评论 / 赞 / 私信，左右滑动也能翻**；@我 再分「微博 / 评论」两格小胶囊，微博那栏直接复用信息流卡片；评论与赞是通知卡片（谁 + 做了什么 + 被评论/被赞微博摘要），点进详情；私信会话列表（未读点）、聊天（文字/图片、长轮询、失败重试）、群聊 gid；四个栏目都支持下拉刷新与续页 |
| 发布 | 首页顶栏「发布」进入；最多 9 图、可见范围、草稿、上传进度提示 |
| 看图 / 视频 | 点缩略图 Hero 放大动画、双指缩放、双击放大/复原、翻页、复制链接、保存图片到相册；**长按缩略图或图片出「查看原图 / 保存图片 / 复制链接」**；video_player + Referer/Cookie 头，多档清晰度切换（超清/高清/标清）、**播放倍速 0.5x–2.0x（记住上次选的档）**、保存视频到相册，失败退回内置浏览器 |
| 设置 | 深色模式/字号/强调色（可跟随壁纸）/**应用图标（圆角矩形 / 圆形）**/卡片跟随壁纸取色/模糊、**微博页栏目多选（保存后才出现在首页）**、本地关注账号、附近城市、热搜榜、看图画质、点赞确认、底栏「我」头像、长按「我」快捷切号、**检查更新（直接打开 GitHub 页面）**、**捐赠（赞赏码）**、缓存清理、退出 |
| 登录 | 全屏 WebView 登录（系统 CookieManager 读取）+ 粘贴 Cookie；纯本地访客模式 |
| 主题 | prism 的 seed 配色；Android 12+ 用 Monet 从壁纸取强调色（直接取系统那一档，不再二次推导），卡片/页面色调也可选择跟随壁纸 |
| 底栏 | 四格：微博 / 发现 / 消息 / 我（居中，全宽药丸）；首页顶栏左侧是发微博（实心加号），右侧是历史 / 收藏 / 搜索 / 设置（扳手）；下滑信息流时顶栏与底栏一起收起；双击「微博」刷新并回到最新；底栏「我」可显示头像，长按弹出切号；**液态玻璃固定为标准档；按下/滑动仍有透明玻璃镜片和镜片内折射，但不再把图标着色成纯色片** |
| 其它 | 超话（资料头/栏目/分页）、附近城市、投票（投/取消/比例）、网页、收藏/历史/草稿/账号/关于；卡片时间在「1小时前」这类相对时间后面补一条准确发布时间；转发链里的「查看图片」直接进看图页 |

## 网页与更新链路

设置 →「检查更新」和关于页的「检查更新」都直接打开 GitHub Pages 站点
（`Updater.homepage`，定义在 `lib/data/update.dart`）——版本说明、更新日志和安装包
只在站点与 Releases 里维护一份，应用里不再复述。

内置网页（`lib/ui/pages/web_page.dart`）顶栏有「用浏览器打开」：把当前地址交给
系统浏览器，用来应付第三方登录、支付、要求装 App 的下载页这类只能在浏览器里跑完的流程。
走原生 `hobo/browser` 通道（`MainActivity.openInBrowser` → `Intent.ACTION_VIEW`），
没有引入 url_launcher；`AndroidManifest.xml` 的 `<queries>` 里补了 http/https 的 VIEW 声明，
Android 11 起的包可见性限制下也能正常交给浏览器。设备上没有可用的浏览器时返回 false，
界面提示「没有找到可用的浏览器」，不会崩。

站点源码就在本仓库的 `docs/`（GitHub Pages 从 `main` 分支的 `/docs` 发布，
`.nojekyll` 关掉 Jekyll）。改完截图后跑一次：

```powershell
python tool/make_site_images.py      # docs/screenshots/*.png → docs/assets/*.webp + 站点图标
```

## 应用图标

图标是 IconKitchen 导出的一套：深绿底 + 白色回环箭头 + 底部青色条带 + HOBO 字样。
方图 `assets/icon/hobo_icon.png`，`tool/make_icons.py` 从它生成 Android 各密度的两套位图：

| 形状 | 资源 | 桌面入口 |
| --- | --- | --- |
| 圆角矩形（默认） | `mipmap-*/ic_launcher.png` | `com.hobo.app.IconRounded` |
| 圆形 | `mipmap-*/ic_launcher_round.png` | `com.hobo.app.IconCircle` |

设置 →「外观 → 应用图标」切换，落到 `MainActivity` 的 `hobo/icon` 通道：启用一个
`activity-alias`、停用另一个（`.MainActivity` 自己不再挂 MAIN/LAUNCHER，桌面上始终只有一枚图标）。
不用 `adaptive-icon` 是故意的：Android 8+ 的自适应图标由启动器套遮罩，应用改不了形状，
想让形状由 App 说了算就只能把形状画进位图。代价是桌面若坚持给旧式位图再套一层遮罩
（Pixel Launcher 会，Launcher3 与多数国产桌面不会），图上还会多一层系统形状。

应用内（关于页、设置页那一行）不走 alias：同一张方图按设置的形状裁切，和桌面选的是同一个。

## 个人页折叠头

个人页的封面和头像跟着滚动一起收：封面在状态栏底下铺满整屏宽，头像压住封面底边；
下拉时封面从底边裁短，头像贴着它一路缩小、挪进顶栏，名字跟着从大标题变成顶栏标题；
折叠到底后顶栏是「返回 / 头像 / 名字 / 更多」一行，底色（和一条 0.5dp 分隔线）渐显，
微博从它下面滚过去。

实现在 `lib/ui/widgets/profile_header.dart`：

- `ProfileHeaderDelegate` 是 `SliverPersistentHeader` 的 delegate，`maxExtent` 是展开态高度、
  `minExtent` 是顶栏高度，中间态由 `shrinkOffset` 逐帧现算，不挂 `AnimationController`；
- 几何抽成纯函数 `ProfileHeaderLayout.at()`，`test/profile_header_layout_test.dart` 把
  `progress` 从 0 扫到 1，断言头像和名字任何一帧都不越出裁剪框（越界在真机上就是「名字被切掉」）；
- 封面图片固定按整张大小排版、只改裁剪窗口，滚动时不会重新解码或重新取样；
- 这一页不用 prism 的浮动顶栏：给 `PrismScaffold` 一个零高度的 bar，body 才能从屏幕最顶上开始画封面。

## 与 Kotlin 版的有意差异

- **登录**：只保留网页登录与手动粘贴 Cookie。Kotlin 版的 `api.weibo.cn` 客户端容器登录
  （gsid / account-getoauth 静默续期）没有移植，会话续命靠响应里的 `Set-Cookie` 与冷启动心跳。
- **视频**：用 `video_player`（支持 `httpHeaders`）替代 media_kit，省掉 libmpv 原生依赖。
- **图片**：用 Flutter 自带 `Image.network` + 微博域名 Cookie 头，没有引入 Coil 式的磁盘缓存。
- **长按底栏「我」切号**：账号切换在「设置 → 账号」与长按底栏「我」两处都能进。
- **更新**：不做应用内下载，检查更新直接把人送到 GitHub Pages / Releases；
  `Updater.latest()`（读 REST 接口挑最新一版）留着，以后要做边下边装时再接。

## 验证

```powershell
flutter analyze --no-fatal-infos   # 0 error / 0 warning
flutter test                       # 26 个解析、时间、折叠头几何、看图链接与 Cookie 单元测试
dart run tool/smoke.dart           # 真接口冒烟（可选：HOBO_COOKIE=…）
```

### 真机 / 模拟器实测（雷电 Android 14，1080×2400 @440dpi）

已在 `emulator-5554` 上安装并逐页走通：

| 场景 | 结果 |
| --- | --- |
| 登录 | WebView 登录成功后系统 CookieManager 读到 4 个域名的 cookie，`session.json` 落地，uid 正确 |
| 信息流 | 推荐流加载、九宫格/视频封面/LIVE 角标、栏目切换、下拉与翻页 |
| 详情 | 正文 + 转发块 + 九宫格、热门/按时间评论、楼中楼预览、点赞/收藏/转发/评论入口 |
| 主页 | 封面、认证与会员标、关注数、微博流、设置入口 |
| 发现 | 搜索框、五类热搜榜、搜索历史、热门榜切换 |
| 消息 | 四格胶囊拉到 @我的微博 / 收到的评论（滚到底显「没有更多了」）/ 收到的赞 / 私信；左右滑动切栏，切回时列表状态还在 |
| 设置 | 账号卡、外观/浏览/互动/更新/数据/关于分组、深色模式切换、强调色、字号 |
| 看图 / 视频 | 双指缩放翻页；video_player 带 Referer/Cookie 播放成功 |
| 暗色主题 | 整套配色、底栏与卡片均正确切换 |
| **检查更新（1.05 起）** | 设置 → 检查更新直接进内置网页，标题是站点标题，页面完整渲染（`https://ashshay.github.io/hobo/`） |
| **用浏览器打开（1.05 起）** | 内置网页顶栏第二枚按钮把当前地址交给系统浏览器，落到 `com.android.browser/.BrowserActivity`；地址栏是当前页而不是入口页 |

数据层另外用登录态 Cookie 跑过 `tool/smoke.dart`：推荐流 17 条、详情、热门评论 20 条、热搜前 5 全部解析正常。

### 为跑通做的三处适配

1. **引擎 jar 下载**：Gradle 直连 `storage.googleapis.com` 下载 `*_debug` ABI jar 会卡在 0 字节。
   本项目把这三个 jar 预下载到 `tool/engine-mirror`，用
   `FLUTTER_STORAGE_BASE_URL=http://127.0.0.1:8787`（本地静态服务）构建即可。
2. **Impeller**：模拟器的 goldfish Vulkan 驱动会让 Impeller 偶发整机卡死（进程 0% CPU、不响应）。
   `AndroidManifest.xml` 里已关闭 Impeller（走 Skia）；真机验证后可删掉那条 meta-data。
3. **逐帧滤镜**：Android 的拉伸回弹（`StretchingOverscrollIndicator`）每帧做 `ImageFiltered`，
   在模拟器上同样会拖死渲染；`app.dart` 里用 `ScrollConfiguration` 换成夹边滚动，并给
   图片按显示宽度 `cacheWidth` 下采样，显存占用降下来后滚动稳定。

## 构建注意

- Windows 上 Kotlin 增量缓存会在多个插件项目并存时关不掉，`android/gradle.properties`
  里已设 `kotlin.incremental=false`、`org.gradle.daemon=false`。
- `android/local.properties` 里的 SDK 路径必须是本机真实路径，否则 Gradle 会去
  `C:\Users\...\WinGet\Packages\Google.PlatformTools_...` 找 NDK 并报 license 错误。
- 要出 `android-x64` 的包（模拟器debug之外）需要 `tool/engine-mirror` 里同时有
  `x86_64_release` 的 jar 与 pom，然后把 `FLUTTER_STORAGE_BASE_URL` 指向一个静态服务
  的镜像根目录（`tool/engine-mirror`）。默认只出 arm64 / debug。
- `tool/engine/` 与 `tool/engine-mirror/` 是本地构建辅助（各约 400MB），已在 `.gitignore` 里排除。
