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
# RecognitionLanguage.swift 刻意只 import Foundation，就是为了能这样独立编译。
printf '  编译 langcheck\n'
ln -sf ../langcheck.swift bin/main.swift
swiftc -O -o bin/langcheck bin/main.swift \
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/RecognitionLanguage.swift

# ordercheck 测的同样是生产代码：`TextRecognitionService.blocks(from:)` 这个比较器。
# 它没法和上面几个一样编成 macOS 可执行 —— 比较器的输入类型是
# `VNRecognizedTextObservation`，所以只能编成 iOS 模拟器目标，运行时走
# `xcrun simctl spawn booted`（见 README「ordercheck」一节）。
printf '  编译 ordercheck\n'
ln -sf ../ordercheck.swift bin/main.swift
xcrun --sdk iphonesimulator swiftc -O -o bin/ordercheck bin/main.swift \
    -target arm64-apple-ios16.0-simulator \
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/TextRecognitionService.swift \
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/OCRImageSource.swift \
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/RecognitionLanguage.swift

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
