import Foundation
import SwiftUI


final class DownloadsWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var knownFiles: Set<String> = []
    private weak var appState: AppState?


    func start(appState: AppState) {
        self.appState = appState
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        knownFiles = Set((try? FileManager.default.contentsOfDirectory(atPath: downloads.path)) ?? [])


        fileDescriptor = open(downloads.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }


        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let current = Set((try? FileManager.default.contentsOfDirectory(atPath: downloads.path)) ?? [])
            let added = current.subtracting(self.knownFiles).filter { !$0.hasPrefix(".") && !$0.hasSuffix(".download") }
            self.knownFiles = current
            if let newest = added.first {
                self.appState?.portalSentFileName = "Received: \(newest)"
                self.appState?.notchMode = .expandedShelf
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    self?.appState?.portalSentFileName = nil
                }
            }
        }
        src.resume()
        self.source = src
    }


    deinit {
        source?.cancel()
        if fileDescriptor >= 0 { close(fileDescriptor) }
    }
}
