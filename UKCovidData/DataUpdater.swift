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

    private static func ltaCasesByAgeRemoteUrl(lastDateHeld: String?, page: Int8) -> URL {
        let dateFilter = lastDateHeld.map { ";date>\($0)" } ?? ""
        var urlComps = URLComponents(string: "https://api.coronavirus.data.gov.uk/v1/data")!
        urlComps.queryItems = [
            .init(name: "format", value: "csv"),
            .init(name: "structure", value: """
                {"date":"date","areaName":"areaName","areaCode":"areaCode","cases":"newCasesBySpecimenDateAgeDemographics"}
                """),
            .init(name: "filters", value: "areaType=ltla\(dateFilter)"),
            .init(name: "page", value: "\(page)")
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
    
    func updatePopulations(url: URL = populationUrlDev, container: NSPersistentContainer = PersistenceController.shared.container) async throws {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        try await update()
        try context.save()

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

    func updateCases() async throws {
        var receivedRecords = true
        var pageNumber: Int8 = 1
        let latestDataDate = self.newestCasesDate
        var updatedLatestDate = latestDataDate
        while receivedRecords && pageNumber < 30 {
            let dateOfFirstRecord: String?
            let url = Self.ltaCasesByAgeRemoteUrl(lastDateHeld: latestDataDate, page: pageNumber)
            print("Requesting page \(pageNumber)- \(url)")
            (receivedRecords, dateOfFirstRecord) = try await updateCases(url: url)
            if pageNumber == 1 {
                updatedLatestDate = dateOfFirstRecord
            }
            pageNumber += 1
        }
        // If no error thrown we can update the newestCasesDate
        if let updatedLatestDate = updatedLatestDate {
            self.newestCasesDate = updatedLatestDate
        }
    }

    fileprivate func updateCases(url: URL, container: NSPersistentContainer = PersistenceController.shared.container) async throws -> (Bool, String?) {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let didReceiveRecords = try await updateCaseData(url: url, context: context)
        try context.save()
        return didReceiveRecords
    }
    
    fileprivate struct CasesStruct {
        var date: String
        var areaName: String
        var areaCode: String
        var cases: Int32
        var ages: String
    }
    
    private func csvLineToCasesArray(csvString: String) throws -> [CasesStruct] {
        let values = csvString.csvSplit(separator: ",", enclosure: "\"")
        let date = String(values[0])
        let areaName = String(values[1])
        let areaCode = String(values[2])
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
    
    /// Request and process the case data from the URL
    /// - Parameters:
    ///   - url: URL to request the CSV cases data from
    ///   - context: Managed object context to write to
    /// - Returns: Tuple of Bool (true if at least one record was processed and the date value of the first record)
    private func updateCaseData(url: URL, context: NSManagedObjectContext) async throws -> (Bool, String?) {
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
        PersistenceController.shared.resetPersistentContexts()
        print("Data import complete. Count: \(dataItemCount)")
        return (dataItemCount > 0, firstDate)
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
        areaCode = String(values[1])
        age = String(values[3])
        self.population = population
    }
}
// https://gist.github.com/mukeshthawani/7dd1d7d66ae7bd451dc34d02a7c0087b
extension String {

    /// Splits a string into an array of subsequences
    /// using a separator.
    ///
    /// Note: Separator is ignored inside enclosure characters.
    func csvSplit(separator: String, enclosure: Character = "\"") -> [String.SubSequence] {
        var values: [String.SubSequence] = []
        // Index of the last processed separator
        var lastSeparatorIndex = startIndex
        var isInsideDoubleQuotes = false
        let separatorCount = separator.count

        for loopIndex in indices {
            let substringStartIndex = loopIndex
            let substringEndIndex = self.index(substringStartIndex, offsetBy: separatorCount)

            guard substringEndIndex < endIndex else {
                // No more separators
                // Add remaining characters
                values.append(self[lastSeparatorIndex..<endIndex])
                break
            }
            let substring = self[substringStartIndex..<substringEndIndex]

            if !isInsideDoubleQuotes && substring == separator  {
                let newstr = self[lastSeparatorIndex..<substringStartIndex]
                values.append(newstr)
                lastSeparatorIndex = substringEndIndex
            } else if self[substringStartIndex] == enclosure {
                isInsideDoubleQuotes.toggle()
            }
        }
        return values
    }
}
