//
//  ContentView.swift
//  UKCovidData
//
//  Created by Joseph Lord on 15/09/2021.
//

import SwiftUI
import Combine

struct AreaListView: View {

    @StateObject
    var searchUseCase: SearchUseCase = {
        let useCase = SearchUseCase(container: PersistenceController.shared.container)
        return useCase
    }()
    @StateObject var ageOptions = AgeOptions()
    
    @State private var isLoading: Bool = false
    @State private var viewModelWhileLoading: CovidDataGroupViewModel?
    @State private var showAreas = false
    @State private var showAges = false
    @State private var navigation: String?
    @State var sortOrder = SortOrder(column: .rate)
    
    @State var cancellable: Cancellable?
    
    struct SortOrder {
        enum SortColumn {
            case name, rate, growth
        }
        var column: SortColumn
        var reverse: Bool = false
    }
    
    var areas: [Area] {
        switch sortOrder.column {
        case .name:
            return searchUseCase.areas.sorted(reverse: sortOrder.reverse) { lhs, rhs in lhs.name < rhs.name }
        case .rate:
            return searchUseCase.areas.sorted(reverse: sortOrder.reverse) { lhs, rhs in
                guard let lRate = lhs.lastWeekCaseRate,
                      let rRate = rhs.lastWeekCaseRate
                else { return lhs.name < rhs.name }
                return lRate > rRate
            }
        case .growth:
            return searchUseCase.areas.sorted(reverse: sortOrder.reverse) { lhs, rhs in
                guard let lGrowth = lhs.lastWeekCaseGrowth,
                      let rGrowth = rhs.lastWeekCaseGrowth
                else { return lhs.name < rhs.name }
                return lGrowth > rGrowth
            }
        }
    }
    
    func tappedSort(column: SortOrder.SortColumn) {
        withAnimation(.easeInOut(duration: 3)) {
            if column == sortOrder.column {
                sortOrder.reverse.toggle()
            } else {
                sortOrder.column = column
                if column == .name {
                    sortOrder.reverse = false
                }
            }
        }
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

    var body: some View {
        NavigationView {
            VStack {
                Text(ageOptions.selectedAgesString)
                if showAges {
                    AgeOptionsView(ageOptions: ageOptions)
                }
                TextField("Area", text: $searchUseCase.searchString, prompt: Text("Search"))
                    .padding()
                    .border(Color.accentColor)
                    .padding()
                    
                HStack {
                    // Do properly with alignment guides
                    Button(action: { tappedSort(column: .name) }) {
                        Text("Area")
                    }
                    Spacer()
                    Button(action: { tappedSort(column: .rate) }){
                        Text("Last week cases / 100,000")
                    }
                        .frame(width: 90)
                    Button(action: { tappedSort(column: .growth) }) {
                        Text("%age growth in last week")
                    }
                        .frame(width: 80)
                }
                .padding(EdgeInsets(top: 0, leading: 8, bottom: 2, trailing: 4))
                .font(Font.headline)
                List() {
                    ForEach(areas) { area in
                        NavigationLink(destination: AreaDetailsView(area: area), tag: area.name, selection: $navigation) {
                            HStack {
                                Text(area.name)
                                Spacer()
                                Text(area.lastWeekCaseRate.flatMap(rateFormatter.string) ?? "-")
//                                Color.clear.fram    e(width: 12)
                                HStack {
                                    Spacer()
                                    Text((area.lastWeekCaseGrowth.flatMap { rateFormatter.string(for: $0 * 100) } ?? "-") + "%")
                                }.frame(width: 58)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .navigationBarTitle(searchUseCase.lastDate ?? "")
            }
            .toolbar {
                ToolbarItem {
                    Button(action: { withAnimation { showAges.toggle() } } ) {
                        Text("Ages")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: update) {
                        Label("Update", systemImage: "square.and.arrow.down.on.square")
                    }.disabled(isLoading)
                }
            }
            .onAppear {
                searchUseCase.ages = ageOptions.selected
                
                cancellable = ageOptions.$options.sink { (values: [AgeOption]) in
                    if navigation == nil {
                        searchUseCase.ages = values.filter { $0.isEnabled }.map { $0.age }
                    }
                }
            }
        }
        .environment(\.ageOptions, ageOptions)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        AreaListView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
