#!/usr/bin/env bash
set -euo pipefail

# Build FullscreenReminder and package it into ./dist

# --- Configuration ---
PROJECT_NAME="FullscreenReminder"
SCHEME="$PROJECT_NAME"
CONFIG="release" # swift build uses lowercase 'release' or 'debug'

# Script is in root
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$ROOT_DIR/dist"
APP_INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
ENTITLEMENTS_PATH="$ROOT_DIR/Resources/FullscreenReminder.entitlements"

# Codesigning configuration
CODESIGN_IDENTITY_DEFAULT="Developer ID Application: LARS PEHRSSON (XX2RQ3WPAH)"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-$CODESIGN_IDENTITY_DEFAULT}"
SKIP_CODESIGN="${SKIP_CODESIGN:-}"

# Packaging options
BUMP_BUILD="${BUMP_BUILD:-0}"
BUMP_MARKETING_VERSION="${BUMP_MARKETING_VERSION:-0}"
NEW_MARKETING_VERSION="${NEW_MARKETING_VERSION:-}"
CREATE_DMG="${CREATE_DMG:-0}"
UNIVERSAL="${UNIVERSAL:-0}"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARY_KEY_PATH="${NOTARY_KEY_PATH:-}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:-}"
NOTARY_ISSUER="${NOTARY_ISSUER:-}"
NO_OPEN="${NO_OPEN:-${CI:-}}"

SWIFT_BUILD_ARGS=(-c "$CONFIG")
if [ "$UNIVERSAL" = "1" ]; then
    SWIFT_BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

# --- Logging Helpers ---
info() { echo -e "\033[1;34m➡︎ $*\033[0m"; }
success() { echo -e "\033[1;32m✅ $*\033[0m"; }
warn() { echo -e "\033[1;33m⚠︎ $*\033[0m" >&2; }
error() { echo -e "\033[1;31m❌ $*\033[0m" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Builds $PROJECT_NAME using 'swift build', assembles the .app bundle, signs it, and packages it into the dist/ directory.

Options:
  -h, --help                Show this help message and exit

Environment Variables:
  BUMP_BUILD=1              Auto-increment the build number (CFBundleVersion)
  BUMP_MARKETING_VERSION=1  Auto-increment the marketing version (CFBundleShortVersionString)
  NEW_MARKETING_VERSION=X.Y.Z
                            Set a specific marketing version
  CREATE_DMG=1              Create a DMG installer in addition to the ZIP
  SKIP_CODESIGN=1           Skip the codesigning and verification steps
  CODESIGN_IDENTITY="..."   Override the default codesigning identity
  UNIVERSAL=1               Build a universal (arm64 + x86_64) binary
  NOTARIZE=1                Notarize and staple the app (and DMG). Needs either
                              NOTARY_PROFILE=<notarytool keychain profile>, or
                              NOTARY_KEY_PATH, NOTARY_KEY_ID and NOTARY_ISSUER (App Store Connect API key)
  NO_OPEN=1                 Don't open the app when done (default when CI is set)
EOF
}

# --- Dependency Checks ---
check_dependency() {
    if ! command -v "$1" >/dev/null 2>&1; then
        error "Required tool '$1' not found. Please install it."
        exit 1
    fi
}

check_dependencies() {
    check_dependency swift
    check_dependency /usr/libexec/PlistBuddy
    check_dependency ditto
    if [ "$CREATE_DMG" = "1" ]; then
        check_dependency hdiutil
    fi
}

# --- Versioning Functions ---
bump_semver() {
    # Bumps the last numeric component of a dotted version string.
    local ver="$1"
    local a b c
    IFS='.' read -r a b c <<<"$ver"
    [[ -z "$a" || ! "$a" =~ ^[0-9]+$ ]] && a=0
    [[ -z "$b" || ! "$b" =~ ^[0-9]+$ ]] && b=""
    [[ -z "$c" || ! "$c" =~ ^[0-9]+$ ]] && c=""

    if [[ -n "$c" ]]; then
        echo "$a.$b.$((c + 1))"
    elif [[ -n "$b" ]]; then
        echo "$a.$((b + 1))"
    else
        echo "$((a + 1))"
    fi
}

