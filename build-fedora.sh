#!/bin/bash
set -e

# Update this URL when a new version of Claude Desktop is released
CLAUDE_DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"

# Inclusive check for Fedora-based system
is_fedora_based() {
    if [ -f "/etc/fedora-release" ]; then
        return 0
    fi
    
    if [ -f "/etc/os-release" ]; then
        grep -qi "fedora" /etc/os-release && return 0
    fi
    
    # Not a Fedora-based system
    return 1
}

if ! is_fedora_based; then
    echo "❌ This script requires a Fedora-based Linux distribution"
    exit 1
fi

# Check for root/sudo
IS_SUDO=false
if [ "$EUID" -eq 0 ]; then
    IS_SUDO=true
    # Check if running via sudo (and not directly as root)
    if [ -n "$SUDO_USER" ]; then
        ORIGINAL_USER="$SUDO_USER"
        ORIGINAL_HOME=$(eval echo ~$ORIGINAL_USER)
    else
        # Running directly as root, no original user context
        ORIGINAL_USER="root"
        ORIGINAL_HOME="/root"
    fi
else
    echo "Please run with sudo to install dependencies"
    exit 1
fi

# Preserve NVM path if running under sudo and NVM exists for the original user
if [ "$IS_SUDO" = true ] && [ "$ORIGINAL_USER" != "root" ] && [ -d "$ORIGINAL_HOME/.nvm" ]; then
    echo "Found NVM installation for user $ORIGINAL_USER, attempting to preserve npm/npx path..."
    # Source NVM script to set up NVM environment variables temporarily
    export NVM_DIR="$ORIGINAL_HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

    # Find the path to the currently active or default Node version's bin directory
    # nvm_find_node_version might not be available, try finding the latest installed version
    NODE_BIN_PATH=$(find "$NVM_DIR/versions/node" -maxdepth 2 -type d -name 'bin' | sort -V | tail -n 1)

    if [ -n "$NODE_BIN_PATH" ] && [ -d "$NODE_BIN_PATH" ]; then
        echo "Adding $NODE_BIN_PATH to PATH"
        export PATH="$NODE_BIN_PATH:$PATH"
    else
        echo "Warning: Could not determine NVM Node bin path. npm/npx might not be found."
    fi
fi

# Print system information
echo "System Information:"
echo "Distribution: $(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)"
echo "Fedora version: $(cat /etc/fedora-release)"

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ $1 not found"
        return 1
    else
        echo "✓ $1 found"
        return 0
    fi
}

# Check and install dependencies
echo "Checking dependencies..."
DEPS_TO_INSTALL=""

# Check system package dependencies
for cmd in sqlite3 7z wget wrestool icotool convert npx rpm rpmbuild; do
    if ! check_command "$cmd"; then
        case "$cmd" in
            "sqlite3")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL sqlite3"
                ;;
            "7z")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL p7zip-plugins"
                ;;
            "wget")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL wget"
                ;;
            "wrestool"|"icotool")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL icoutils"
                ;;
            "convert")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL ImageMagick"
                ;;
            "npx")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL nodejs npm"
                ;;
            "rpm")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL rpm"
                ;;
            "rpmbuild")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL rpmbuild"
                ;;
            "curl")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL curl"
        esac
    fi
done

# Install system dependencies if any
if [ ! -z "$DEPS_TO_INSTALL" ]; then
    echo "Installing system dependencies: $DEPS_TO_INSTALL"
    dnf install -y $DEPS_TO_INSTALL
    echo "System dependencies installed successfully"
fi

# Install electron globally via npm if not present
if ! check_command "electron"; then
    echo "Installing electron via npm..."
    npm install -g electron
    if ! check_command "electron"; then
        echo "Failed to install electron. Please install it manually:"
        echo "sudo npm install -g electron"
        exit 1
    fi
    echo "Electron installed successfully"
fi

PACKAGE_NAME="claude-desktop"
ARCHITECTURE="amd64"
MAINTAINER="Claude Desktop Linux Maintainers"
DESCRIPTION="Claude Desktop for Linux"

# Create working directories
PROJECT_DIR="$(pwd)"
WORK_DIR="$PROJECT_DIR/build"
FEDORA_ROOT="$WORK_DIR/fedora-package"
INSTALL_DIR="$FEDORA_ROOT/usr"

