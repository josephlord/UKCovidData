//
//  ContentView.swift
//  UKCovidData
//
//  Created by Joseph Lord on 15/09/2021.
//

import SwiftUI
import CoreData

let rateFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.maximumFractionDigits = 0
    f.minimumFractionDigits = 0
    return f
}()

struct AgeOptionsKey : EnvironmentKey {
    static var defaultValue: AgeOptions = AgeOptions()
}

extension EnvironmentValues {
    var ageOptions: AgeOptions {
        get { self[AgeOptionsKey.self] }
        set { self[AgeOptionsKey.self] = newValue }
    }
}

struct ContentView: View {
    //@Environment(\.managedObjectContext) private var viewContext

    @StateObject
    var searchUseCase: SearchUseCase = {
        let useCase = SearchUseCase(container: PersistenceController.shared.container)
        return useCase
    }()
    
    @State private var isLoading: Bool = false
    

    
    @State private var viewModelWhileLoading: CovidDataGroupViewModel?
    @State private var showAreas = false
    @State private var showAges = false
    
    @StateObject var ageOptions = AgeOptions()

    var body: some View {
        NavigationView {
            VStack {
                TextField("Area", text: $searchUseCase.searchString, prompt: Text("Search"))
                    .padding()
                    .border(Color.accentColor)
                    .padding()
                    
                List() {
                    ForEach(searchUseCase.areas) { area in
                        NavigationLink(destination: AreaDetailsView(area: area)) {
                            HStack {
                                Text(area.name)
                                Spacer()
                                Text(area.lastWeekCaseRate.flatMap(rateFormatter.string) ?? "-")
                                Color.clear.frame(width: 12)
                                Text((area.lastWeekCaseGrowth.flatMap { rateFormatter.string(for: $0 * 100) } ?? "-") + "%")
                            }
                        }
                    }
                    
                }
                .listStyle(.plain)
                .navigationBarTitle(searchUseCase.lastDate ?? "")
            }
            .toolbar {
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
            .onAppear {
                searchUseCase.ages = ageOptions.selected
            }
            .sheet(
                isPresented: $showAges,
                onDismiss: {
                    searchUseCase.ages = ageOptions.selected
                }) {
                    VStack {
                        HStack {
                            Button(action: {
                                ageOptions.setAll(enabled: true)
                            }, label: { Text("Enable All") })
                                .padding()
                                .border(Color.accentColor)
                            Spacer()
                            Button(action: {
                                ageOptions.setAll(enabled: false)
                            }, label: { Text("Disable All") })
                                .padding()
                                .border(Color.accentColor)
                        }.padding()
                        List() {
                            
                            ForEach($ageOptions.options.indices, id: \.self) { index in
                                Toggle(
                                    isOn: $ageOptions.options[index].isEnabled,
                                    label: {
                                        Text(ageOptions.options[index].age)
                                    }
                                )
                            }
                        }
                    }
            }
        
        }
        .environment(\.ageOptions, ageOptions)
    }
    
    private func update() {
        isLoading = true
        Task {
            do {
                try await updateCases()
            } catch {
                print(error)
            }
            isLoading = false
            searchUseCase.searchString = searchUseCase.searchString
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
    
    fileprivate static let initialAgeSelection = "10_14"
    
    static private let ages = ["00_04", "05_09", "10_14", "15_19", "20_24", "25_29", "30_34", "35_39", "40_44",
                      "45_49", "50_54", "55_59", "60_64", "65_69", "70_74", "75_79", "80_84", "85_89", "90+"]
    static var ageOptions = ages.map { AgeOption(age: $0, isEnabled: $0 == initialAgeSelection) }
}

class AgeOptions : ObservableObject {
    @Published var options = AgeOption.ageOptions
    
    func setAll(enabled: Bool) {
        var tmp = options
        tmp.indices.forEach {
            tmp[$0].isEnabled = enabled
        }
        options = tmp
    }
    
    var selected: [String] {
        options.filter { $0.isEnabled }.map { $0.age }
    }
    
    var selectedAgesString: String {
        selected.joined(separator: ", ")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
