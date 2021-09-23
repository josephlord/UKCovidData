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

    @StateObject
    var datesUseCase = DateUseCase(
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
    @State private var showAreas = true
    
    var currentAreaName: String { datesUseCase.viewModel.areas.first?.name ?? ""}
    
    var viewModel: CovidDataGroupViewModel {
        viewModelWhileLoading ?? datesUseCase.viewModel
    }
    
    
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
            }
            
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showAreas = true } ) {
                        Text("Areas")
                    }
                }
                ToolbarItem {
                    Button(action: update) {
                        Label("Update", systemImage: "square.and.arrow.down.on.square")
                    }.disabled(isLoading)
                }
            }
            .navigationTitle(Text(currentAreaName))
        }.popover(isPresented: $showAreas) {
            TextField("Area", text: $searchUseCase.searchString, prompt: Text("Search"))
                
            List() {
                ForEach(searchUseCase.areas) { area in
                    Button(action: {
                        datesUseCase.areas = [area]
                        showAreas = false
                    }) {
                        Text(area.name)
                    }
                }
            }//.searchable(text: $searchUseCase.searchString)
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
