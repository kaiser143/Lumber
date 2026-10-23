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

# 无开发者证书，做 ad-hoc 签名：让 bundle 自带完整签名与资源封印，
# 否则下载后 Gatekeeper 会直接判定「已损坏」。签名必须在打包 dmg 之前完成。
xattr -cr "$APP_PATH" 2>/dev/null || true
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
printf '已生成应用包（ad-hoc 签名）：%s\n' "$APP_PATH"

# 版本号取自 Info.plist，用于 dmg 命名
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$CONTENTS/Info.plist" 2>/dev/null || printf '0.0.0')
DMG_PATH=${2:-"$ROOT_DIR/dist/Lumber-$VERSION.dmg"}

# 暂存目录内放 app 与指向 /Applications 的快捷方式，形成标准拖装布局
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$(dirname -- "$DMG_PATH")"
rm -f "$DMG_PATH"
hdiutil create -volname "Lumber" -fs HFS+ -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH"
printf '已生成磁盘镜像：%s\n' "$DMG_PATH"
