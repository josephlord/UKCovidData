//
//  ContentView.swift
//  UKCovidData
//
//  Created by Joseph Lord on 15/09/2021.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

//    @FetchRequest(
//        sortDescriptors: [NSSortDescriptor(keyPath: \AreaAgeDateCases.date, ascending: false)],
//        predicate: NSPredicate(format: "areaName = %@ AND age IN %@", "Surrey Heath", ["15_19", "10_14"]),
//        animation: .default)
//    private var items: FetchedResults<AreaAgeDateCases>
    @StateObject
    var datesUseCase = DateUseCase(
//            areas: [Area(name: "Surrey Heath", id: "E07000214", populationsForAges: ["10_14" : 5000, "15_19": 5000])],
//            ages: [
//                "10_14",
//    //            "15_19",
//            ],
            context: {
                let context = PersistenceController.shared.container.newBackgroundContext()
                context.automaticallyMergesChangesFromParent = true
                return context
            }())
    
    @StateObject
    var searchUseCase: SearchUseCase = SearchUseCase(container: PersistenceController.shared.container)
    
    @State private var isLoading: Bool = false
    
    private let rateFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.maximumFractionDigits = 1
        return f
    }()
    
    @State private var viewModelWhileLoading: CovidDataGroupViewModel?
    
    var currentAreaName: String { datesUseCase.viewModel.areas.first?.name ?? ""}
    
    var viewModel: CovidDataGroupViewModel {
        viewModelWhileLoading ?? datesUseCase.viewModel
    }
    
    @State var searchText: String = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: .init(.flexible()), count: 4)) {
                    ForEach(viewModel.cases.reversed()) { item in
                        Text(item.date)
                        Text("\(item.cases)")
                        Text("\(item.lastWeekCases)")
                        Text(item.lastWeekCaseRate.flatMap(rateFormatter.string) ?? "-")
                    }
                }
    //            List {
    //                ForEach(datesUseCase.viewModel.cases) { item in
    //                    NavigationLink {
    //                        Text("Item at \(item.date)")
    //                    } label: {
    //                        Text(item.date)
    //                        Spacer()
    //                        Text("Cases: \(item.cases)")
    //                    }
    //                }
    //                .onDelete(perform: deleteItems)
    //            }
            }
            .searchable(text: $searchText) {
                if searchText == "" || searchText == currentAreaName {
                    EmptyView()
                } else {
                    
                }
            }
            .toolbar {
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    EditButton()
//                }
                ToolbarItem {
                    Button(action: update) {
                        Label("Update", systemImage: "square.and.arrow.down.on.square")
                    }.disabled(isLoading)
                }
            }
            .navigationTitle(Text(currentAreaName))
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

//    private func deleteItems(offsets: IndexSet) {
//        withAnimation {
//            offsets.map { items[$0] }.forEach(viewContext.delete)
//
//            do {
//                try viewContext.save()
//            } catch {
//                // Replace this implementation with code to handle the error appropriately.
//                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
//                let nsError = error as NSError
//                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
//            }
//        }
//    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
