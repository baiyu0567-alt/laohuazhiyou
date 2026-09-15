#!/bin/sh
# 编译四个工具到 bin/。每个文件一个可执行，因为都各自带顶层代码。
set -e
cd "$(dirname "$0")"
mkdir -p bin
for tool in gen-image ocr compare cold; do
    printf '  编译 %s\n' "$tool"
    swiftc -O -o "bin/$tool" "$tool.swift"
done
printf '\n完成。产物在 bin/\n'
