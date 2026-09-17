#!/bin/sh
# 编译工具到 bin/。每个文件一个可执行，因为都各自带顶层代码。
set -e
cd "$(dirname "$0")"
mkdir -p bin

# 下面两个多文件编译要给驱动一个叫 main.swift 的符号链接 —— swiftc 只在名为
# main.swift 的文件里允许顶层代码，多文件编译时驱动会被整个拒掉
# （"expressions are not allowed at the top level"）。链接指向真文件，不是副本。
#
# 清理必须挂在 trap 上：`set -e` 下任何一步失败（swiftc 报错、Ctrl-C）都会在
# 顺序清理之前直接退出，把链接留在 bin/ 里 —— 下一轮编译就会拿着上一轮的驱动去编，
# 拿到的产物名不对、来源也不对，而且不会报错。trap 在 EXIT 上跑，正常退出、
# 报错退出、中断退出都会清。它是幂等的，重复执行无副作用。
trap 'rm -f bin/main.swift' EXIT

for tool in gen-image ocr compare cold; do
    printf '  编译 %s\n' "$tool"
    swiftc -O -o "bin/$tool" "$tool.swift"
done

# langcheck 测的是 App 的生产代码，不复制、不镜像 —— 直接编原文件。
# RecognitionLanguage.swift 刻意只 import Foundation、RecognitionLanguageAudit.swift 只多一个
# NaturalLanguage，就是为了能这样独立编译（两者都不碰 Vision / L10n / UI 类型）。
printf '  编译 langcheck\n'
ln -sf ../langcheck.swift bin/main.swift
swiftc -O -o bin/langcheck bin/main.swift \
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/RecognitionLanguage.swift \
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/RecognitionLanguageAudit.swift

# **编完就跑。** 它们是断言，不是演示：只编不跑的话，一套全红的断言和一套全绿的
# 产物在构建输出里长得一模一样，`set -e` 也不会因为断言失败而退出——
# 「编译通过」于是被当成了「验过」。这两个都是 macOS 可执行（不碰 Vision / UIKit），
# 没有理由留给人工去跑。失败就让它带着自己的诊断退出，别包一层把输出吞掉。
printf '  运行 langcheck\n'
./bin/langcheck

# layoutcheck 同样测生产代码：`TextLayout` 的版式重建。它只 import Foundation
# （不碰 Vision / L10n / UI），就是为了能这样单独编出来 —— 断言喂的是手造的
# `TextLine` 几何，不是图片，所以换台机器结果不变。
printf '  编译 layoutcheck\n'
ln -sf ../layoutcheck.swift bin/main.swift
swiftc -O -o bin/layoutcheck bin/main.swift \
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/TextLayout.swift

# 同上：编完就跑。这是回归那三层里的第一层，README 那张表写的是「前两层是自动的」——
# 在补上这一行之前，那句话是假的：layoutcheck 只被编译，从没被运行过。
printf '  运行 layoutcheck\n'
./bin/layoutcheck

# ordercheck 测的同样是生产代码：`TextRecognitionService.blocks(from:)` 这个比较器。
# 它没法和上面几个一样编成 macOS 可执行 —— 比较器的输入类型是
# `VNRecognizedTextObservation`，所以只能编成 iOS 模拟器目标，运行时走
# `xcrun simctl spawn booted`（见 README「ordercheck」一节）。
#
# `TextLayout.swift` 也是必需的：`RecognizedBlock` 现在带一个 `TextLine`，
# 而 `TextLine` 定义在那里。少了它编不过。
printf '  编译 ordercheck\n'
ln -sf ../ordercheck.swift bin/main.swift
xcrun --sdk iphonesimulator swiftc -O -o bin/ordercheck bin/main.swift \
    -target arm64-apple-ios16.0-simulator \
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/TextRecognitionService.swift \
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/OCRImageSource.swift \
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/RecognitionLanguage.swift \
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/TextLayout.swift

# paracheck 是端到端那一环：真图片 → Vision → `blocks(from:)` → `TextLayout.paragraphs`。
# 编译清单与 ordercheck 相同（都用生产代码），差别只在它**读图**、而且要把
# `TextRecognitionService` 整个编进来——后者依赖 UIKit 的 `OCRImageSource`，
# 所以同样是模拟器产物，必须经 `simctl spawn` 跑。
printf '  编译 paracheck\n'
ln -sf ../paracheck.swift bin/main.swift
xcrun --sdk iphonesimulator swiftc -O -o bin/paracheck bin/main.swift \
    -target arm64-apple-ios16.0-simulator \
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/TextRecognitionService.swift \
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/OCRImageSource.swift \
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/RecognitionLanguage.swift \
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/TextLayout.swift

printf '\n完成。产物在 bin/\n'

