//
//  Formatters.swift
//  UKCovidData
//
//  Created by Joseph Lord on 29/09/2021.
//

import Foundation

let rateFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.maximumFractionDigits = 0
    f.minimumFractionDigits = 0
    return f
}()
