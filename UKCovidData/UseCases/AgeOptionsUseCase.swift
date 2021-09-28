//
//  AgeOptionsUseCase.swift
//  UKCovidData
//
//  Created by Joseph Lord on 29/09/2021.
//

import SwiftUI


struct AgeOption : Identifiable, Equatable {
    let age: String
    var isEnabled: Bool
    var id: String { age }
    
    fileprivate static let initialAgeSelection = "10_14"
    
    static private let ages = ["00_04", "05_09", "10_14", "15_19", "20_24", "25_29", "30_34", "35_39", "40_44",
                      "45_49", "50_54", "55_59", "60_64", "65_69", "70_74", "75_79", "80_84", "85_89", "90+"]
    static var ageOptions = ages.map { AgeOption(age: $0, isEnabled: $0 == initialAgeSelection) }
}

class AgeOptions : ObservableObject {
    @Published var options = AgeOption.ageOptions
    
    func setAll(enabled: Bool) {
        var tmp = options
        tmp.indices.forEach {
            tmp[$0].isEnabled = enabled
        }
        options = tmp
    }
    
    var selected: [String] {
        options.filter { $0.isEnabled }.map { $0.age }
    }
    
    var selectedAgesString: String {
        selected.joined(separator: ", ")
    }
}

struct AgeOptionsKey : EnvironmentKey {
    static var defaultValue: AgeOptions = AgeOptions()
}

extension EnvironmentValues {
    var ageOptions: AgeOptions {
        get { self[AgeOptionsKey.self] }
        set { self[AgeOptionsKey.self] = newValue }
    }
}
