//
//  FRCAsyncSequence.swift
//  UKCovidData
//
//  Created by Joseph Lord on 29/09/2021.
//

import CoreData

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

