//
//  Area.swift
//  UKCovidData
//
//  Created by Joseph Lord on 29/09/2021.
//


struct Area : Sendable, Identifiable {
    var name: String
    var id: String
    var populationsForAges: [String: Int32]
    var lastWeekCaseRate: Double?
    var lastWeekCaseGrowth: Double?
    
    func populationTotal(ages: [String]) -> Int {
        Int(ages.reduce(0) { $0 + populationsForAges[$1]! })
    }
}
