#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_PATH=${1:-"$ROOT_DIR/dist/Lumber.app"}
CONTENTS="$APP_PATH/Contents"

cd "$ROOT_DIR"
swift build -c release
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp ".build/release/Lumber" "$CONTENTS/MacOS/Lumber"
cp "Resources/Info.plist" "$CONTENTS/Info.plist"
cp "Resources/LumberIcon.icns" "$CONTENTS/Resources/LumberIcon.icns"
# 界面内与 Dock 运行时图标优先读矢量源，保证与 .icns 完全同源
cp "Resources/LumberIcon.svg" "$CONTENTS/Resources/LumberIcon.svg"
printf '已生成应用包：%s\n' "$APP_PATH"
