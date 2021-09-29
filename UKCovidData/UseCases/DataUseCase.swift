//
//  DataUseCase.swift
//  UKCovidData
//
//  Created by Joseph Lord on 19/09/2021.
//

import Foundation
import CoreData
import DequeModule
import Combine

struct CasesSince {
    var casesMar2020: Int32
    var casesJun2021: Int32
    var proportionMar2020: Double
    var proportionJun2021: Double
}

class DateUseCase : ObservableObject {
    @Published var viewModel: CovidDataGroupViewModel
    @Published var casesSince: CasesSince?
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
                let cases = combineCases(entites: update, population: groupPopulation)
                model.cases = cases
                await updatePublished(newValue: model)
                
                Task {
                    let casesSince = casesSince(cases: cases, population: groupPopulation)
                    await updateCasesSince(newValue: casesSince)
                }
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
            casesSince = nil
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
    
    private func casesSince(cases: [DateCaseValue], population: Int) -> CasesSince {
        var caseTotal: Int32 = 0
        var before1Jun = false
        var countSinceJun: Int32 = 0
        for dcv in cases.reversed() {
            caseTotal += dcv.cases
            if !before1Jun && dcv.date == "2021-06-01" {
                before1Jun = true
                countSinceJun = caseTotal
            }
        }
        return CasesSince(
            casesMar2020: caseTotal,
            casesJun2021: countSinceJun,
            proportionMar2020: Double(caseTotal) / Double(max(1, population)),
            proportionJun2021: Double(countSinceJun) / Double(max(1, population)))
    }
    
    init(context: NSManagedObjectContext) {
        viewModel = CovidDataGroupViewModel()
        self.context = context
    }
    
    private func combineCases(entites: [AreaAgeCasesEntity], population: Int) -> [DateCaseValue] {
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
    
    @MainActor
    func updateCasesSince(newValue: CasesSince?) {
        casesSince = newValue
    }
}
