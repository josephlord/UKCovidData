//
//  AreaDetailsView.swift
//  UKCovidData
//
//  Created by Joseph Lord on 28/09/2021.
//

import SwiftUI

struct AreaDetailsView : View {
    
    let area: Area
    @Environment(\.ageOptions) var ageOptions: AgeOptions
    
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
    
    internal init(area: Area) {
        self.area = area
    }
    
    var currentAreaName: String { area.name }
    
    var body: some View {
        VStack {
            Text(ageOptions.selectedAgesString)
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
        .toolbar {
            ToolbarItem {
                Button(action: { showAges = true } ) {
                    Text("Ages")
                }
            }
        }
        .sheet(
            isPresented: $showAges,
            onDismiss: {
                datesUseCase.ages = ageOptions.selected
            }) { AgeOptionsView(ageOptions: ageOptions, showButtons: true) }
        .onAppear {
            datesUseCase.areas = [area]
            datesUseCase.ages = ageOptions.selected
        }
    }
}


