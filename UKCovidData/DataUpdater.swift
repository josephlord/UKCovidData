//
//  DataUpdater.swift
//  UKCovidData
//
//  Created by Joseph Lord on 15/09/2021.
//

import Foundation
import CoreData

private let populationUrlDev = Bundle.main.url(
    forResource: "ONS-population_2021-08-05",
    withExtension: "csv")!

private let ltaCasesByAgeRemoteUrl = URL(string: "https://api.coronavirus.data.gov.uk/v2/data?areaType=ltla&metric=newCasesBySpecimenDateAgeDemographics&format=csv")!
private let surreyHeathCasesOnly = URL(string: "https://api.coronavirus.data.gov.uk/v2/data?areaType=ltla&areaCode=E07000214&metric=newCasesBySpecimenDateAgeDemographics&format=csv")!

private let ltaCasesByAgeUrlDev = Bundle.main.url(
    forResource: "LTLA_case_data_by_age",
    withExtension: "csv")!

func updatePopulations(url: URL = populationUrlDev, container: NSPersistentContainer = PersistenceController.shared.container) async throws {
    let context = container.newBackgroundContext()
    try await clear()
    try await update()
    try context.save()
    
    func clear() async throws {
        try await context.perform {
            let fr = AreaAgeDemographics.fetchRequest()
            fr.returnsObjectsAsFaults = true
            fr.fetchLimit = 10_000
            var hasMore = true
            while hasMore {
            print("About to delete")
                let results = try fr.execute()
                hasMore = !results.isEmpty
                results.forEach { context.delete($0) }
                print("Deletion done")
                try context.save()
                print("Saved after delete")
            }
            print("Finished deletion")
        }
    }
    
    func update() async throws {
       var firstline = true
        
        for try await line in url.lines {
            if !firstline {
                _ = try AreaAgeDemographics(csvString: line, context: context)
            } else {
                firstline = false
                guard line == "category,areaCode,gender,age,population" else { throw DataUpdateError.unexpectedColumnHeaders }
            }
        }
    }
}

extension AreaAgeDemographics {
    convenience init?(csvString: String, context: NSManagedObjectContext) throws {
        let values = csvString.split(separator: ",", enclosure: "\"")
        guard values.count == 5,
              let population = Int32(values[4])
        else { throw DataUpdateError.unexpectedValueCount }
        guard values[0] == "AGE_ONLY" && values[2] == "ALL" else { return nil } // We are are ignoring gender specific data
        self.init(context: context)
        areaCode = values[1]
        age = values[3]
        self.population = population
    }
}


func updateCases(url: URL = ltaCasesByAgeRemoteUrl, container: NSPersistentContainer = PersistenceController.shared.container) async throws {
    let context = container.newBackgroundContext()
    let priorDate = Date.now - 1
    try await updateCaseData(url: url, context: context)
    try await clearCaseData(beforeDate: priorDate, context: context)
    try context.save()
}

private func clearCaseData(beforeDate: Date, context: NSManagedObjectContext) async throws {
    try await context.perform {
        let fr = AreaAgeDateCases.fetchRequest()
        fr.returnsObjectsAsFaults = true
        fr.predicate = NSPredicate(format: "timestamp < %@", beforeDate as NSDate)
        fr.fetchLimit = 10_000
        var hasMore = true
        while hasMore {
        print("About to delete")
            let results = try fr.execute()
            hasMore = !results.isEmpty
            results.forEach { context.delete($0) }
            print("Deletion done")
            try context.save()
            print("Saved after delete")
        }
        print("Finished deletion")
    }
}

private func updateCaseData(url: URL, context: NSManagedObjectContext) async throws {
    var areaCodes = [String: String]()
    var firstLine = true
    let timeStamp = Date()
    var dataItemCount = 0
    for try await line in url.lines {
        if !firstLine {
            try await context.perform(schedule: .immediate) {
                let value = try AreaAgeDateCases(csvString: line, timeStamp: timeStamp, context: context)
                areaCodes[value.areaCode!] = value.areaName
            }
            dataItemCount += 1
            if dataItemCount.isMultiple(of: 10000) {
                print(dataItemCount)
                try context.save()
            }
        } else {
            firstLine = false
            guard line == "areaCode,areaName,areaType,date,age,cases,rollingSum,rollingRate"
            else { throw DataUpdateError.unexpectedColumnHeaders }
        }
    }
    if !areaCodes.isEmpty {
        try await context.perform {
            var itr = areaCodes.makeIterator()
            let batchInsert = NSBatchInsertRequest(entity: AreaCodeName.entity()) { (object: NSManagedObject) in
                guard let next = itr.next() else { return false }
                guard let areaCode = object as? AreaCodeName else { fatalError() }
                areaCode.areaName = next.key
                areaCode.areaCode = next.value
                return true
            }
            do {
                try context.execute(batchInsert)
            }
        }
    }
    print("Data import complete. Count: \(dataItemCount)")
}

enum DataUpdateError : Error {
    case unexpectedColumnHeaders
    case unexpectedValueCount
    case unexpectedCaseType
}

extension AreaAgeDateCases {
    convenience init(csvString: String, timeStamp: Date, context: NSManagedObjectContext) throws {
        self.init(context: context)
        let values = csvString.split(separator: ",", enclosure: "\"")
        guard values.count > 6 else {
            print(csvString)
            throw DataUpdateError.unexpectedValueCount
        }
        guard let caseValue = Int32(values[5]) else {
            print(csvString)
            throw DataUpdateError.unexpectedCaseType
        }
        timestamp = timeStamp
        age = String(values[4])
        areaCode = String(values[0])
        areaName = String(values[1])
        areaType = String(values[2])
        date = String(values[3])
        cases = caseValue
    }
}

// https://gist.github.com/mukeshthawani/7dd1d7d66ae7bd451dc34d02a7c0087b
extension String {

    /// Splits a string into an array of subsequences
    /// using a separator.
    ///
    /// Note: Separator is ignored inside enclosure characters.
    func split(separator: String, enclosure: Character = "\"") -> [String] {
        var values: [String] = []
        // Index of the last processed separator
        var lastSeparatorIndex = startIndex
        var isInsideDoubleQuotes = false

        for index in 0..<count {
            let substringStartIndex = self.index(startIndex, offsetBy: index)
            let substringEndIndex = self.index(substringStartIndex, offsetBy: separator.count)

            guard index < count - separator.count else {
                // No more separators
                // Add remaining characters
                values.append(String(self[lastSeparatorIndex..<endIndex]))
                break
            }
            let substring = self[substringStartIndex..<substringEndIndex]

            if substring == separator && !isInsideDoubleQuotes {
                let newstr = String(self[lastSeparatorIndex..<substringStartIndex])
                values.append(newstr)
                lastSeparatorIndex = substringEndIndex
            } else if self[substringStartIndex] == enclosure {
                isInsideDoubleQuotes = !isInsideDoubleQuotes
            }
        }
        return values
    }
}
