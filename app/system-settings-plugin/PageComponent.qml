/**
 * @file PageComponent
 * @description Lomiri System Settings page for HomeSpike. Lives at
 *   Settings → Personal → HomeSpike. Currently exposes a single toggle
 *   (`enabled`) bound to the com.lomiri.HomeSpike gsettings schema.
 *
 *   The four lomiri-overrides files (Shell.qml, Stage.qml, Spread
 *   visibility, Drawer.qml) plus HomeSpike's own main.qml all bind to
 *   the same gsettings key, so flipping this switch takes effect live
 *   with no reboot.
 *
 *   Installed to:
 *     /usr/share/lomiri-system-settings/qml-plugins/home-spike/PageComponent.qml
 *   Discovered via:
 *     /usr/share/lomiri-system-settings/home-spike.settings
 *
 * @status Stable.
 * @issues None
 * @todo
 *   - [ ] When the widget API ships (v2), grow this page with a
 *         "Widgets" section: installed widgets list, per-source trust
 *         toggles for the allowlist.
 */
import GSettings 1.0
import QtQuick 2.12
import SystemSettings 1.0
import SystemSettings.ListItems 1.0 as SettingsListItems
import Lomiri.Components 1.3

ItemPage {
    id: root
    objectName: "homeSpikePage"
    title: i18n.tr("HomeSpike")
    flickable: flick

    GSettings {
        id: hsSettings
        schema.id: "com.lomiri.HomeSpike"
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: parent.width
        contentHeight: contentItem.childrenRect.height
        boundsBehavior: (contentHeight > root.height) ?
            Flickable.DragAndOvershootBounds : Flickable.StopAtBounds

        Column {
            anchors {
                left: parent.left
                right: parent.right
            }
            spacing: units.gu(1)

            SettingsItemTitle {
                text: i18n.tr("Home screen")
            }

            SettingsListItems.Standard {
                id: enableRow
                objectName: "enableHomeSpike"
                text: i18n.tr("HomeSpike home screen")
                layout.subtitle.text: i18n.tr(
                    "Use HomeSpike as your home surface. When off, the phone "
                  + "reverts to stock Lomiri behavior — the Ubuntu logo opens "
                  + "the app drawer instead of HomeSpike."
                )

                Switch {
                    id: enableSwitch
                    checked: hsSettings.enabled
                    // Lomiri.Components Switch fires onTriggered (not
                    // onClicked) on user interaction. onClicked never
                    // fires for this widget.
                    onTriggered: hsSettings.enabled = checked
                }
            }

            SettingsItemTitle {
                text: i18n.tr("About")
            }

            SettingsListItems.Standard {
                text: i18n.tr("Version")
                layout.subtitle.text: "1.0"
            }

            SettingsListItems.Standard {
                text: i18n.tr("Source")
                layout.subtitle.text: "github.com/TeamIDE/HomeSpikev1"
            }
        }
    }
}
