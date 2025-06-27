Name:           claude-desktop
Version:        0.1
Release:        1%{?dist}
Summary:        Claude Desktop for Linux
License:        Proprietary
URL:            https://www.anthropic.com
BuildArch:      x86_64
Requires:       nodejs >= 12.0.0, npm, p7zip, sqlite3
Source0:        source.tar.gz
%description
Claude is an AI assistant from Anthropic.
This package provides the desktop interface for Claude.

%prep
tar -xf %{SOURCE0}

%install
mkdir -p %{buildroot}/usr/lib64/%{name}
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons

# Copy files from the INSTALL_DIR
cp -r usr/lib/%{name}/* %{buildroot}/usr/lib64/%{name}/
cp -r usr/bin/* %{buildroot}/usr/bin/
cp -r usr/share/applications/* %{buildroot}/usr/share/applications/
cp -r usr/share/icons/* %{buildroot}/usr/share/icons/

%files
%{_bindir}/claude-desktop
%{_libdir}/%{name}
%{_datadir}/applications/claude-desktop.desktop
%{_datadir}/icons/hicolor/*/apps/claude-desktop.png

%post
npm i electron
# Update icon caches
gtk-update-icon-cache -f -t %{_datadir}/icons/hicolor || :
# Force icon theme cache rebuild
touch -h %{_datadir}/icons/hicolor >/dev/null 2>&1 || :
update-desktop-database %{_datadir}/applications || :

# Set correct permissions for chrome-sandbox
echo "Setting chrome-sandbox permissions..."
SANDBOX_PATH=""
# Check for sandbox in locally packaged electron first
if [ -f "/usr/lib64/claude-desktop/app.asar.unpacked/node_modules/electron/dist/chrome-sandbox" ]; then
    SANDBOX_PATH="/usr/lib64/claude-desktop/app.asar.unpacked/node_modules/electron/dist/chrome-sandbox"

elif [ -n "$SUDO_USER" ]; then
    # Running via sudo: try to get electron from the invoking user's environment
    if su - "$SUDO_USER" -c "command -v electron >/dev/null 2>&1"; then
        ELECTRON_PATH=$(su - "$SUDO_USER" -c "command -v electron")

        POTENTIAL_SANDBOX="\$(dirname "\$(dirname "\$ELECTRON_PATH")")/lib/node_modules/electron/dist/chrome-sandbox"
        if [ -f "\$POTENTIAL_SANDBOX" ]; then
            SANDBOX_PATH="\$POTENTIAL_SANDBOX"
        fi
    fi
else
    # Running directly as root (no SUDO_USER); attempt to find electron in root's PATH
    if command -v electron >/dev/null 2>&1; then
        ELECTRON_PATH=$(command -v electron)
        POTENTIAL_SANDBOX="\$(dirname "\$(dirname "\$ELECTRON_PATH")")/lib/node_modules/electron/dist/chrome-sandbox"
        if [ -f "\$POTENTIAL_SANDBOX" ]; then
            SANDBOX_PATH="\$POTENTIAL_SANDBOX"
        fi
    fi
fi

if [ -n "\$SANDBOX_PATH" ] && [ -f "\$SANDBOX_PATH" ]; then
    echo "Found chrome-sandbox at: \$SANDBOX_PATH"
    chown root:root "\$SANDBOX_PATH" || echo "Warning: Failed to chown chrome-sandbox"
    chmod 4755 "\$SANDBOX_PATH" || echo "Warning: Failed to chmod chrome-sandbox"
    echo "Permissions set for \$SANDBOX_PATH"
else
    echo "Warning: chrome-sandbox binary not found. Sandbox may not function correctly."
fi

%changelog
* Fri Jun 27 2025 vishalvvr - 0.1-1
- Initial package
