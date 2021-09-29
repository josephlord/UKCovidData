//
//  SearchUseCase.swift
//  UKCovidData
//
//  Created by Joseph Lord on 29/09/2021.
//
import SwiftUI
import CoreData

class SearchUseCase : ObservableObject {
    @Published var areas: [Area] = []
    @Published var growthStats: DistributionStats?
    @Published var lastDate: String?
//    let ageOptions = AgeOptions()
    private let container: NSPersistentContainer
    
    init(container: NSPersistentContainer) {
        self.container = container
        searchString = ""
        updateResults()
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateResults), name: .persistenceControllerReset, object: nil)
    }
    
    @MainActor
    private func updateAreas(areas: [Area]) {
        self.areas = areas
    }
    
    @MainActor
    private func clearCasesInfo() {
        self.areas = areas.map {
            var cleared = $0
            cleared.lastWeekCaseGrowth = nil
            cleared.lastWeekCaseRate = nil
            return cleared
        }
    }
    
    @MainActor
    private func updateGrowthStats(stats: DistributionStats?, date: String?) {
        self.growthStats = stats
        self.lastDate = date
    }
    
    fileprivate func fetchAreas(search: String, context: NSManagedObjectContext) throws -> [Area] {
        let areasFR = AreaCodeName.fetchRequest()
//        areasFR.fetchLimit = 8
        areasFR.sortDescriptors = [NSSortDescriptor(keyPath: \AreaCodeName.areaName, ascending: true)]
        if !searchString.isEmpty {
            areasFR.predicate = NSPredicate(format: "areaName CONTAINS[c] %@", search)
        }
        let areasO = try context.fetch(areasFR)
        
        let populationsFR = AreaAgeDemographics.fetchRequest()
        populationsFR.predicate = NSPredicate(format: "areaCode IN %@", areasO.compactMap { $0.areaCode })
        let populations = try context.fetch(populationsFR)
        
        let areas = areasO.map { area in
            Area(
                name: area.areaName!,
                id: area.areaCode!,
                populationsForAges: Dictionary(uniqueKeysWithValues: populations
                                                .filter { $0.areaCode == area.areaCode }
                                                .map { ($0.age!, $0.population) })
            )
        }
        return areas
    }
    
    fileprivate func fetchCases(areas: [Area], context: NSManagedObjectContext) throws -> ([Area], date: String?) {
        let weekRecordsCount = ages.count * 7
        let fetchRequest = AreaAgeDateCases.fetchRequest()
        fetchRequest.fetchLimit = weekRecordsCount * 2 // Last two week's data
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \AreaAgeDateCases.date, ascending: false)]
        let agesPredicate = NSPredicate(format: "age in %@", ages)
        var date: String? = nil
        let updatedAreas: [Area] = try areas.map { originalArea in
            var updated = originalArea
            let areaPredicate = NSPredicate(format: "areaCode = %@", originalArea.id)
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [areaPredicate, agesPredicate])
            let areaCases = try fetchRequest.execute()
            assert(areaCases.count == fetchRequest.fetchLimit)
            date = areaCases.first!.date
            let mostRecentWeekTotal = areaCases.prefix(weekRecordsCount).reduce(0) { $0 + $1.cases }
            let previousWeekTotal = areaCases.suffix(weekRecordsCount).reduce(0) { $0 + $1.cases }
            updated.lastWeekCaseGrowth = previousWeekTotal > 0 ? Double(mostRecentWeekTotal - previousWeekTotal) / Double(previousWeekTotal) : (mostRecentWeekTotal > 0 ? Double.infinity : 0)
            let population = originalArea.populationTotal(ages: ages)
            guard population > 0 else { throw SearchUseCaseError.noPopulationData }
            updated.lastWeekCaseRate = Double(mostRecentWeekTotal * 100_000) / Double(population)
            return updated
        }
        return (updatedAreas, date)
    }
    
    var searchString: String = "" {
        didSet {
            updateResults()
        }
    }
    
    var ages: [String] = [] {
        didSet {
            if ages != oldValue {
                // Could just update case rates as optimisation
                updateResults()
            }
        }
    }
    
    enum SearchUseCaseError : Error {
        case noPopulationData
    }
    
    private var existingUpdate: Task<(),Never>?
    
    @objc private func updateResults() {
        existingUpdate?.cancel()
        let context = container.newBackgroundContext()
        let search = searchString
        existingUpdate = Task {
            await clearCasesInfo()
            await updateGrowthStats(stats: nil, date: nil)
            do {
                let areas = try await context.perform {
                    return try self.fetchAreas(search: search, context: context)
//                        await self.updateAreas(areas: areas)
                }
                await updateAreas(areas: areas)
                guard !ages.isEmpty else { return }
                let (areasWithCases, date) = try await context.perform {
                    return try self.fetchCases(areas: areas, context: context)
                }
                await updateAreas(areas: areasWithCases)
                if let growthStats = DistributionStats(
                    values: areasWithCases.compactMap(\.lastWeekCaseGrowth),
                    bucketBoundaries: [0, 0.20, 0.50, 1.0, 1.5, 2.0, 3]) {
                    await updateGrowthStats(stats: growthStats, date: date)
                }
            } catch {
                fatalError(error.localizedDescription)
            }
        }
    }
}
