//
//  DataUseCase.swift
//  UKCovidData
//
//  Created by Joseph Lord on 19/09/2021.
//

import Foundation
import CoreData
import DequeModule

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

class DateUseCase : ObservableObject {
    @Published var viewModel: CovidDataGroupViewModel
    private let context: NSManagedObjectContext
    
    private lazy var fetchedResultsController: NSFetchedResultsController<AreaAgeDateCases> = {
        let request = AreaAgeDateCases.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \AreaAgeDateCases.date, ascending: true),
            NSSortDescriptor(keyPath: \AreaAgeDateCases.areaCode, ascending: false),
            NSSortDescriptor(keyPath: \AreaAgeDateCases.age, ascending: false)
        ]
        let fetchedResultsController = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil)
        Task {
            var model = CovidDataGroupViewModel(areas: areas, ages: ages, cases: [])
           
            for try await update in frcSequence {
                model.cases = combineCases(entites: update, population: groupPopulation)
                await updatePublished(newValue: model)
            }
        }
        return fetchedResultsController
    }()
    
    @Published var areas: [Area] = [] {
        didSet {
            updatePredicate()
        }
    }
    
    @Published var ages: [String] = [] {
        didSet {
            updatePredicate()
        }
    }
    
    private var groupPopulation: Int {
        areas.map { $0.populationTotal(ages: ages) }.reduce(0,+)
    }
    
    private lazy var frcSequence = FRCAsyncSequence(fRC: fetchedResultsController, mapper: AreaAgeCasesEntity.init)
    
    private func updatePredicate() {
        guard !areas.isEmpty, !ages.isEmpty else {
            viewModel = CovidDataGroupViewModel()
            return
        }
        fetchedResultsController.fetchRequest.predicate = NSPredicate(
            format: "areaCode IN %@ AND age IN %@",
            areas.map { $0.id },
            ages)
        Task {
            do {
                try await fetchedResultsController.managedObjectContext.perform {
                    try self.fetchedResultsController.performFetch()
                    self.frcSequence.controllerUpdated()
                }
            } catch {
                assertionFailure(error.localizedDescription)
                return
            }
        }
    }
    
    init(context: NSManagedObjectContext) {
        viewModel = CovidDataGroupViewModel()
        self.context = context
    }
    
    func combineCases(entites: [AreaAgeCasesEntity], population: Int) -> [DateCaseValue] {
        guard !entites.isEmpty else { return [] }
        var lastSix: Deque<DateCaseValue> = []
        var output: [DateCaseValue] = []
        var date: String? = nil
        var cases: Int32 = 0
        
        func createNextValue() {
            if let date = date {
                let lastWeek = lastSix.reduce(0) { $0 + $1.cases } + cases
                if lastSix.count > 5 {
                    lastSix.removeFirst()
                }
                let newValue = DateCaseValue(
                    cases: cases,
                    lastWeekCases: lastWeek,
                    lastWeekCaseRate: Double(lastWeek) / Double(population) * 100_000,
                    date: date)
                lastSix.append(newValue)
                output.append(newValue)
            }
            
        }
        
        for entity in entites {
            if entity.date == date {
                cases += entity.cases
            } else {
                createNextValue()
                date = entity.date
                cases = entity.cases
            }
        }
        createNextValue()
        return output
    }
    
    @MainActor
    func updatePublished(newValue: CovidDataGroupViewModel) {
        guard !areas.isEmpty, !ages.isEmpty else { return }
        viewModel = newValue
    }
}

struct DistributionStats {
    var count: Int
    var median: Double
    var min: Double
    var max: Double
    var secondQuintileLower: Double
    var thirdQuintileLower: Double
    var fourthQuintileLower: Double
    var topQuintileLower: Double
    var bucketCounts: [(Group, Int16)]
    enum Group : Hashable {
        case below(Double)
        case range(Double, Double)
        case above(Double)
        
        init(lower: Double?, upper: Double) {
            if let lower = lower {
                self = .range(lower, upper)
            } else {
                self = .below(upper)
            }
        }
    }
    