handle_versioning() {
    if [ "$BUMP_BUILD" = "1" ]; then
        info "Bumping build number (CFBundleVersion)"
        if [ ! -f "$APP_INFO_PLIST" ]; then
            warn "Info.plist not found at $APP_INFO_PLIST; skipping build bump"
        else
            local current next
            current=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_INFO_PLIST" 2>/dev/null || echo 0)
            [[ ! "$current" =~ ^[0-9]+$ ]] && current=0
            next=$((current + 1))
            /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next" "$APP_INFO_PLIST" 2>/dev/null || \
                /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $next" "$APP_INFO_PLIST"
            info "CFBundleVersion: $current → $next"
        fi
    fi

    if [ "$BUMP_MARKETING_VERSION" = "1" ] && [ -z "$NEW_MARKETING_VERSION" ]; then
        info "Computing new marketing version"
        local current_mv=""
        if [ -f "$APP_INFO_PLIST" ]; then
            current_mv=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_INFO_PLIST" 2>/dev/null || echo "")
        fi
        [ -z "$current_mv" ] && current_mv="1.0.0"
        NEW_MARKETING_VERSION=$(bump_semver "$current_mv")
        info "CFBundleShortVersionString: $current_mv → $NEW_MARKETING_VERSION"
    fi

    if [ -n "$NEW_MARKETING_VERSION" ]; then
        info "Setting marketing version to $NEW_MARKETING_VERSION"
        if [ ! -f "$APP_INFO_PLIST" ]; then
            warn "Info.plist not found; skipping marketing version set"
        else
            /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_MARKETING_VERSION" "$APP_INFO_PLIST" 2>/dev/null || \
                /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $NEW_MARKETING_VERSION" "$APP_INFO_PLIST"
        fi
    fi
}

# --- Build and Sign Functions ---
build_project() {
    info "Building $PROJECT_NAME ($CONFIG)"
    mkdir -p "$OUT_DIR"
    
    cd "$ROOT_DIR"
    swift build "${SWIFT_BUILD_ARGS[@]}"
    
    local bin_path=$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)
    local executable="$bin_path/$PROJECT_NAME"
    
    if [ ! -x "$executable" ]; then
        error "Executable not found at $executable"
        return 1
    fi
    
    local app_dir="$OUT_DIR/$PROJECT_NAME.app"
    info "Assembling .app bundle at $app_dir"
    rm -rf "$app_dir"
    mkdir -p "$app_dir/Contents/MacOS"
    mkdir -p "$app_dir/Contents/Resources"
    
    cp "$executable" "$app_dir/Contents/MacOS/$PROJECT_NAME"
    [ -f "$APP_INFO_PLIST" ] && cp "$APP_INFO_PLIST" "$app_dir/Contents/Info.plist"
    [ -f "$ROOT_DIR/Resources/AppIcon.icns" ] && cp "$ROOT_DIR/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
    
    for png in appicon processbar; do
        [ -f "$ROOT_DIR/Resources/$png.png" ] && cp "$ROOT_DIR/Resources/$png.png" "$app_dir/Contents/Resources/$png.png"
    done

    # Sparkle (in-app updates) is a dynamic framework, found through the @executable_path/../Frameworks rpath.
    if [ -d "$bin_path/Sparkle.framework" ]; then
        mkdir -p "$app_dir/Contents/Frameworks"
        ditto "$bin_path/Sparkle.framework" "$app_dir/Contents/Frameworks/Sparkle.framework"
    else
        error "Sparkle.framework not found in $bin_path"
        return 1
    fi
}

sign_app() {
    local app_path="$1"
    if [ -n "$SKIP_CODESIGN" ]; then
        info "SKIP_CODESIGN set; skipping codesign step"
        return 0
    fi

    info "Signing app with identity: $CODESIGN_IDENTITY"
    local base_args=("--force" "--options" "runtime" "--sign" "$CODESIGN_IDENTITY")
    # A secure timestamp needs a real identity; ad-hoc ("-") signing can't have one.
    [ "$CODESIGN_IDENTITY" != "-" ] && base_args+=("--timestamp")

    # Sign Sparkle's helpers inside-out, as its docs prescribe (--deep would drop the
    # Downloader service's entitlements).
    local sparkle="$app_path/Contents/Frameworks/Sparkle.framework"
    if [ -d "$sparkle" ]; then
        info "Signing Sparkle.framework"
        codesign "${base_args[@]}" "$sparkle/Versions/B/XPCServices/Installer.xpc" || return 1
        codesign "${base_args[@]}" --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc" || return 1
        codesign "${base_args[@]}" "$sparkle/Versions/B/Autoupdate" || return 1
        codesign "${base_args[@]}" "$sparkle/Versions/B/Updater.app" || return 1
        codesign "${base_args[@]}" "$sparkle" || return 1
    fi

    local sign_args=("${base_args[@]}")
    if [ -f "$ENTITLEMENTS_PATH" ]; then
        info "Using entitlements: $ENTITLEMENTS_PATH"
        sign_args+=("--entitlements" "$ENTITLEMENTS_PATH")
    fi
    
    if ! codesign "${sign_args[@]}" "$app_path"; then
        error "Codesign failed"
        return 1
    fi

    info "Verifying code signature"
    if ! codesign --verify --deep --strict --verbose=2 "$app_path"; then
        error "Code signature verification failed"
        return 1
    fi

    if command -v spctl >/dev/null 2>&1; then
        spctl --assess --type execute --verbose "$app_path" || true
    fi
}

