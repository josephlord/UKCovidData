//
//  Cases.swift
//  UKCovidData
//
//  Created by Joseph Lord on 29/09/2021.
//

struct DateCaseValue : Sendable, Identifiable {
    var cases: Int32
    var lastWeekCases: Int32
    var lastWeekCaseRate: Double?
    var date: String
    var id: String { date }
}

struct CovidDataGroupViewModel : Sendable{
    var areas: [Area]
    var ages: [String]
    var cases: [DateCaseValue]
    
    init(areas: [Area], ages: [String], cases: [DateCaseValue]) {
        self.areas = areas
        self.ages = ages
        self.cases = cases
    }
    
    init() {
        areas = []
        ages = []
        cases = []
    }
}

struct AreaAgeCasesEntity : Sendable {
    var date: String
    var areaCode: String
    var age: String
    var cases: Int32
    init(object: AreaAgeDateCases) {
        areaCode = object.areaCode!
        age = object.age!
        cases = object.cases
        date = object.date!
    }
}
