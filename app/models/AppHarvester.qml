/**
 * @file AppHarvester
 * @description Materializes Lomiri's AppDrawerModel rows into QML Items
 *   so the rest of HomeSpike can iterate over apps and read role data
 *   (appId, name, icon) by property name from JavaScript. This is the
 *   canonical workaround for QAbstractItemModel role access from QML —
 *   `model.data(index, RoleEnum)` requires C++-side role enum exposure
 *   that we can't rely on.
 *
 *   Wraps `AppDrawerProxyModel` from Utils (NOT Lomiri.Launcher — the
 *   model lives in Lomiri.Launcher, the proxy lives in Utils; easy to
 *   conflate). Sort order: A-Z by app name.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Launcher 0.1
import Utils 0.1

Item {
    id: root

    /** Total app count (for binding to onCountChanged). */
    readonly property int count: harvest.count

    AppDrawerModel { id: source }
    AppDrawerProxyModel {
        id: sorted
        source: source
        sortBy: AppDrawerProxyModel.SortByAToZ
    }

    Repeater {
        id: harvest
        model: sorted
        // Materializes each row's roles into a child Item. The Items
        // never render — they exist purely so JS can index them.
        Item {
            property string appId: model.appId || ""
            property string name:  model.name  || ""
            property string icon:  model.icon  || ""
        }
    }

    /**
     * Get the materialized item at index. Returns null if out of range.
     *
     * @param i Row index (0-based)
     */
    function itemAt(i) {
        return harvest.itemAt(i);
    }
}
