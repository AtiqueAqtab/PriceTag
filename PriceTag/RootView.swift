//
//  RootView.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-14.
//

import SwiftUI

enum Tab: String, CaseIterable {
    case pages, library, templates, logos

    var label: String {
        switch self {
        case .pages:     return "Pages"
        case .library:   return "Library"
        case .templates: return "Templates"
        case .logos:     return "Logos"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var tab: Tab = .pages

    var body: some View {
        ZStack {
            Color.ptBG.ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch tab {
                    case .pages:     PagesScreen()
                    case .library:   LibraryScreen()
                    case .templates: TemplatesScreen()
                    case .logos:     LogosScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                tabBar
            }
        }
        .preferredColorScheme(.dark)
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.ptHair).frame(height: 1)
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.rawValue) { item in
                    Button(action: { tab = item }) {
                        Text(item.label.uppercased())
                            .font(pt(10, .semibold))
                            .kerning(1.1)
                            .foregroundColor(tab == item ? Color.ptAccent : Color.ptDim)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)
        }
        .background(Color.ptBG)
    }
}

