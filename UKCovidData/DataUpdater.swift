//
//  DataUpdater.swift
//  UKCovidData
//
//  Created by Joseph Lord on 15/09/2021.
//

import Foundation
import CoreData


final class DataUpdater {
    
    private init() {
        
    }
    
    static var shared = DataUpdater.init()

    private static let populationUrlDev = Bundle.main.url(
        forResource: "ONS-population_2021-08-05",
        withExtension: "csv")!

    private static func ltaCasesByAgeRemoteUrl(lastDateHeld: String?) -> URL {
        let dateFilter = lastDateHeld.map { ";date>\($0)" } ?? ""
        var urlComps = URLComponents(string: "https://api.coronavirus.data.gov.uk/v1/data")!
        urlComps.queryItems = [
            .init(name: "format", value: "csv"),
            .init(name: "structure", value: """
                {"date":"date","areaName":"areaName","areaCode":"areaCode","cases":"newCasesBySpecimenDateAgeDemographics"}
                """),
            .init(name: "filters", value: "areaType=ltla\(dateFilter)"),
            .init(name: "page", value: "1"),
        ]
        return urlComps.url!
    //    return URL(string: "https://api.coronavirus.data.gov.uk/v2/data?areaType=ltla&metric=newCasesBySpecimenDateAgeDemographics&format=csv")!
    }
    
    var newestCasesDate: String? {
        get {
            UserDefaults.standard.string(forKey: "newestCasesDate")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "newestCasesDate")
        }
    }
    
    //private let surreyHeathCasesOnly = URL(string: "https://api.coronavirus.data.gov.uk/v2/data?areaType=ltla&areaCode=E07000214&metric=newCasesBySpecimenDateAgeDemographics&format=csv")!

//    private let ltaCasesByAgeUrlDev = Bundle.main.url(
//        forResource: "LTLA_case_data_by_age",
//        withExtension: "csv")!

    func updatePopulations(url: URL = populationUrlDev, container: NSPersistentContainer = PersistenceController.shared.container) async throws {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    //    try await clear()
        try await update()
        try context.save()
        
    //    func clear() async throws {
    //        try await context.perform {
    //            let fr = AreaAgeDemographics.fetchRequest()
    //            fr.returnsObjectsAsFaults = true
    //            fr.fetchLimit = 10_000
    //            var hasMore = true
    //            while hasMore {
    //            print("About to delete")
    //                let results = try fr.execute()
    //                hasMore = !results.isEmpty
    //                results.forEach { context.delete($0) }
    //                print("Deletion done")
    //                try context.save()
    //                print("Saved after delete")
    //            }
    //            print("Finished deletion")
    //        }
    //    }
        
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


    var ltaCasesByAgeRemoteUrl: URL {
        Self.ltaCasesByAgeRemoteUrl(lastDateHeld: newestCasesDate)
    }


    func updateCases(url: URL? = nil, container: NSPersistentContainer = PersistenceController.shared.container) async throws {
        let requestUrl = url ?? ltaCasesByAgeRemoteUrl
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    //    let priorDate = Date.now - 1
        try await updateCaseData(url: requestUrl, context: context)
    //    try await clearCaseData(beforeDate: priorDate, context: context)
        try context.save()
    }

    //private func clearCaseData(beforeDate: Date, context: NSManagedObjectContext) async throws {
    //    try await context.perform {
    //        let fr = AreaAgeDateCases.fetchRequest()
    //        fr.returnsObjectsAsFaults = true
    //        fr.predicate = NSPredicate(format: "timestamp < %@", beforeDate as NSDate)
    //        fr.fetchLimit = 10_000
    //        var hasMore = true
    //        while hasMore {
    //        print("About to delete")
    //            let results = try fr.execute()
    //            hasMore = !results.isEmpty
    //            results.forEach { context.delete($0) }
    //            print("Deletion done")
    //            try context.save()
    //            print("Saved after delete")
    //        }
    //        print("Finished deletion")
    //    }
    //}
    
    fileprivate struct CasesStruct {
        var date: String
        var areaName: String
        var areaCode: String
        var cases: Int32
        var ages: String
    }
    
    private func csvLineToCasesArray(csvString: String) throws -> [CasesStruct] {
        let values = csvString.csvSplit(separator: ",", enclosure: "\"")
        let date = values[0]
        let areaName = values[1]
        let areaCode = values[2]
        let ageCases = values[3].split(separator: "{").dropFirst()
        var templateStruct = CasesStruct(date: date, areaName: areaName, areaCode: areaCode, cases: 0, ages: "")
        return ageCases.map {
            let trimmed1 = $0.dropFirst(8)
            let ageEndIndex = trimmed1.firstIndex(of: "'")!
            templateStruct.ages = String(trimmed1[..<ageEndIndex])
            let trimmed2 = trimmed1[ageEndIndex...].dropFirst(12)
            let casesEndIndex = trimmed2.firstIndex(of: ",")!
            templateStruct.cases = Int32(trimmed2[..<casesEndIndex])!
            return templateStruct
        }
    }
    

    /// returns areacode, areaname
    private func batchWriteLinesToCaseData(lines: [String], latestDate: inout String?, areaCodes: inout [String: String], context: NSManagedObjectContext) async throws {
        var areaCodeTmp = areaCodes
        let records = try lines.flatMap(self.csvLineToCasesArray)
        if latestDate == nil {
            latestDate = records.first?.date
        }
        try await context.perform {
            var itr = records.makeIterator()
            let batchInsert = NSBatchInsertRequest(entity: AreaAgeDateCases.entity()) { (object: NSManagedObject) in
                guard let next = itr.next() else { return true }
                guard let aadc = object as? AreaAgeDateCases else { fatalError() }
                aadc.updateFromCasesStruct(record: next)
                areaCodeTmp[next.areaCode] = next.areaName
                return false
            }
            let result = try context.execute(batchInsert)
            print("Batch insert result: \(String(describing: result))")
        }
        areaCodes = areaCodeTmp
        try context.save()
    }

    private func updateCaseData(url: URL, context: NSManagedObjectContext) async throws {
        var areaCodes = [String: String]()
        var firstLine = true
        var dataItemCount = 0
        var linesBatch: [String] = []
        var firstDate: String? = nil
        for try await line in url.lines {
            if !firstLine {
                linesBatch.append(line)
                dataItemCount += 1
                if dataItemCount.isMultiple(of: 1 << 10) {
                    try await batchWriteLinesToCaseData(lines: linesBatch, latestDate: &firstDate, areaCodes: &areaCodes, context: context)
                    print(dataItemCount)
                    linesBatch = []
                }
            } else {
                firstLine = false
                guard line == "date,areaName,areaCode,cases"
                else { throw DataUpdateError.unexpectedColumnHeaders }
            }
        }
        try await batchWriteLinesToCaseData(lines: linesBatch, latestDate: &firstDate, areaCodes: &areaCodes, context: context)
        print("Cases insert complete: \(dataItemCount) case numbers")
        if !areaCodes.isEmpty {
            try await context.perform {
                var itr = areaCodes.makeIterator()
                let batchInsert = NSBatchInsertRequest(entity: AreaCodeName.entity()) { (object: NSManagedObject) in
                    guard let next = itr.next() else { return true }
                    guard let areaCode = object as? AreaCodeName else { fatalError() }
                    areaCode.areaName = next.value
                    areaCode.areaCode = next.key
                    return false
                }
                do {
                    let result = try context.execute(batchInsert)
                    print("Batch insert result: \(result)")
                }
            }
            try context.save()
        }
        newestCasesDate = firstDate
        PersistenceController.shared.resetPersistentContexts()
    //    PersistenceController.shared.container
        print("Data import complete. Count: \(dataItemCount)")
    }

    enum DataUpdateError : Error {
        case unexpectedColumnHeaders
        case unexpectedValueCount
        case unexpectedCaseType
    }
}

