//
//  DataUseCase.swift
//  UKCovidData
//
//  Created by Joseph Lord on 19/09/2021.
//

import Foundation
import CoreData
import DequeModule

struct Area : Sendable {
    var name: String
    var id: String
    var populationsForAges: [String: Int32]
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
    
    init(areas: [Area], ages: [String], context: NSManagedObjectContext) {
        viewModel = CovidDataGroupViewModel(areas: areas, ages: ages, cases: [])
        let request = AreaAgeDateCases.fetchRequest()
        request.predicate = NSPredicate(
            format: "areaCode IN %@ AND age IN %@",
            areas.map { $0.id },
            ages)
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
        let frcSequence = FRCAsyncSequence(fRC: fetchedResultsController, mapper: AreaAgeCasesEntity.init)
        Task {
            do {
                try await context.perform {
                    try self.fetchedResultsController.performFetch()
                    frcSequence.controllerUpdated()
                }
            } catch {
                assertionFailure(error.localizedDescription)
                return
            }
            var model = CovidDataGroupViewModel(areas: areas, ages: ages, cases: [])
            let groupPopulation = areas.reduce(0) { sum, area in
                sum + Int(ages.reduce(0) { $0 + area.populationsForAges[$1]! })
            }
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
        viewModel = newValue
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
