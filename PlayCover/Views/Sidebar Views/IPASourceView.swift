//
//  IPASourceView.swift
//  PlayCover
//
//  Created by Amir Mohammadi on 1/21/1402 AP.
//

import SwiftUI

struct IPASourceView: View {

    @ObservedObject var storeVM: StoreVM
    @EnvironmentObject var downloadVM: DownloadVM

    @Binding var selectedBackgroundColor: Color
    @Binding var selectedTextColor: Color
    var sourceName: String
    var sourceApps: [SourceAppsData]
    var onRemoveSource: () -> Void

    @State private var isList = UserDefaults.standard.bool(forKey: "IPALibraryView")
    @State private var sortAlphabetical = UserDefaults.standard.bool(forKey: "IPASourceAlphabetically")
    @State private var selected: SourceAppsData?
    @State private var searchString = ""

    @State private var addSourcePresented = false
    @State private var showAppInfo = false

    @State private var gridLayout = [GridItem(.adaptive(minimum: 130, maximum: .infinity))]

    private var displayedApps: [SourceAppsData] {
        let query = searchString.lowercased()
        let matchingApps = query.isEmpty ? sourceApps : sourceApps.filter { $0.name.lowercased().contains(query) }
        return sortAlphabetical ? matchingApps.sorted { $0.name.lowercased() < $1.name.lowercased() } : matchingApps
    }

    var body: some View {
        ScrollView {
            if !isList {
                LazyVGrid(columns: gridLayout, alignment: .center) {
                    ForEach(displayedApps, id: \.bundleID) { app in
                        StoreAppView(selectedBackgroundColor: $selectedBackgroundColor,
                                     selectedTextColor: $selectedTextColor,
                                     selected: $selected,
                                     app: app,
                                     isList: isList)
                        .id(app)
                    }
                }
                .padding()
                Spacer()
            } else {
                LazyVStack {
                    ForEach(displayedApps, id: \.bundleID) { app in
                        StoreAppView(selectedBackgroundColor: $selectedBackgroundColor,
                                     selectedTextColor: $selectedTextColor,
                                     selected: $selected,
                                     app: app,
                                     isList: isList)
                        .id(app)
                        .environmentObject(DownloadVM.shared)
                        .environmentObject(InstallVM.shared)
                    }
                    Spacer()
                }
                .padding()
            }
        }
        .navigationTitle(sourceName)
        .onTapGesture {
            selected = nil
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addSourcePresented.toggle()
                } label: {
                    Image(systemName: "plus.circle")
                        .help("playapp.addSource")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    storeVM.resolveSources()
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                        .help("playapp.refreshSources")
                }
                .disabled(storeVM.sourcesList.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive, action: onRemoveSource) {
                    Image(systemName: "trash")
                }
                .help("preferences.button.deleteSource")
                .accessibilityLabel(Text("preferences.button.deleteSource"))
            }
            ToolbarItem(placement: .primaryAction) {
                Spacer()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAppInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .disabled(selected == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Spacer()
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle("A", isOn: $sortAlphabetical)
                    .help("ipaLibrary.AlphabeticalSort")
            }
            ToolbarItem(placement: .primaryAction) {
                Picker("", selection: $isList) {
                    Image(systemName: "square.grid.2x2")
                        .tag(false)
                    Image(systemName: "list.bullet")
                        .tag(true)
                }
                .pickerStyle(.segmented)
            }
        }
        .searchable(text: $searchString, placement: .toolbar)
        .sheet(isPresented: $addSourcePresented) {
            AddSourceView(addSourceSheet: $addSourcePresented)
                .environmentObject(storeVM)
        }
        .sheet(isPresented: $showAppInfo) {
            if let selected = selected {
                StoreInfoAppView(viewModel: StoreAppVM(data: selected))
                    .environmentObject(downloadVM)
            }
        }
        .onChange(of: isList) { value in
            UserDefaults.standard.set(value, forKey: "IPALibraryView")
        }
        .onChange(of: sortAlphabetical) { value in
            UserDefaults.standard.set(value, forKey: "IPASourceAlphabetically")
        }
        .onChange(of: sourceApps) { apps in
            if let selected, !apps.contains(selected) {
                self.selected = nil
                showAppInfo = false
            }
        }
    }
}
