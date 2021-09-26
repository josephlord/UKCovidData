//
//  ContentView.swift
//  UKCovidData
//
//  Created by Joseph Lord on 15/09/2021.
//

import SwiftUI
import CoreData

struct ContentView: View {
    //@Environment(\.managedObjectContext) private var viewContext

    @StateObject
    var datesUseCase = DateUseCase(
            context: {
                let context = PersistenceController.shared.container.viewContext
                context.automaticallyMergesChangesFromParent = true
                return context
            }())
    
    @StateObject
    var searchUseCase: SearchUseCase = SearchUseCase(container: PersistenceController.shared.container)
    
    @State private var isLoading: Bool = false
    
    private let rateFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 1
        return f
    }()
    
    @State private var viewModelWhileLoading: CovidDataGroupViewModel?
    @State private var showAreas = true
    @State private var showAges = false
    
    @State private var currentAreaName: String = ""
    
    var viewModel: CovidDataGroupViewModel {
        viewModelWhileLoading ?? datesUseCase.viewModel
    }
    
//    @State private var ages: [String]
    
    var selectedAgesString: String {
        datesUseCase.ages.joined(separator: ", ")
    }
    
    @StateObject var ageOptions = AgeOptions()
    
    var body: some View {
        NavigationView {
            VStack {
                Text(selectedAgesString)
                ScrollView {
                    LazyVGrid(
                        columns: [.init(.flexible()), .init(.flexible()), .init(.flexible()), .init(.flexible())]) {
                            Text("Date").font(.headline)
                            Text("Day").font(.headline)
                            Text("7 Day").font(.headline)
                            Text("7 Day / 100,000").font(.headline)
                        ForEach(viewModel.cases.reversed()) { item in
                            Text(item.date)
                            Text("\(item.cases)")
                            Text("\(item.lastWeekCases)")
                            HStack {
                                Spacer()
                                Text(item.lastWeekCaseRate.flatMap(rateFormatter.string) ?? "-")
                            }
                        }
                    }
                    .navigationTitle(currentAreaName)
                }
            }
            
            .popover(isPresented: $showAreas) {
                TextField("Area", text: $searchUseCase.searchString, prompt: Text("Search"))
                    .padding()
                    .border(Color.blue)
                    .padding()
                    
                List() {
                    ForEach(searchUseCase.areas) { area in
                        Button(action: {
                            datesUseCase.areas = [area]
                            showAreas = false
                            currentAreaName = area.name
                        }) {
                            Text(area.name)
                        }
                    }
                }
            }
            .sheet(
                isPresented: $showAges,
                onDismiss: { datesUseCase.ages = ageOptions.options.filter { $0.isEnabled }.map { $0.age } }) {
                List() {
                    ForEach($ageOptions.options.indices, id: \.self) { index in
                        Toggle(isOn: $ageOptions.options[index].isEnabled, label: { Text(ageOptions.options[index].age) })
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showAreas = true } ) {
                        Text("Areas")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showAges = true } ) {
                        Text("Ages")
                    }
                }
                ToolbarItem {
                    Button(action: update) {
                        Label("Update", systemImage: "square.and.arrow.down.on.square")
                    }.disabled(isLoading)
                }
            }
    
        }
        .onAppear {
            if datesUseCase.ages.isEmpty {
                datesUseCase.ages = ageOptions.options.filter { $0.isEnabled }.map { $0.id }
            }
        }
    }
    
    private func update() {
        isLoading = true
        viewModelWhileLoading = datesUseCase.viewModel
        Task {
            do {
                try await updateCases()
            } catch {
                print(error)
            }
            isLoading = false
            viewModelWhileLoading = nil
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

struct AgeOption : Identifiable, Equatable {
    let age: String
    var isEnabled: Bool
    var id: String { age }
    
    static private let ages = ["00_04", "05_09", "10_14", "15_19", "20_24", "25_29", "30_34", "35_39", "40_44",
                      "45_49", "50_54", "55_59", "60_64", "65_69", "70_74", "75_79", "80_84", "85_89", "90+"]
    static var ageOptions = ages.map { AgeOption(age: $0, isEnabled: $0 == "10_14") }
}

class AgeOptions : ObservableObject {
    @Published var options = AgeOption.ageOptions
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
