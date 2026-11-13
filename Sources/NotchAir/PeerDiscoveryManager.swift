import Foundation
import Network
import SwiftUI

struct NearbyMac: Identifiable, Equatable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
}

final class PeerDiscoveryManager: ObservableObject {
    @Published var peers: [NearbyMac] = []
    private var browser: NWBrowser?
    private let localHostName = Host.current().localizedName ?? "Mac"

    func start() {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_notchair._tcp", domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            let discovered: [NearbyMac] = results.compactMap { result in
                if case let .service(name, _, _, _) = result.endpoint, name != self.localHostName {
                    return NearbyMac(id: name, name: name, endpoint: result.endpoint)
                }
                return nil
            }
            DispatchQueue.main.async { self.peers = discovered }
        }
        browser.start(queue: .global(qos: .utility))
        self.browser = browser
    }

    func sendFile(fileURL: URL, to peer: NearbyMac, appState: AppState) {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let fileName = fileURL.lastPathComponent
        let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fileName
        let encodedHost = localHostName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Mac"

        DispatchQueue.main.async {
            appState.notchMode = .transferring(fileName: "Sending \(fileName) → \(peer.name)", progress: 0.15, speedMBps: 0)
        }

        let conn = NWConnection(to: peer.endpoint, using: .tcp)
        conn.stateUpdateHandler = { state in
            if case .ready = state {
                let header = "POST /upload HTTP/1.1\r\nHost: \(peer.name)\r\nX-File-Name: \(encodedName)\r\nX-Device-Name: \(encodedHost)\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
                let start = Date()
                conn.send(content: Data(header.utf8) + data, completion: .contentProcessed { error in
                    let elapsed = max(0.05, Date().timeIntervalSince(start))
                    let speed = (Double(data.count) / 1_048_576.0) / elapsed
                    DispatchQueue.main.async {
                        if error == nil {
                            appState.notchMode = .transferring(fileName: "Sent \(fileName) ✓", progress: 1.0, speedMBps: speed)
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { appState.notchMode = .idle }
                        } else {
                            appState.notchMode = .idle
                        }
                    }
                    conn.cancel()
                })
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
    }
}
