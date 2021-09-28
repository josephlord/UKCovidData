//
//  DataUseCase.swift
//  UKCovidData
//
//  Created by Joseph Lord on 19/09/2021.
//

import Foundation
import CoreData
import DequeModule

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