# Clean previous build
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$FEDORA_ROOT/FEDORA"
mkdir -p "$INSTALL_DIR/lib/$PACKAGE_NAME"
mkdir -p "$INSTALL_DIR/share/applications"
mkdir -p "$INSTALL_DIR/share/icons"
mkdir -p "$INSTALL_DIR/bin"

# Install asar if needed
if ! command -v asar > /dev/null 2>&1; then
    echo "Installing asar package globally..."
    npm install -g asar
fi

# Download Claude Windows installer
echo "📥 Downloading Claude Desktop installer..."
CLAUDE_EXE="$WORK_DIR/Claude-Setup-x64.exe"
if ! curl -o "$CLAUDE_EXE" "$CLAUDE_DOWNLOAD_URL"; then
    echo "❌ Failed to download Claude Desktop installer"
    exit 1
fi
echo "✓ Download complete"

# Extract resources
echo "📦 Extracting resources..."
cd "$WORK_DIR"
if ! 7z x -y "$CLAUDE_EXE"; then
    echo "❌ Failed to extract installer"
    exit 1
fi

# Find the nupkg file
NUPKG_FILE=$(find . -name "AnthropicClaude-*-full.nupkg" | head -1)
if [ -z "$NUPKG_FILE" ]; then
    echo "❌ Could not find AnthropicClaude nupkg file"
    exit 1
fi

# Extract the version from the nupkg filename
VERSION=$(echo "$NUPKG_FILE" | grep -oP 'AnthropicClaude-\K[0-9]+\.[0-9]+\.[0-9]+(?=-full\.nupkg)')
echo "📋 Detected Claude version: $VERSION"

if ! 7z x -y "$NUPKG_FILE"; then
    echo "❌ Failed to extract nupkg"
    exit 1
fi
echo "✓ Resources extracted"

# Extract and convert icons
echo "🎨 Processing icons..."
if ! wrestool -x -t 14 "lib/net45/claude.exe" -o claude.ico; then
    echo "❌ Failed to extract icons from exe"
    exit 1
fi

if ! icotool -x claude.ico; then
    echo "❌ Failed to convert icons"
    exit 1
fi
echo "✓ Icons processed"

# Map icon sizes to their corresponding extracted files
declare -A icon_files=(
    ["16"]="claude_13_16x16x32.png"
    ["24"]="claude_11_24x24x32.png"
    ["32"]="claude_10_32x32x32.png"
    ["48"]="claude_8_48x48x32.png"
    ["64"]="claude_7_64x64x32.png"
    ["256"]="claude_6_256x256x32.png"
)

# Install icons
for size in 16 24 32 48 64 256; do
    icon_dir="$INSTALL_DIR/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    if [ -f "${icon_files[$size]}" ]; then
        echo "Installing ${size}x${size} icon..."
        install -Dm 644 "${icon_files[$size]}" "$icon_dir/claude-desktop.png"
    else
        echo "Warning: Missing ${size}x${size} icon"
    fi
done

# Process app.asar
mkdir -p electron-app
cp "lib/net45/resources/app.asar" electron-app/
cp -r "lib/net45/resources/app.asar.unpacked" electron-app/

cd electron-app
npx asar extract app.asar app.asar.contents || { echo "asar extract failed"; exit 1; }

echo "Attempting to set frame:true and remove titleBarStyle/titleBarOverlay in index.js..."

sed -i 's/height:e\.height,titleBarStyle:"default",titleBarOverlay:[^,]\+,/height:e.height,frame:true,/g' app.asar.contents/.vite/build/index.js || echo "Warning: sed command failed to modify index.js"

# Replace native module with stub implementation
echo "Creating stub native module..."
cat > app.asar.contents/node_modules/claude-native/index.js << EOF
// Stub implementation of claude-native using KeyboardKey enum values
const KeyboardKey = {
  Backspace: 43,
  Tab: 280,
  Enter: 261,
  Shift: 272,
  Control: 61,
  Alt: 40,
  CapsLock: 56,
  Escape: 85,
  Space: 276,
  PageUp: 251,
  PageDown: 250,
  End: 83,
  Home: 154,
  LeftArrow: 175,
  UpArrow: 282,
  RightArrow: 262,
  DownArrow: 81,
  Delete: 79,
  Meta: 187
};

Object.freeze(KeyboardKey);

