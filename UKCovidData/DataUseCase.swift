//
//  DataUseCase.swift
//  UKCovidData
//
//  Created by Joseph Lord on 19/09/2021.
//

import Foundation
import CoreData
import DequeModule

struct Area : Sendable, Identifiable{
    var name: String
    var id: String
    var populationsForAges: [String: Int32]
    
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
    private let fetchedResultsController: NSFetchedResultsController<AreaAgeDateCases>
    
    var areas: [Area] = [] {
        didSet {
            updatePredicate()
        }
    }
    
    var ages: [String] = ["10_14"] {
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
   
        let request = AreaAgeDateCases.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \AreaAgeDateCases.date, ascending: true),
            NSSortDescriptor(keyPath: \AreaAgeDateCases.areaCode, ascending: false),
            NSSortDescriptor(keyPath: \AreaAgeDateCases.age, ascending: false)
        ]
        fetchedResultsController = .init(
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


class SearchUseCase : ObservableObject {
    @Published var areas: [Area] = []
    private let container: NSPersistentContainer
    
    init(container: NSPersistentContainer) {
        self.container = container
        searchString = ""
        updateResults()
    }
    
    @MainActor
    func updateAreas(areas: [Area]) {
        self.areas = areas
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
    
    var searchString: String = "" {
        didSet {
            updateResults()
//            guard !searchString.isEmpty else {
//                areas = []
//                return
//            }
        }
    }
    
    private func updateResults() {
        let context = container.newBackgroundContext()
        let search = searchString
        Task {
            do {
                let areas = try await context.perform {
                    return try self.fetchAreas(search: search, context: context)
//                        await self.updateAreas(areas: areas)
                }
                await updateAreas(areas: areas)
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
