//
//  NavigationPathHelper.swift
//  ActionUI
//

import SwiftUI

extension NavigationPath {
    func toStringArray() -> [String]? {
        guard let codable = self.codable,
              let data = try? JSONEncoder().encode(codable),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return array
    }
}
