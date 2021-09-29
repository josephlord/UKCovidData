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
    var bucketCounts: [BucketCount]
    
    struct BucketCount : Identifiable {
        var group: Group
        var count: Int16
        
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
            
            func label(valueFormat: (Double) -> String) -> String {
                switch self {
                case .below(let below):
                    return "Below \(valueFormat(below))"
                case .range(let from, let to):
                    return "\(valueFormat(from)) to \(valueFormat(to))"
                case .above(let above):
                    return "Above \(valueFormat(above))"
                }
            }
        }
        var id: String {
            switch group {
            case .below:
                return "b"
            case .range(let lower, _):
                return "\(lower)"
            case .above:
                return "a"
            }
        }
    }
    init?(values: [Double], bucketBoundaries: [Double]) {
        let sorted = values.sorted()
        min = sorted.first ?? 0
        max = sorted.last ?? 0
        count = sorted.count
        if values.count > 5 {
            let quintileBoundaries = Self.groupBoundaries(sorted: sorted, numberOfGroups: 5)
            secondQuintileLower = quintileBoundaries[0]
            thirdQuintileLower = quintileBoundaries[1]
            fourthQuintileLower = quintileBoundaries[2]
            topQuintileLower = quintileBoundaries[3]
        } else {
            self.secondQuintileLower = 0
            self.thirdQuintileLower = 0
            self.fourthQuintileLower = 0
            self.topQuintileLower = 0
        }
        if values.count > 2 {
            median = Self.groupBoundaries(sorted: sorted, numberOfGroups: 2)[0]
        } else {
            median = Double(values.reduce(0, +)) / Double( Swift.max(values.count, 1))
        }
        bucketCounts = Self.bucketCounts(sorted: sorted, boundaries: bucketBoundaries)
    }
    
    init() {
        self.count = 0
        self.median = 0
        self.min = 0
        self.max = 0
        self.secondQuintileLower = 0
        self.thirdQuintileLower = 0
        self.fourthQuintileLower = 0
        self.topQuintileLower = 0
        self.bucketCounts = []
    }
    
    private static func bucketCounts(sorted: [Double], boundaries: [Double]) -> [BucketCount] {
        guard !boundaries.isEmpty,
              !sorted.isEmpty else { return [] }
        var result = [BucketCount]()
        var previousBoundary: Double? = nil
        var boundaryIterator = boundaries.makeIterator()
        var currentBoundary = boundaryIterator.next()
        var count: Int16 = 0
        for value in sorted {
            while let boundary = currentBoundary,
               value >= boundary {
                result.append(.init(group: .init(lower: previousBoundary, upper: boundary), count: count))
                count = 0
                previousBoundary = boundary
                currentBoundary = boundaryIterator.next()
            }
            count += 1
        }
        result.append(.init(group: .above(previousBoundary!), count: count))
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
