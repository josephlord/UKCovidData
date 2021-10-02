//
//  ProgressView.swift
//  UKCovidData
//
//  Created by Joseph Lord on 02/10/2021.
//

import SwiftUI

struct ProgressView: View {
    let progress: ProgressPublisher.Progress
    
    private static let updateValueFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.maximumFractionDigits = 0
        return f
    }()
    
    private func format(_ d: Double) -> String {
        Self.updateValueFormatter.string(from: d as NSNumber) ?? "-"
    }
    
    private var message: String {
        "\(format(progress.numerator)) of \(format(progress.denominator))\(progress.unit.map { " \($0)" } ?? "")"
    }
    
    var body: some View {
        HStack {
            GeometryReader { proxy in
                Color.gray
                    .overlay(alignment: .leading) {
                        Color.accentColor
                            .frame(width: proxy.size.width * progress.numerator / progress.denominator)
                    }
                    
            }
            .frame(height: 20)
            .cornerRadius(10)
            
            Text(message)
        }
    }
}

struct ProgressView_Previews: PreviewProvider {
    static var previews: some View {
        ProgressView(progress: .init(numerator: 300, denominator: 315, unit: nil))
    }
}
