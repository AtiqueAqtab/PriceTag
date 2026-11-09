//
//  PriceTagApp.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-13.
//

import SwiftUI

@main
struct PriceTagApp: App {
    @StateObject private var store: Store
    @StateObject private var auth: AuthStore
    @StateObject private var sync: SyncEngine
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = Store()
        let auth = AuthStore()
        _store = StateObject(wrappedValue: store)
        _auth = StateObject(wrappedValue: auth)
        _sync = StateObject(wrappedValue: SyncEngine(store: store, auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(sync)
                .task { auth.start() }
                .onChange(of: auth.state) { state in sync.authChanged(state) }
                // Artwork is decoded in the background once the first screen is up.
                .task { LogoLibrary.shared.prewarm() }
        }
        .onChange(of: scenePhase) { phase in
            // Coming back to the app is a good moment to see whether an admin approved us.
            if phase == .active, auth.state != .signedOut {
                Task {
                    await auth.refresh()
                    await sync.sync()
                }
            }
            // Saves are debounced while editing; leaving the app forces the last one out.
            if phase != .active {
                store.flush()
                LogoLibrary.shared.flush()
            }
        }
    }
}
