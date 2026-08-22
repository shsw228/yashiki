#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default values
TARGET=""
RELEASE=false
OUTPUT_DIR="${PROJECT_ROOT}/target"

usage() {
    echo "Usage: $0 [--target <target>] [--release] [--output <dir>]"
    echo ""
    echo "Options:"
    echo "  --target <target>  Build target (e.g., aarch64-apple-darwin, x86_64-apple-darwin)"
    echo "  --release          Build in release mode"
    echo "  --output <dir>     Output directory (default: target/)"
    echo ""
    echo "Examples:"
    echo "  $0 --release"
    echo "  $0 --target aarch64-apple-darwin --release"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --target)
            TARGET="$2"
            shift 2
            ;;
        --release)
            RELEASE=true
            shift
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Determine build directory
if [[ -n "$TARGET" ]]; then
    if [[ "$RELEASE" == true ]]; then
        BUILD_DIR="${PROJECT_ROOT}/target/${TARGET}/release"
    else
        BUILD_DIR="${PROJECT_ROOT}/target/${TARGET}/debug"
    fi
else
    if [[ "$RELEASE" == true ]]; then
        BUILD_DIR="${PROJECT_ROOT}/target/release"
    else
        BUILD_DIR="${PROJECT_ROOT}/target/debug"
    fi
fi

# Build arguments
CARGO_ARGS=()
if [[ -n "$TARGET" ]]; then
    CARGO_ARGS+=(--target "$TARGET")
fi
if [[ "$RELEASE" == true ]]; then
    CARGO_ARGS+=(--release)
fi

echo "Building yashiki..."
cargo build -p yashiki -p yashiki-layout-tatami -p yashiki-layout-byobu "${CARGO_ARGS[@]}"

# Get version from Cargo.toml
VERSION=$(grep '^version' "${PROJECT_ROOT}/Cargo.toml" | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo "Version: ${VERSION}"

# Determine architecture suffix for zip name
if [[ -n "$TARGET" ]]; then
    case "$TARGET" in
        aarch64-apple-darwin)
            ARCH_SUFFIX="-arm64"
            ;;
        x86_64-apple-darwin)
            ARCH_SUFFIX="-x86_64"
            ;;
        *)
            ARCH_SUFFIX="-${TARGET}"
            ;;
    esac
else
    # Detect current architecture
    CURRENT_ARCH=$(uname -m)
    case "$CURRENT_ARCH" in
        arm64)
            ARCH_SUFFIX="-arm64"
            ;;
        x86_64)
            ARCH_SUFFIX="-x86_64"
            ;;
        *)
            ARCH_SUFFIX=""
            ;;
    esac
fi

# fork ビルドを cask 版と共存させるため、bundle 名と識別子を上書きできるようにする。
# macOS のアクセシビリティ権限は bundle ID 単位なので、識別子を分けておくと
# 両方に別々の許可を与えられる（片方を入れ替えても他方の許可が消えない）。
APP_BASENAME="${APP_BASENAME:-Yashiki}"
BUNDLE_ID="${BUNDLE_ID:-dev.typester.yashiki}"
APP_NAME="${APP_BASENAME}.app"
APP_DIR="${OUTPUT_DIR}/${APP_NAME}"

echo "Creating ${APP_NAME}..."

# Create app bundle structure
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources/layouts"

# Copy binaries
# No launcher shim — yashiki is the bundle executable itself (macOS 26 menu bar fix, https://github.com/typester/yashiki/issues/182).
cp "${BUILD_DIR}/yashiki" "${APP_DIR}/Contents/MacOS/"
cp "${BUILD_DIR}/yashiki-layout-tatami" "${APP_DIR}/Contents/Resources/layouts/"
cp "${BUILD_DIR}/yashiki-layout-byobu" "${APP_DIR}/Contents/Resources/layouts/"

# Copy assets
cp "${PROJECT_ROOT}/resources/icon/Assets.car" "${APP_DIR}/Contents/Resources/"

# Generate Info.plist
sed "s/VERSION_PLACEHOLDER/${VERSION}/g" "${PROJECT_ROOT}/Info.plist.template" > "${APP_DIR}/Contents/Info.plist"

# テンプレートは上流の識別子を持つので、上書き指定があれば当て直す。
# codesign より前に行うこと（署名は Info.plist を含めて封じる）。
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${APP_BASENAME}" "${APP_DIR}/Contents/Info.plist"

# Code signing (use CODESIGN_IDENTITY if set, otherwise ad-hoc signing)
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
echo "Signing ${APP_NAME} with identity: ${CODESIGN_IDENTITY}"

# CODESIGN_REQUIREMENTS で designated requirement を差し替えられるようにする。
# 既定 (未設定) では codesign が leaf の CN を焼き込むため、証明書を更新すると
# 別のコード識別子になり、macOS が覚えたアクセシビリティ許可が失効する。
# チーム ID で固定した要件を渡せば、同じチームの証明書に入れ替えても許可が続く。
if [[ -n "${CODESIGN_REQUIREMENTS:-}" ]]; then
    # codesign -r は引数をファイルパスと見るので、インライン式は "=" を前置する。
    codesign --force --deep -s "$CODESIGN_IDENTITY" \
        -r "=${CODESIGN_REQUIREMENTS}" "${APP_DIR}"
else
    codesign --force --deep -s "$CODESIGN_IDENTITY" "${APP_DIR}"
fi

echo "Created: ${APP_DIR}"

# Create zip for release
if [[ "$RELEASE" == true ]]; then
    # Copy shell completions
    echo "Copying shell completions..."
    mkdir -p "${OUTPUT_DIR}/completions/zsh"
    cp "${PROJECT_ROOT}/completions/zsh/_yashiki" "${OUTPUT_DIR}/completions/zsh/"

    ZIP_NAME="${APP_BASENAME}${ARCH_SUFFIX}-${VERSION}.zip"
    echo "Creating ${ZIP_NAME}..."
    (cd "${OUTPUT_DIR}" && zip -r "${ZIP_NAME}" "${APP_NAME}" completions/)
    echo "Created: ${OUTPUT_DIR}/${ZIP_NAME}"

    # Cleanup completions directory after zip creation
    rm -rf "${OUTPUT_DIR}/completions"
fi

echo "Done!"
