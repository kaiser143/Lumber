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
printf '已生成应用包：%s\n' "$APP_PATH"
