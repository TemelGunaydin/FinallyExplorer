import AppKit
import Observation

@MainActor @Observable
final class OfflineCatalogModel: Identifiable {
    let id = UUID()
    var selectedID: UUID? { didSet { if oldValue != selectedID, isWorking == false { loadSelected() } } }
    var query = "" { didSet { search() } }
    var fileExtension = "" { didSet { search() } }
    var minimumBytes: Int64 = 0 { didSet { search() } }
    var modifiedWithinDays = 0 { didSet { search() } }
    var includesHidden = false
    var removal: OfflineCatalogSummary?
    private(set) var catalogs: [OfflineCatalogSummary] = []
    private(set) var connectedVolumes: [OfflineCatalogVolume] = []
    private(set) var source: OfflineCatalogSource?
    private(set) var rows: [OfflineCatalogEntry] = []
    private(set) var totalMatches = 0
    private(set) var isWorking = false
    private(set) var isCancelling = false
    private(set) var isSearching = false
    private(set) var progress: FolderWorkProgress?
    private(set) var errorMessage: String?
    private(set) var notice: String?
    private(set) var didAttemptLoad = false
    @ObservationIgnored private let store: any OfflineCatalogStoring
    @ObservationIgnored private let volumes: any OfflineVolumeAccessing
    @ObservationIgnored private let scanner: any OfflineCatalogScanning
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var entries: [OfflineCatalogEntry] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var folderPanel: NSOpenPanel?
    @ObservationIgnored private var searchGeneration = 0
    @ObservationIgnored private var connectionGeneration = 0

    init(store: any OfflineCatalogStoring = OfflineCatalogStore.shared,
         volumes: any OfflineVolumeAccessing = LocalOfflineVolumeAccess(), scanner: (any OfflineCatalogScanning)? = nil,
         now: @escaping @Sendable () -> Date = { .now }) {
        self.store = store
        self.volumes = volumes
        self.scanner = scanner ?? OfflineCatalogScanner(volumes: volumes)
        self.now = now
    }

    deinit { task?.cancel(); searchTask?.cancel(); connectionTask?.cancel() }
    var selected: OfflineCatalogSummary? { catalogs.first { $0.id == selectedID } }
    var isConnected: Bool { selected.map { summary in connectedVolumes.count { $0.id == summary.volumeID } == 1 } ?? false }
    var connectionDescription: String {
        guard let selected else { return "No catalog selected" }
        let count = connectedVolumes.count { $0.id == selected.volumeID }
        return count == 1 ? "Disk connected" : count == 0 ? "Disk offline — saved metadata" : "Duplicate disk identifiers — reconnect one disk"
    }

    @discardableResult func load() -> Task<Void, Never>? {
        guard begin("Loading saved catalogs…") else { return nil }
        didAttemptLoad = true
        clearEntries()
        task = Task { [weak self, store, volumes] in
            do {
                let catalogs = try await store.list()
                let connected = try await volumes.volumes()
                try Task.checkCancellation()
                guard let self else { return }
                self.catalogs = catalogs
                connectedVolumes = connected
                selectedID = catalogs.first(where: { $0.id == self.selectedID })?.id ?? catalogs.first?.id
                if let selectedID {
                    let snapshot = try await store.load(selectedID)
                    try Task.checkCancellation()
                    entries = snapshot.entries
                } else { entries = [] }
                finish(); search()
            } catch { self?.fail(error) }
        }
        return task
    }

    @discardableResult func prepare(_ url: URL) -> Task<Void, Never>? {
        guard begin("Checking selected folder…") else { return nil }
        source = nil
        task = Task { [weak self, volumes] in
            do {
                let source = try await volumes.source(for: url)
                try Task.checkCancellation()
                self?.source = source
                self?.finish()
            } catch { self?.fail(error) }
        }
        return task
    }

    func chooseFolder() {
        guard isWorking == false else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose a Folder to Catalog"
        panel.message = "Choose a folder on an external disk. Scan & Save will store names and metadata on this Mac, not file contents."
        panel.directoryURL = connectedVolumes.first?.rootURL
        guard begin("Choosing a folder…") else { return }
        folderPanel = panel
        task = Task { [weak self] in
            let response = await panel.begin()
            guard let self else { return }
            folderPanel = nil
            finish()
            guard Task.isCancelled == false, response == .OK, let url = panel.url else { return }
            prepare(url)
        }
    }

    @discardableResult func scanAndSave() -> Task<Void, Never>? {
        guard let source else { return nil }
        return save(source: source, refreshing: nil, includesHidden: includesHidden)
    }

    @discardableResult func refreshSelected() -> Task<Void, Never>? {
        guard let selected else { return nil }
        return save(source: nil, refreshing: selected, includesHidden: selected.includesHidden)
    }