    init?(values: [Double], bucketBoundaries: [Double]) {
        guard values.count > 5 else { return nil }
        let sorted = values.sorted()
        min = sorted.first!
        max = sorted.last!
        count = sorted.count
        let quintileBoundaries = Self.groupBoundaries(sorted: sorted, numberOfGroups: 5)
        secondQuintileLower = quintileBoundaries[0]
        thirdQuintileLower = quintileBoundaries[1]
        fourthQuintileLower = quintileBoundaries[2]
        topQuintileLower = quintileBoundaries[3]
        median = Self.groupBoundaries(sorted: sorted, numberOfGroups: 2)[0]
        bucketCounts = Self.bucketCounts(sorted: sorted, boundaries: bucketBoundaries)
    }
    
    private static func bucketCounts(sorted: [Double], boundaries: [Double]) -> [(Group, Int16)] {
        guard !boundaries.isEmpty,
              !sorted.isEmpty else { return [] }
        var result = [(Group, Int16)]()
        var previousBoundary: Double? = nil
        var boundaryIterator = boundaries.makeIterator()
        var currentBoundary = boundaryIterator.next()
        var count: Int16 = 0
        for value in sorted {
            while let boundary = currentBoundary,
               value >= boundary {
                result.append((.init(lower: previousBoundary, upper: boundary), count))
                count = 0
                previousBoundary = boundary
                currentBoundary = boundaryIterator.next()
            }
            count += 1
        }
        result.append(((.above(previousBoundary!), count)))
        return result
    }
    
    private static func groupBoundaries(sorted: [Double], numberOfGroups: Int) -> [Double] {
        guard numberOfGroups > 1 else { return [] }
        let groupSize = Double(sorted.count) / Double(numberOfGroups)
        guard groupSize > 1 else { return [] }
        return (1...(numberOfGroups - 1)).map {
            // Just returning a single value isn't ideal but is good enough for first pass
            sorted[Int((Double($0) * groupSize).rounded(.toNearestOrAwayFromZero))]
        }
    }
}

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
            guard population > 0 else { fatalError() }
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
            // Could just update case rates as optimisation
            updateResults()
        }
    }
    
    
    private var existingUpdate: Task<(),Never>?
    
    @objc private func updateResults() {
        existingUpdate?.cancel()
        let context = container.newBackgroundContext()
        let search = searchString
        existingUpdate = Task {
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
    
class FRCAsyncSequence<FR, OUT> : NSObject, AsyncSequence, NSFetchedResultsControllerDelegate
where FR : NSFetchRequestResult, OUT : Sendable {
    typealias AsyncIterator = Iterator
    typealias Element = [OUT]
    
    let fRC: NSFetchedResultsController<FR>
    let mapper: (FR) -> OUT
    
    init(fRC: NSFetchedResultsController<FR>, mapper: @escaping (FR) -> OUT) {
        self.fRC = fRC
        self.mapper = mapper
        super.init()
        fRC.delegate = self
    }
    
    let iterator = Iterator()
    
    func makeAsyncIterator() -> Iterator {
        iterator
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        controllerUpdated()
    }
    
    func controllerUpdated() {
        let results = fRC.fetchedObjects?.map(mapper) ?? []
        Task {
            await iterator.update(value: results)
        }
    }
    
    final actor Iterator : AsyncIteratorProtocol {
        typealias Element = [OUT]
        
        var latestResult: [OUT]?
        private var continuation: CheckedContinuation<[OUT], Never>?
        
        func update(value: [OUT]) {
            if let continuation = continuation {
                self.continuation = nil
                continuation.resume(returning: value)
            } else {
                latestResult = value
            }
        }
        
        func next() async throws -> [OUT]? {
            if let latest = latestResult {
                latestResult = nil
                return latest
            }
            return await withCheckedContinuation({ (continuation: CheckedContinuation<[OUT], Never>) in
                if let latest = latestResult {
                    latestResult = nil
                    continuation.resume(returning: latest)
                }
                self.continuation = continuation
            })
        }
    }
    
}