# --- Notarization ---
notarize_file() {
    # Submits a .zip or .dmg to Apple's notary service and fails unless it's accepted.
    local file="$1"
    local auth_args=()
    if [ -n "$NOTARY_PROFILE" ]; then
        auth_args=(--keychain-profile "$NOTARY_PROFILE")
    elif [ -n "$NOTARY_KEY_PATH" ] && [ -n "$NOTARY_KEY_ID" ] && [ -n "$NOTARY_ISSUER" ]; then
        auth_args=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
    else
        error "NOTARIZE=1 needs NOTARY_PROFILE, or NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER"
        return 1
    fi

    info "Submitting $(basename "$file") for notarization (this can take a few minutes)"
    local out status id
    out=$(xcrun notarytool submit "$file" "${auth_args[@]}" --wait --output-format json) || true
    echo "$out"
    status=$(/usr/bin/plutil -extract status raw -o - - <<<"$out" 2>/dev/null) || status=""
    id=$(/usr/bin/plutil -extract id raw -o - - <<<"$out" 2>/dev/null) || id=""
    if [ "$status" != "Accepted" ]; then
        error "Notarization of $(basename "$file") failed (status: ${status:-unknown})"
        [ -n "$id" ] && xcrun notarytool log "$id" "${auth_args[@]}" || true
        return 1
    fi
    success "Notarization accepted: $(basename "$file")"
}

notarize_app() {
    local app_path="$1"
    if [ "$NOTARIZE" != "1" ]; then
        return 0
    fi
    if [ -n "$SKIP_CODESIGN" ]; then
        warn "SKIP_CODESIGN set; can't notarize an unsigned app"
        return 0
    fi
    check_dependency xcrun
    local tmp_zip="$OUT_DIR/.notarize-$PROJECT_NAME.zip"
    rm -f "$tmp_zip"
    ditto -c -k --sequesterRsrc --keepParent "$app_path" "$tmp_zip"
    notarize_file "$tmp_zip" || { rm -f "$tmp_zip"; return 1; }
    rm -f "$tmp_zip"
    info "Stapling notarization ticket to app"
    xcrun stapler staple "$app_path"
}

# --- Packaging Functions ---
copy_app_to_dist() {
    local app_path="$1"
    # In this script, the app is already built into dist by build_project
    # but we'll ensure it's in the final location if needed.
    info "App bundle is at $app_path"
}

package_zip() {
    local app_path="$1"
    local version="$2"
    local zip_name="$SCHEME${version:+-$version}.zip"
    local zip_path="$OUT_DIR/$zip_name"

    info "Zipping app to $zip_path"
    rm -f "$zip_path"
    # Use ditto from the parent of the .app to keep parent
    cd "$OUT_DIR"
    ditto -c -k --sequesterRsrc --keepParent "$PROJECT_NAME.app" "$zip_name"
    success "Zip created: $zip_path"
}

package_dmg() {
    local app_path="$1"
    local version="$2"
    if [ "$CREATE_DMG" != "1" ]; then
        info "CREATE_DMG=0; skipping DMG creation"
        return 0
    fi

    local dmg_name="$SCHEME${version:+-$version}.dmg"
    local dmg_path="$OUT_DIR/$dmg_name"
    local staging_dir="$OUT_DIR/.dmg_src"

    info "Creating DMG at $dmg_path"
    rm -rf "$staging_dir"
    mkdir -p "$staging_dir"
    
    cp -R "$app_path" "$staging_dir/"
    ln -sfn /Applications "$staging_dir/Applications"

    rm -f "$dmg_path"
    hdiutil create -volname "$SCHEME" -srcfolder "$staging_dir" -ov -format UDZO -imagekey zlib-level=9 "$dmg_path" >/dev/null
    rm -rf "$staging_dir"

    if [ -z "$SKIP_CODESIGN" ]; then
        info "Signing DMG"
        codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$dmg_path"
        if [ "$NOTARIZE" = "1" ]; then
            notarize_file "$dmg_path"
            info "Stapling notarization ticket to DMG"
            xcrun stapler staple "$dmg_path"
        fi
    fi
    success "DMG created: $dmg_path"
}

# --- Main Flow ---
main() {
    # Check for help
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    check_dependencies
    handle_versioning

    if ! build_project; then
        error "Build failed."
        exit 1
    fi

    local app_path="$OUT_DIR/$PROJECT_NAME.app"
    if [ ! -d "$app_path" ]; then
        error "Built app not found at: $app_path"
        exit 1
    fi

    if ! sign_app "$app_path"; then
        exit 1
    fi

    if ! notarize_app "$app_path"; then
        exit 1
    fi

    local version=""
    if [ -f "$app_path/Contents/Info.plist" ]; then
        version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist" 2>/dev/null || true)
    fi

    package_zip "$app_path" "$version"
    package_dmg "$app_path" "$version"
    copy_app_to_dist "$app_path"

    if [ -z "$NO_OPEN" ]; then
        open "$app_path"
    fi
}

main "$@"