# 能跑就跑一遍。没有 iOS 模拟器时明确跳过——不静默吞掉，也不让构建因此失败
# （ordercheck 跑不了是环境问题，不是这次编译有问题）。
#
# **只挑 iOS 运行时的设备，并拿 UDID 去 spawn。** `simctl list devices booted` 会把
# **所有**平台已启动的模拟器都列出来——watchOS / tvOS / visionOS 的设备一样标 Booted
# ——而 `simctl spawn booted` 只从中挑一台。挑中的若不是 iOS，spawn 这个
# arm64-apple-ios16.0-simulator 产物必然失败，`set -e` 于是让 build.sh 以非零码退出：
# 一次环境问题被报成「编译失败」。检查不能撒谎，所以这里按运行时分组显式选 iOS 设备。
#
# UDID 用**模式**匹配，不按括号切字段：设备名自己就带括号（`iPad Pro 13-inch (M5)`），
# 按字段取会取到 "M5" 这种名字片段，spawn 一样失败——那只是把一种撒谎换成另一种。
ios_booted=$(xcrun simctl list devices booted 2>/dev/null | awk '
    /^-- /              { ios = ($0 ~ /^-- iOS /); next }
    ios && /\(Booted\)/ {
        if (match($0, /[0-9A-F][0-9A-F-]{35}/)) { print substr($0, RSTART, RLENGTH); exit }
    }
')
if [ -n "$ios_booted" ]; then
    printf '\n运行 ordercheck（模拟器 %s）\n' "$ios_booted"
    xcrun simctl spawn "$ios_booted" "$(pwd)/bin/ordercheck"

    # 端到端那一环：造一张合成说明书图，喂给 paracheck 走完整条链子
    # （真 Vision 包围盒 → 坐标翻转 → 版式重建 → 段落）。已存在就不重造。
    #
    # ⚠️ 中文模型首次使用要 28–34s（见 TextRecognitionService.prewarm 的注释），
    # 这一步会等它；之后同一台模拟器上就快了。
    #
    # **输出 0 个块不代表代码坏了**：那多半是这台模拟器上没有可用的识别模型
    # （首次使用要么下载要么本地编译，没网时拿不到）。这种情况下这一环什么都没验到，
    # 不能当成通过——所以下面把那句话明写出来，不让人从「跑完了」误读成「验过了」。
    # **每次都重造，不缓存。** 图是夹具，`gen-image.swift` 里那两行文本一改，
    # 旧的图就和源码对不上了——而断言只读图，不读源码，于是改完源码跑出来的
    # 仍然是旧版式的结论。造两张图不到一秒，不值得为这点时间留个静默失配的坑。
    ./bin/gen-image bin single >/dev/null
    ./bin/gen-image bin wrapped >/dev/null

    # **两张图一起跑，缺一张这一环就不成立。** 段落重建只有两种错法：
    # 该断的没断（说明书图：5 个小节应各成一段，共 10 段）、
    # 不该断的断了（折行图：一段话折五行，应**只有 1 段**）。
    # 只跑一张，把阈值往另一边调都「通过」——单看一张图是看不出方向的。
    printf '\n运行 paracheck（端到端，模拟器 %s）\n' "$ios_booted"
    para_failed=0
    xcrun simctl spawn "$ios_booted" "$(pwd)/bin/paracheck" --expect 10 \
        "$(pwd)/bin/test_image.png" || para_failed=1
    printf '\n'
    xcrun simctl spawn "$ios_booted" "$(pwd)/bin/paracheck" --expect 1 \
        "$(pwd)/bin/test_image_wrapped.png" || para_failed=1

    # **必须真的退非零。** 这里原来只有一句 `printf '❌'`，没有 `exit`——于是 paracheck
    # 明明打印了「段数 6，期望 10」，build.sh 仍然一路走到最后退出 0。一条**能发现问题、
    # 却拦不住任何东西**的断言，比没有这条断言更坏：它会让「构建过了」被读成「验过了」，
    # 而那正是这个文件里其它注释反复在防的那种谎。
    #
    # `||` 让上面两条命令免于 `set -e`（要收集两条的结果再一起判），所以这里得显式 exit。
    if [ "$para_failed" -ne 0 ]; then
        printf '\n❌ paracheck 有断言未通过。\n'
        exit 1
    fi
    printf '\n   若上面是「识别到 0 个视觉块」，这一环什么都没验到 —— 先确认这台模拟器\n'
    printf '   有识别模型（首次使用要下载或本地编译，28–34s）。别把它读成通过。\n'
else
    printf '\n⚠️  跳过 ordercheck：没有已启动的 iOS 模拟器。\n'
    if xcrun simctl list devices booted 2>/dev/null | grep -q Booted; then
        printf '   有已启动的模拟器，但没有一台是 iOS 运行时；ordercheck 是\n'
        printf '   arm64-apple-ios16.0-simulator 的产物，在那些设备上跑不起来。\n'
    fi
    printf '   跑一次：xcrun simctl boot "iPhone 17" && ./build.sh\n'
    printf '   （ordercheck 是模拟器产物，不能在 shell 里直接跑——会报\n'
    printf '     "DYLD_ROOT_PATH not set for simulator program"，必须经 simctl spawn。）\n'
fi
