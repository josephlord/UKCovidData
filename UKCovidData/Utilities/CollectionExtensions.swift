//
//  CollectionExtensions.swift
//  UKCovidData
//
//  Created by Joseph Lord on 29/09/2021.
//

extension Collection {
    func sorted(reverse: Bool, by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> [Element] {
        if reverse {
            return try sorted { lhs, rhs in try areInIncreasingOrder(rhs, lhs) }
        } else {
            return try sorted(by: areInIncreasingOrder)
        }
    }
}
