import AppKit
import Observation

@MainActor @Observable
final class VisualSearchModel {
    private(set) var sourceURL: URL?
    var includesHidden = false { didSet { if includesHidden != oldValue { clearIndex() } } }
    var query = "" { didSet { if query != oldValue { search() } } }
    var mode: VisualSearchMode = .both { didSet { if mode != oldValue { search() } } }
    private(set) var snapshot: VisualSearchSnapshot?
    private(set) var matches: [VisualSearchMatch] = []
    private(set) var progress: FolderWorkProgress?
    private(set) var isWorking = false
    private(set) var isCancelling = false
    private(set) var errorMessage: String?
    @ObservationIgnored private let service: any VisualSearchScanning
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration = 0

    init(service: any VisualSearchScanning = VisualSearchService()) { self.service = service }
    deinit { task?.cancel(); searchTask?.cancel() }

    func setSource(_ url: URL) {
        guard isWorking == false, sourceURL != url else { return }
        clearIndex()
        sourceURL = url
    }

    func chooseFolder() {
        guard isWorking == false else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = "Images inside this folder are read only when you select Analyze Folder."
        panel.directoryURL = sourceURL
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url { self?.setSource(url) }
        }
    }

    @discardableResult func analyze() -> Task<Void, Never>? {
        guard isWorking == false, let sourceURL else { return nil }
        isWorking = true
        isCancelling = false
        errorMessage = nil
        progress = FolderWorkProgress(phase: "Reading folder…", relativePath: sourceURL.path)
        let hidden = includesHidden
        task = Task { [weak self, service] in
            do {
                let result = try await service.scan(rootURL: sourceURL, includesHidden: hidden) { [weak self] value in
                    await self?.receive(value)
                }
                try Task.checkCancellation()
                guard let self else { return }
                snapshot = result
                finish()
                search()
            } catch {
                guard let self else { return }
                if Task.isCancelled == false { errorMessage = VisualSearchError.message(for: error) }
                finish()
            }
        }
        return task
    }

    func cancel() {
        guard isWorking else { return }
        isCancelling = true
        task?.cancel()
        // Keep the operation busy until Vision unwinds; a second scan cannot overlap it.
    }

    func clearIndex() {
        cancel()
        searchGeneration += 1
        searchTask?.cancel()
        searchTask = nil
        snapshot = nil
        matches = []
        errorMessage = nil
        query = ""
    }

    @discardableResult func reveal(_ entry: VisualSearchSnapshot.Entry,
                                    onReveal: @escaping @MainActor (URL) -> Void) -> Task<Void, Never>? {
        guard isWorking == false, let snapshot else { return nil }
        isWorking = true
        errorMessage = nil
        task = Task { [weak self, service] in
            do {
                let url = try await service.validate(entry, in: snapshot)
                try Task.checkCancellation()
                guard let self else { return }
                finish()
                onReveal(url)
            } catch {
                guard let self else { return }
                if Task.isCancelled == false { errorMessage = "This result is no longer available. Analyze the folder again." }
                finish()
            }
        }
        return task
    }

    func waitForSearch() async { await searchTask?.value }

    private func receive(_ value: FolderWorkProgress) {
        guard isWorking, isCancelling == false else { return }
        progress = value
    }

    private func finish() { task = nil; progress = nil; isWorking = false; isCancelling = false }

    private func search() {
        searchTask?.cancel()
        searchGeneration += 1
        matches = []
        guard let snapshot else { searchTask = nil; return }
        let generation = searchGeneration, query = query, mode = mode
        searchTask = Task { [weak self] in
            do {
                let result = try await VisualSearchQuery.search(snapshot.entries, query: query, mode: mode)
                try Task.checkCancellation()
                guard let self, searchGeneration == generation, self.snapshot?.id == snapshot.id else { return }
                matches = result
            } catch { /* Superseded searches are intentionally discarded. */ }
        }
    }
}
