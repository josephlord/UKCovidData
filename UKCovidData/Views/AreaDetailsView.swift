//
//  AreaDetailsView.swift
//  UKCovidData
//
//  Created by Joseph Lord on 28/09/2021.
//

import SwiftUI
import Combine

struct AreaDetailsView : View {
    
    let area: Area
    @ObservedObject var ageOptions: AgeOptions
    
    @State var showAges = false
    
    @StateObject
    var datesUseCase: DateUseCase = {
        let useCase = DateUseCase(
            context: {
                let context = PersistenceController.shared.container.viewContext
                context.automaticallyMergesChangesFromParent = true
                return context
            }())
        return useCase
    }()
    
    @State private var cancellable: Cancellable?
    
    internal init(area: Area, ageOptions: AgeOptions) {
        self.area = area
        self.ageOptions = ageOptions
    }
    
    var currentAreaName: String { area.name }
    
    var body: some View {
        VStack {
            Button(action: { withAnimation { showAges.toggle() } } ) {
                Text(ageOptions.selectedAgesString)
                Image(systemName: showAges ? "chevron.up" : "chevron.down")
            }
            if showAges {
                AgeOptionsView(ageOptions: ageOptions, showButtons: false)
            }
            Spacer(minLength: 8)
            ScrollView {
                
                HStack {
                    VStack {
                        Text("Total cases")
                        HStack {
                            VStatView(label: "Cases", value: "\(datesUseCase.casesSince?.casesMar2020.description ?? "-")")
                            Spacer()
                            VStatView(label: "%age of pop", value: (datesUseCase.casesSince?.proportionMar2020).flatMap(percentFormatter.string) ?? "-")
                        }
                    }
                    Spacer()
                    VStack {
                        Text("Cases Since June")
                        HStack {
                            VStatView(label: "Cases", value: "\(datesUseCase.casesSince?.casesJun2021.description ?? "-")")
                            Spacer()
                            VStatView(label: "%age of pop", value: (datesUseCase.casesSince?.proportionJun2021).flatMap(percentFormatter.string) ?? "-")
                        }
                    }
                }.padding([.leading, .trailing])
                LazyVGrid(
                    columns: [.init(.flexible()), .init(.flexible()), .init(.flexible()), .init(.flexible())]) {
                        Text("Date").font(.headline)
                        Text("Day").font(.headline)
                        Text("7 Day").font(.headline)
                        Text("7 Day / 100,000").font(.headline)
                        ForEach(datesUseCase.viewModel.cases.reversed()) { item in
                        Text(item.date)
                        Text("\(item.cases)")
                        Text("\(item.lastWeekCases)")
                        HStack {
                            Spacer()
                            Text(item.lastWeekCaseRate.flatMap(rateFormatter.string) ?? "-")
                                .padding(.trailing, 8)
                        }
                    }
                }
                .navigationTitle(currentAreaName)
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
        .onAppear {
            datesUseCase.areas = [area]
            cancellable = ageOptions.$options.sink { (values: [AgeOption]) in
                datesUseCase.ages = values.filter { $0.isEnabled }.map { $0.age }
            }
        }
    }
}