extension AreaAgeDateCases {
    
    /// Updates the values from the input and returns the name of the area
    /// - Parameter record: Struct with the case data
    /// - Returns: Area name
    fileprivate func updateFromCasesStruct(record: DataUpdater.CasesStruct) {
        age = record.ages
        areaCode = record.areaCode
        date = record.date
        cases = record.cases
    }
    
    /// Updates the values from the input and returns the name of the area - Unused (used on V2 API CSV data)
    /// - Parameter csvString: CSV line to from downloaded data
    /// - Returns: Area name
    func updateFromCSV(csvString: String) throws -> String {
        let values = csvString.csvSplit(separator: ",", enclosure: "\"")
        guard values.count > 6 else {
            print(csvString)
            throw DataUpdater.DataUpdateError.unexpectedValueCount
        }
        guard let caseValue = Int32(values[5]) else {
            print(csvString)
            throw DataUpdater.DataUpdateError.unexpectedCaseType
        }
        age = String(values[4])
        areaCode = String(values[0])
        date = String(values[3])
        cases = caseValue
        return String(values[1])
    }
}

extension AreaAgeDemographics {
    convenience init?(csvString: String, context: NSManagedObjectContext) throws {
        let values = csvString.csvSplit(separator: ",", enclosure: "\"")
        guard values.count == 5,
              let population = Int32(values[4])
        else { throw DataUpdater.DataUpdateError.unexpectedValueCount }
        guard values[0] == "AGE_ONLY" && values[2] == "ALL" else { return nil } // We are are ignoring gender specific data
        self.init(context: context)
        areaCode = values[1]
        age = values[3]
        self.population = population
    }
}
// https://gist.github.com/mukeshthawani/7dd1d7d66ae7bd451dc34d02a7c0087b
extension String {

    /// Splits a string into an array of subsequences
    /// using a separator.
    ///
    /// Note: Separator is ignored inside enclosure characters.
    func csvSplit(separator: String, enclosure: Character = "\"") -> [String] {
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
