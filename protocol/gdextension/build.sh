#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

TARGET="release"
PLATFORM=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--target)
            TARGET="$2"
            shift 2
            ;;
        -p|--platform)
            PLATFORM="$2"
            shift 2
            ;;
        -h|--help)
            echo "GURT Godot Extension Build Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -t, --target TARGET      Build target (debug|release) [default: release]"
            echo "  -p, --platform PLATFORM Target platform (windows|linux|macos|macos-intel|current)"
            echo "  -h, --help              Show this help message"
            echo ""
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ "$TARGET" != "debug" && "$TARGET" != "release" ]]; then
    print_error "Invalid target: $TARGET. Must be 'debug' or 'release'"
    exit 1
fi

if [[ -z "$PLATFORM" ]]; then
    case "$(uname -s)" in
        Linux*)     PLATFORM="linux";;
        Darwin*)    PLATFORM="macos";;
        CYGWIN*|MINGW*|MSYS*) PLATFORM="windows";;
        *)          PLATFORM="current";;
    esac
fi

print_info "GURT Godot Extension Build Script"
print_info "Target: $TARGET"
print_info "Platform: $PLATFORM"

print_info "Checking prerequisites..."

if ! command -v cargo >/dev/null 2>&1; then
    print_error "Rust/Cargo not found. Please install Rust: https://rustup.rs/"
    exit 1
fi

print_success "Prerequisites found"

case $PLATFORM in
    windows)
        RUST_TARGET="x86_64-pc-windows-msvc"
        LIB_NAME="gurt_godot.dll"
        ;;
    linux)
        RUST_TARGET="x86_64-unknown-linux-gnu"
        LIB_NAME="libgurt_godot.so"
        ;;
    macos)
        RUST_TARGET="aarch64-apple-darwin"
        LIB_NAME="libgurt_godot.dylib"
        ;;
    macos-intel)
        RUST_TARGET="x86_64-apple-darwin"
        LIB_NAME="libgurt_godot.dylib"
        ;;
    current)
        RUST_TARGET=""
        case "$(uname -s)" in
            Linux*) LIB_NAME="libgurt_godot.so";;
            Darwin*) LIB_NAME="libgurt_godot.dylib";;
            CYGWIN*|MINGW*|MSYS*) LIB_NAME="gurt_godot.dll";;
            *) print_error "Unsupported platform"; exit 1;;
        esac
        ;;
    *)
        print_error "Unknown platform: $PLATFORM"
        exit 1
        ;;
esac

# Create addon directory structure
ADDON_DIR="addon/gurt-protocol"
OUTPUT_DIR="$ADDON_DIR/bin/$PLATFORM"
mkdir -p "$OUTPUT_DIR"

BUILD_CMD="cargo build"
if [[ "$TARGET" == "release" ]]; then
    BUILD_CMD="$BUILD_CMD --release"
fi

if [[ -n "$RUST_TARGET" ]]; then
    print_info "Installing Rust target: $RUST_TARGET"
    rustup target add "$RUST_TARGET"
    BUILD_CMD="$BUILD_CMD --target $RUST_TARGET"
fi

print_info "Building with Cargo..."
$BUILD_CMD

if [[ -n "$RUST_TARGET" ]]; then
    if [[ "$TARGET" == "release" ]]; then
        BUILT_LIB="target/$RUST_TARGET/release/$LIB_NAME"
    else
        BUILT_LIB="target/$RUST_TARGET/debug/$LIB_NAME"
    fi
else
    if [[ "$TARGET" == "release" ]]; then
        BUILT_LIB="target/release/$LIB_NAME"
    else
        BUILT_LIB="target/debug/$LIB_NAME"
    fi
fi

if [[ -f "$BUILT_LIB" ]]; then
    cp "$BUILT_LIB" "$OUTPUT_DIR/$LIB_NAME"
    
    # Copy addon files
    cp gurt_godot.gdextension "$ADDON_DIR/"
    cp plugin.cfg "$ADDON_DIR/"
    cp plugin.gd "$ADDON_DIR/"
    
    print_success "Build completed: $OUTPUT_DIR/$LIB_NAME"
    SIZE=$(du -h "$OUTPUT_DIR/$LIB_NAME" | cut -f1)
    print_info "Library size: $SIZE"
else
    print_error "Built library not found at: $BUILT_LIB"
    exit 1
fi

print_success "Build process completed!"
print_info "Copy the 'addon/gurt-protocol' folder to your project's 'addons/' directory"