    @discardableResult func confirmRemoval(_ approved: OfflineCatalogSummary) -> Task<Void, Never>? {
        guard removal?.id == approved.id, begin("Removing saved catalog…") else { return nil }
        removal = nil
        task = Task { [weak self, store] in
            do {
                try await store.remove(approved.id)
                guard let self else { return }
                didRemove(approved.id)
                notice = "Saved catalog removed. Original files were not changed."
                finish()
            } catch {
                // The manifest is already committed when only payload cleanup fails.
                if error as? OfflineCatalogError == .cleanupFailed { self?.didRemove(approved.id) }
                self?.fail(error)
            }
        }
        return task
    }

    @discardableResult func reveal(_ entry: OfflineCatalogEntry, onReveal: @escaping @MainActor @Sendable (URL, Bool) -> Void) -> Task<Void, Never>? {
        guard let selected, entries.contains(where: { $0 == entry }), begin("Checking saved location…") else { return nil }
        task = Task { [weak self, volumes] in
            do {
                let url = try await volumes.reveal(entry, in: selected)
                try Task.checkCancellation()
                guard let self else { return }
                finish()
                onReveal(url, entry.isDirectory)
            } catch { self?.fail(error) }
        }
        return task
    }

    @discardableResult func refreshConnections() -> Task<Void, Never> {
        connectionTask?.cancel()
        connectionGeneration += 1
        let generation = connectionGeneration
        let task = Task { [weak self, volumes] in
            do {
                let connected = try await volumes.volumes()
                guard Task.isCancelled == false, let self, connectionGeneration == generation else { return }
                connectedVolumes = connected
            } catch {
                guard let self, connectionGeneration == generation, Task.isCancelled == false else { return }
                connectedVolumes = []
            }
        }
        connectionTask = task
        return task
    }

    func cancel() {
        if isWorking { isCancelling = true; task?.cancel() }
        folderPanel?.cancel(nil)
        searchGeneration += 1; searchTask?.cancel(); isSearching = false
        connectionGeneration += 1; connectionTask?.cancel()
    }

    func waitForWork() async { let pending = task; await pending?.value }
    func waitForSearch() async { let pending = searchTask; await pending?.value }

    private func save(source: OfflineCatalogSource?, refreshing: OfflineCatalogSummary?, includesHidden: Bool) -> Task<Void, Never>? {
        guard begin("Preparing catalog scan…") else { return nil }
        task = Task { [weak self, store, scanner, volumes] in
            do {
                let selected: OfflineCatalogSource
                if let source { selected = source }
                else if let refreshing { selected = try await volumes.source(for: refreshing) }
                else { throw OfflineCatalogError.invalidSource }
                let snapshot = try await scanner.scan(selected, includesHidden: includesHidden) { [weak self] value in
                    await self?.updateProgress(value)
                }
                try Task.checkCancellation()
                let saved = try await store.save(snapshot)
                guard let self else { return }
                // A successful atomic save remains successful if cancellation arrives afterward.
                catalogs.removeAll { $0.id == saved.id }; catalogs.append(saved)
                catalogs.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                clearEntries()
                selectedID = saved.id; entries = snapshot.entries
                self.source = nil
                notice = "Catalog saved · \(saved.entryCount) entries"
                finish(); search()
            } catch { self?.fail(error) }
        }
        return task
    }

    private func loadSelected() {
        guard isWorking == false else { return }
        clearEntries()
        guard let selectedID, begin("Loading catalog entries…") else { return }
        task = Task { [weak self, store] in
            do {
                let snapshot = try await store.load(selectedID)
                try Task.checkCancellation()
                guard let self else { return }
                entries = snapshot.entries
                finish(); search()
            } catch { self?.fail(error) }
        }
    }

    private func clearEntries() {
        searchGeneration += 1
        searchTask?.cancel()
        entries = []; rows = []; totalMatches = 0; isSearching = false
    }

    private func didRemove(_ id: UUID) {
        catalogs.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil; clearEntries() }
    }

    private func search() {
        searchTask?.cancel(); searchGeneration += 1
        let generation = searchGeneration, entries = entries
        let cutoff = modifiedWithinDays > 0 ? Calendar.current.date(byAdding: .day, value: -modifiedWithinDays, to: now()) : nil
        let filter = OfflineCatalogQuery(text: query, fileExtension: fileExtension, minimumBytes: minimumBytes, modifiedSince: cutoff)
        isSearching = true
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
                let result = try await OfflineCatalogSearch.search(entries, query: filter)
                guard let self, generation == searchGeneration, Task.isCancelled == false else { return }
                rows = result.entries; totalMatches = result.totalMatches; isSearching = false
            } catch {
                guard let self, generation == searchGeneration else { return }
                isSearching = false
            }
        }
    }

    private func begin(_ phase: String) -> Bool {
        guard isWorking == false else { return false }
        isWorking = true; isCancelling = false; errorMessage = nil; notice = nil
        progress = FolderWorkProgress(phase: phase, relativePath: "")
        return true
    }
    private func finish() { isWorking = false; isCancelling = false; progress = nil; task = nil }
    private func updateProgress(_ value: FolderWorkProgress) { if isWorking { progress = value } }
    private func fail(_ error: any Error) {
        if error is CancellationError { notice = "Stopped. Previously saved catalogs are unchanged." }
        else { errorMessage = OfflineCatalogError.message(for: error) }
        finish()
    }
}
