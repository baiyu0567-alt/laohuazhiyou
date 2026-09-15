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
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/OCRImageSource.swift

printf '\n完成。产物在 bin/\n'

# 能跑就跑一遍。没有 booted 模拟器时明确跳过——不静默吞掉，也不让构建因此失败
# （ordercheck 跑不了是环境问题，不是这次编译有问题）。
if xcrun simctl list devices booted 2>/dev/null | grep -q Booted; then
    printf '\n运行 ordercheck\n'
    xcrun simctl spawn booted "$(pwd)/bin/ordercheck"
else
    printf '\n⚠️  跳过 ordercheck：没有 booted 模拟器。\n'
    printf '   跑一次：xcrun simctl boot "iPhone 17" && ./build.sh（或直接 ./bin/ordercheck）\n'
fi
