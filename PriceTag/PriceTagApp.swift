//
//  PriceTagApp.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-13.
//

import SwiftUI

@main
struct PriceTagApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { phase in
            // Saves are debounced while editing; leaving the app forces the last one out.
            if phase != .active {
                store.flush()
                LogoLibrary.shared.flush()
            }
        }
    }
}
