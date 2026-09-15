#!/bin/sh
# 编译工具到 bin/。每个文件一个可执行，因为都各自带顶层代码。
set -e
cd "$(dirname "$0")"
mkdir -p bin
for tool in gen-image ocr compare cold; do
    printf '  编译 %s\n' "$tool"
    swiftc -O -o "bin/$tool" "$tool.swift"
done

# langcheck 测的是 App 的生产代码，不复制、不镜像 —— 直接编原文件。
# RecognitionLanguage.swift 刻意只 import Foundation，就是为了能这样独立编译。
#
# 唯一的曲折：swiftc 只在名为 main.swift 的文件里允许顶层代码，多文件编译时
# langcheck.swift 会被整个拒掉（"expressions are not allowed at the top level"）。
# 所以给驱动一个叫 main.swift 的符号链接 —— 它指向真文件，不是副本。
# 别把它改成 cp —— 那就成了副本，这个测试也就失去了意义。
printf '  编译 langcheck\n'
ln -sf ../langcheck.swift bin/main.swift
swiftc -O -o bin/langcheck bin/main.swift \
    ../../ios/PresbyFriend/PresbyFriend/Core/OCR/RecognitionLanguage.swift
rm -f bin/main.swift

printf '\n完成。产物在 bin/\n'