module.exports = {
  getWindowsVersion: () => "10.0.0",
  setWindowEffect: () => {},
  removeWindowEffect: () => {},
  getIsMaximized: () => false,
  flashFrame: () => {},
  clearFlashFrame: () => {},
  showNotification: () => {},
  setProgressBar: () => {},
  clearProgressBar: () => {},
  setOverlayIcon: () => {},
  clearOverlayIcon: () => {},
  KeyboardKey
};
EOF

# Copy Tray icons
mkdir -p app.asar.contents/resources
cp ../lib/net45/resources/Tray* app.asar.contents/resources/

# Repackage app.asar
mkdir -p app.asar.contents/resources/i18n/
cp ../lib/net45/resources/*.json app.asar.contents/resources/i18n/

echo "Downloading Main Window Fix Assets"
cd app.asar.contents
wget -O- https://github.com/emsi/claude-desktop/raw/refs/heads/main/assets/main_window.tgz | tar -zxvf -
cd ..

npx asar pack app.asar.contents app.asar || { echo "asar pack failed"; exit 1; }

# Create native module with keyboard constants
mkdir -p "$INSTALL_DIR/lib/$PACKAGE_NAME/app.asar.unpacked/node_modules/claude-native"
cat > "$INSTALL_DIR/lib/$PACKAGE_NAME/app.asar.unpacked/node_modules/claude-native/index.js" << EOF
// Stub implementation of claude-native using KeyboardKey enum values
const KeyboardKey = {
  Backspace: 43,
  Tab: 280,
  Enter: 261,
  Shift: 272,
  Control: 61,
  Alt: 40,
  CapsLock: 56,
  Escape: 85,
  Space: 276,
  PageUp: 251,
  PageDown: 250,
  End: 83,
  Home: 154,
  LeftArrow: 175,
  UpArrow: 282,
  RightArrow: 262,
  DownArrow: 81,
  Delete: 79,
  Meta: 187
};

Object.freeze(KeyboardKey);

module.exports = {
  getWindowsVersion: () => "10.0.0",
  setWindowEffect: () => {},
  removeWindowEffect: () => {},
  getIsMaximized: () => false,
  flashFrame: () => {},
  clearFlashFrame: () => {},
  showNotification: () => {},
  setProgressBar: () => {},
  clearProgressBar: () => {},
  setOverlayIcon: () => {},
  clearOverlayIcon: () => {},
  KeyboardKey
};
EOF

# Copy app files
cp app.asar "$INSTALL_DIR/lib/$PACKAGE_NAME/"
cp -r app.asar.unpacked "$INSTALL_DIR/lib/$PACKAGE_NAME/"

# Create desktop entry
cat > "$INSTALL_DIR/share/applications/claude-desktop.desktop" << EOF
[Desktop Entry]
Name=Claude
Exec=claude-desktop %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;
MimeType=x-scheme-handler/claude;
StartupWMClass=claude
EOF

# Create launcher script with Wayland flags and logging
cat > "$INSTALL_DIR/bin/claude-desktop" << EOF
#!/bin/bash
LOG_FILE="\$HOME/claude-desktop-launcher.log"
electron /usr/lib64/claude-desktop/app.asar --ozone-platform-hint=auto --enable-logging=file --log-file=\$LOG_FILE --log-level=INFO "\$@"
EOF
chmod +x "$INSTALL_DIR/bin/claude-desktop"

cd $FEDORA_ROOT
tar -czvf source.tar.gz usr

# Create RPM spec file
# call spec file

# Build RPM package
echo "📦 Building RPM package..."
mkdir -p "${WORK_DIR}"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
cp source.tar.gz "$WORK_DIR/SOURCES"
# cp $WORK_DIR/claude-desktop.spec $WORK_DIR/SPECS

RPM_FILE="$(pwd)/x86_64/claude-desktop-${VERSION}-1.fc41.$(uname -m).rpm"
if rpmbuild -ba \
    --define "_topdir ${WORK_DIR}" \
    --define "_rpmdir $(pwd)" \
    "${PROJECT_DIR}/claude-desktop.spec"; then
    echo "✓ RPM package built successfully at: $RPM_FILE"
    echo "🎉 Done! You can now install the RPM with: dnf install $RPM_FILE"
else
    echo "❌ Failed to build RPM package"
    exit 1
fi
