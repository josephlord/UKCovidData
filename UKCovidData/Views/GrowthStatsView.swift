//
//  GrowthStatsView.swift
//  UKCovidData
//
//  Created by Joseph Lord on 29/09/2021.
//

import SwiftUI

let percentFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.minimumFractionDigits = 1
    f.maximumFractionDigits = 1
    f.numberStyle = .percent
    return f
}()

func growthFormat(_ val: Double) -> String {
    percentFormatter.string(from: val as NSNumber) ?? "-"
}


struct GrowthStatsView: View {
    
    let heading: String
    let stats: DistributionStats
    enum ValueType {
        case growth
    }
    let valueType: ValueType = .growth
    let format: (Double) -> String
    
    
    var body: some View {
        VStack {
            Text(heading)
                .font(Font.title)
            Spacer()
            StatSummaryView(stats: stats, format: format)
            ScrollView {
                Text("Bucket counts")
                    .font(Font.title)
                HStack {
                    BucketsView(stats: stats, format: format)
                        .font(Font.title3)
                    Spacer()
                }
                Spacer()
                Text("Quintiles")
                    .font(Font.title)
                QuintilesView(stats: stats, format: format)
            }
        }.padding()
            .navigationTitle("Growth Stats")
            
    }
}

struct StatSummaryView : View {
    let stats: DistributionStats
    let format: (Double) -> String
    
    var body: some View {
        HStack{
            VStatView(label: "Count", value: "\(stats.count)")
            Spacer()
            VStatView(label: "Median", value: format(stats.median))
            Spacer()
            VStatView(label: "Min", value: format(stats.min))
            Spacer()
            VStatView(label: "Max", value: format(stats.max))
        }
    }
}

struct BucketsView : View {
    let stats: DistributionStats
    let format: (Double) -> String

    var body: some View {
        LazyVGrid(columns: [.init(.flexible(minimum: 200, maximum: 300)), .init(.fixed(40)), .init(.flexible(minimum: 0, maximum: 300))], spacing: 4) {
            ForEach(stats.bucketCounts) { bucket in
                HStack {
                    Spacer()
                    Text(bucket.group.label(valueFormat: format))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
                HStack {
                    Text("\(bucket.count)")
                        .bold()
                    Spacer()
                }
                Spacer()
            }
        }
    }
}

struct QuintilesView : View {
    let stats: DistributionStats
    let format: (Double) -> String

    var body: some View {
        LazyVGrid(columns: [.init(.flexible(minimum: 40, maximum: 120)), .init(.flexible(minimum: 280, maximum: 300))], spacing: 4) {
            HStack {
                Spacer()
                Text("1st")
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
            HStack {
                Text("\(format(stats.min)) to \(format(stats.secondQuintileLower))")
                    .bold()
                Spacer()
            }
            HStack {
                Spacer()
                Text("2nd")
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
            HStack {
                Text("\(format(stats.secondQuintileLower)) to \(format(stats.thirdQuintileLower))")
                    .bold()
                Spacer()
            }
            HStack {
                Spacer()
                Text("3rd")
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
            HStack {
                Text("\(format(stats.thirdQuintileLower)) to \(format(stats.fourthQuintileLower))")
                    .bold()
                Spacer()
            }
            HStack {
                Spacer()
                Text("4th")
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
            HStack {
                Text("\(format(stats.fourthQuintileLower)) to \(format(stats.topQuintileLower))")
                    .bold()
                Spacer()
            }
            HStack {
                Spacer()
                Text("5th")
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
            HStack {
                Text("\(format(stats.topQuintileLower)) to \(format(stats.max))")
                    .bold()
                Spacer()
            }
        }.font(Font.title2)
    }
}

struct VStatView : View {
    
    let label: String
    let value: String
    
    var body: some View {
        VStack {
            Text(label)
            Text(value)
                .font(Font.title2)
                .minimumScaleFactor(0.6)
        }
    }
}

struct GrowthStatsView_Previews: PreviewProvider {
    static var previews: some View {
        GrowthStatsView(
            heading: "10_14 - Selected areas",
            stats: DistributionStats(values: [-2,-2,0,3,6,7,8,76,200], bucketBoundaries: [0, 5, 10])!,
            format: growthFormat)
    }
}
