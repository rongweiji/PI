//
//  PIApp.swift
//  PI
//
//  Created by Rongwei Ji on 11/5/25.
//

import SwiftUI
import SwiftData

@main
struct PIApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PhotoItem.self,
            VideoItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
