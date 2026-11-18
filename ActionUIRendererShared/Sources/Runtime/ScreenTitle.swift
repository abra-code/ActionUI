// Sources/Runtime/ScreenTitle.swift
/*
 A screen's navigationTitle, from any of its views, as SwiftUI takes it for the screen's bar
 (Searchable.json titles its page from a List inside the root). SwiftUI's order, measured on
 macOS 27: at each view, its views in order first, its own title only when none of them has one,
 so an inner title wins over an outer one and an earlier view's over a later one's. A view's views
 are its content, children and grid rows (with those inserted at run time), then its label,
 background and overlay (SwiftUI takes titles from these too, measured); of a TabView only the
 selected tab. The search does not enter a nested navigation container (only its own title
 counts; its views' titles are its own screens'), a destination, a sheet or popover, a toolbar,
 or a template (its instances are not in the window's view models). An empty title counts as none.
 Read from the view models, so a changed title titles the screen again; on a screen with no title
 at all, that reads every view, about 1 ms for 2000 views (measured in a debug build).
*/

@MainActor
enum ScreenTitle {
    /// The subview lists the search walks: the screen's own views.
    private static let screenKeys = ["content", "children", "rows", "label", "background", "overlay"]

    /// The navigationTitle of the screen whose root is `element`, nil when none of its views has
    /// one.
    static func find(in element: any ActionUIElementBase, windowModel: WindowModel) -> String? {
        if !ToolbarHelper.isNavigationContainer(element.type) {
            for child in screenChildren(element, windowModel) {
                if let title = find(in: child, windowModel: windowModel) {
                    return title
                }
            }
        }
        return ownTitle(element, windowModel)
    }

    private static func ownTitle(_ element: any ActionUIElementBase, _ windowModel: WindowModel) -> String? {
        guard let model = windowModel.viewModels[element.id] else { return nil }
        let title = ActionUIRegistry.shared.currentProperties(element: element, model: model)["navigationTitle"] as? String
        return title?.isEmpty == false ? title : nil
    }

    /// The element's views on its screen, in order: with the views inserted or removed at run time,
    /// and of a TabView only the selected tab, as SwiftUI titles the screen from the tab it shows.
    private static func screenChildren(_ element: any ActionUIElementBase, _ windowModel: WindowModel) -> [any ActionUIElementBase] {
        let model = windowModel.viewModels[element.id]
        let subviews = (model.map { ActionUIRegistry.shared.applyDynamicSubviews(to: element, model: $0) } ?? element).subviews
        if element.type == "TabView" {
            // As TabView+Adwaita.swift selects: the value indexes the tabs with content; out of
            // range, the first.
            let tabs = (subviews?["children"] as? [any ActionUIElementBase] ?? []).filter { $0.subviews?["content"] is any ActionUIElementBase }
            let selected = model.flatMap { TabView.initialValue($0) as? Int } ?? 0
            return tabs.indices.contains(selected) ? [tabs[selected]] : Array(tabs.prefix(1))
        }
        var children: [any ActionUIElementBase] = []
        for key in screenKeys {
            switch subviews?[key] {
            case let one as any ActionUIElementBase:
                children.append(one)
            case let list as [any ActionUIElementBase]:
                children += list
            case let rows as [[any ActionUIElementBase]]:
                children += rows.flatMap { $0 }
            default:
                break
            }
        }
        return children
    }
}
