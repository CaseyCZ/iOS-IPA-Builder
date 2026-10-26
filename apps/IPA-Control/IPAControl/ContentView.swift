import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            MyAppsView()
                .tabItem { Label("Moje aplikace", systemImage: "square.stack.3d.up") }
            SourcesView()
                .tabItem { Label("Zdroje", systemImage: "square.grid.2x2") }
            SettingsView()
                .tabItem { Label("Nastavení", systemImage: "gearshape") }
        }
        .tint(.indigo)
    }
}

private struct MyAppsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ContentUnavailableView(
                        "Zatím žádné spravované aplikace",
                        systemImage: "app.badge.checkmark",
                        description: Text("Seznam bude dostupný po propojení podpisové a instalační služby. iOS běžným aplikacím nedovoluje zjistit úplný seznam nainstalovaných aplikací.")
                    )
                }
                Section("Bezplatný Apple účet") {
                    LabeledContent("Současně aktivní aplikace", value: "max. 3")
                    LabeledContent("Registrovaná App ID", value: "max. 10 / 7 dní")
                    LabeledContent("Platnost profilu", value: "7 dní")
                }
                Section {
                    Label("Obnovení podpisu bude dostupné po připojení serveru a ověření párování iPhonu.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("IPA Control")
        }
    }
}

private struct SourcesView: View {
    @EnvironmentObject private var model: IPAControlModel
    @State private var showingAddSource = false
    @State private var sourceURL = ""
    @State private var errorMessage: String?
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                Section("Moje zdroje") {
                    if model.sources.isEmpty {
                        Text("Zatím nemáš žádný zdroj. Přidej adresu JSON ve formátu AltStore Classic.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.sources) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name).font(.headline)
                            Text(source.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .onDelete { offsets in
                        let removed = offsets.map { model.sources[$0] }
                        for source in removed { model.removeSource(source) }
                    }
                }
                Section("Katalog") {
                    if model.catalog.isEmpty {
                        Text("Přidané aplikace se zobrazí po načtení JSON zdrojů.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.catalog) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.app.name).font(.headline)
                            HStack {
                                Text(item.sourceName)
                                if let version = item.app.latestVersion {
                                    Text("· v\(version.version)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text(item.app.bundleIdentifier)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .navigationTitle("Zdroje")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddSource = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if model.isLoading { ProgressView() }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(model.isLoading)
                }
            }
            .task { await refresh() }
            .alert("Chyba", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
            .sheet(isPresented: $showingAddSource) {
                NavigationStack {
                    Form {
                        Section("Adresa JSON") {
                            TextField("https://example.com/source.json", text: $sourceURL)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                        }
                        Section {
                            Text("Podporujeme HTTPS zdroje kompatibilní s AltStore Classic.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Přidat zdroj")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Zrušit") { showingAddSource = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(adding ? "Načítám…" : "Přidat") {
                                adding = true
                                Task {
                                    do {
                                        try await model.addSource(sourceURL)
                                        sourceURL = ""
                                        showingAddSource = false
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                    adding = false
                                }
                            }
                            .disabled(adding || sourceURL.isEmpty)
                        }
                    }
                }
            }
        }
    }

    private func refresh() async {
        do { try await model.refreshSources() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: IPAControlModel
    @State private var errorMessage: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Náš server") {
                    TextField("https://server.example.com", text: $model.serverURLString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    LabeledContent("Stav", value: model.serverStatus)
                    Button(testing ? "Ověřuji…" : "Ověřit připojení") {
                        testing = true
                        Task {
                            do { try await model.checkServer() }
                            catch { errorMessage = error.localizedDescription }
                            testing = false
                        }
                    }
                    .disabled(testing)
                }
                Section("Budoucí funkce") {
                    Label("Podepisování IPA", systemImage: "signature")
                    Label("Obnovení profilů", systemImage: "arrow.clockwise.circle")
                    Label("Párování iPhonu", systemImage: "iphone.gen3")
                }
                Section("O aplikaci") {
                    LabeledContent("Verze", value: "0.1.0")
                    Text("První testovací klient. V této verzi neprobíhá instalace ani podepisování aplikací.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nastavení")
            .alert("Chyba", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }
}
