import GUIForCLICore
import SwiftUI

struct SidebarPageGroup: Identifiable {
  let id: String
  let title: String?
  var pages: [BundlePage]

  static func groups(for pages: [BundlePage]) -> [SidebarPageGroup] {
    pages.reduce(into: []) { groups, page in
      let groupTitle = normalizedGroupTitle(page.sidebarGroup)
      if let lastIndex = groups.indices.last, groups[lastIndex].title == groupTitle {
        groups[lastIndex].pages.append(page)
      } else {
        let groupID = "\(groups.count)-\(groupTitle ?? "ungrouped")"
        groups.append(SidebarPageGroup(id: groupID, title: groupTitle, pages: [page]))
      }
    }
  }

  private static func normalizedGroupTitle(_ title: String?) -> String? {
    guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
      return nil
    }
    return title
  }
}
