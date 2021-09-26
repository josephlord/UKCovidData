//
//  Persistence.swift
//  UKCovidData
//
//  Created by Joseph Lord on 15/09/2021.
//

import CoreData

extension Notification.Name {
    static let persistenceControllerReset = Self.init(rawValue: "PersistenceControllerReset")
}

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for _ in 0..<10 {
            let newItem = AreaAgeDateCases(context: viewContext)
            newItem.age = "10_14"
            newItem.areaCode = "12345"
            newItem.areaName = "A borough"
            newItem.areaType = "ltla"
            newItem.date = "2021-10-04"
            newItem.cases = 43
        }
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer
    private(set) lazy var readingBackgroundContext: NSManagedObjectContext = {
        let context = container.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        return context
    }()
    
    func resetPersistentContexts() {
        container.viewContext.reset()
        var tmp = self
        tmp.readingBackgroundContext.reset()
        NotificationCenter.default.post(name: .persistenceControllerReset, object: nil)
    }

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "UKCovidData")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                Typical reasons for an error here include:
                * The parent directory does not exist, cannot be created, or disallows writing.
                * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                * The device is out of space.
                * The store could not be migrated to the current model version.
                Check the error message to determine what the actual problem was.
                */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
    }
}
