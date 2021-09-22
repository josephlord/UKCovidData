//
//  UKCovidDataApp.swift
//  UKCovidData
//
//  Created by Joseph Lord on 15/09/2021.
//

import SwiftUI

@main
struct UKCovidDataApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .task {
                    do {
                        try await updatePopulations()
                    } catch {
                        fatalError(error.localizedDescription)
                    }
                }
        }
    }
}
