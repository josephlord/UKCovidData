//
//  DistributionStats.swift
//  UKCovidData
//
//  Created by Joseph Lord on 29/09/2021.
//

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
