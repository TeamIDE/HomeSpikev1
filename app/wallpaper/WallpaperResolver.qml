/**
 * @file WallpaperResolver
 * @description Resolves the URI of the user's chosen wallpaper using the
 *   same precedence Lomiri's own shell uses:
 *     1. AccountsService.backgroundFile  (user pick from Settings → Background)
 *     2. com.lomiri.Shell gsettings → background-picture-uri  (distro default override)
 *     3. Hardcoded UBports default
 *   AccountsService returns a bare path; gsettings returns a file:// URI.
 *   This module normalises both into a file:// URI ready for Image.source.
 *
 * @status Stable. Re-resolves automatically when the user changes wallpaper.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import GSettings 1.0
import AccountsService 0.1

Item {
    id: root

    GSettings {
        id: shellSettings
        schema.id: "com.lomiri.Shell"
    }

    /**
     * Prefix a bare path with file:// if it isn't already a URI.
     *
     * @param pathOrUri Either "/abs/path" or "file:///abs/path"
     * @returns         Always a URI ("file://...") or empty string for empty input
     */
    function _toUri(pathOrUri) {
        if (!pathOrUri) return "";
        return pathOrUri.indexOf("://") === -1 ? "file://" + pathOrUri : pathOrUri;
    }

    /**
     * The currently effective wallpaper URI for this user.
     * Reactive — updates when AccountsService or the shell gsettings change.
     */
    readonly property string uri:
        _toUri(AccountsService.backgroundFile) ||
        shellSettings.backgroundPictureUri ||
        "file:///usr/share/backgrounds/lomiri-default-background.png"
}
