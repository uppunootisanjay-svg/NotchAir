import Foundation
import Network
import AppKit

final class LocalTransferServer {
    private var listener: NWListener?
    private let appState: AppState
    private let port: NWEndpoint.Port = 8765

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        do {
            let listener = try NWListener(using: .tcp, on: port)
            listener.service = NWListener.Service(
                name: Host.current().localizedName ?? "Mac",
                type: "_notchair._tcp"
            )
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener.start(queue: .global(qos: .userInitiated))
            self.listener = listener

            if let ip = localWiFiAddress() {
                DispatchQueue.main.async {
                    self.appState.serverURL = "http://\(ip):8765"
                }
            }
        } catch {
            print("Server failed to start: \(error)")
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveHeader(connection: connection, buffer: Data())
    }

    private func receiveHeader(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }

            let accumulated = buffer + data
            let delimiter = Data("\r\n\r\n".utf8)

            if let range = accumulated.range(of: delimiter) {
                let headerData = accumulated.subdata(in: 0..<range.lowerBound)
                let initialBody = accumulated.subdata(in: range.upperBound..<accumulated.count)
                let headerText = String(data: headerData, encoding: .utf8) ?? ""
                self.routeRequest(connection: connection, headerText: headerText, initialBody: initialBody)
            } else if !isComplete {
                self.receiveHeader(connection: connection, buffer: accumulated)
            } else {
                connection.cancel()
            }
        }
    }

    private func routeRequest(connection: NWConnection, headerText: String, initialBody: Data) {
        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                headers[parts[0].trimmingCharacters(in: .whitespaces).lowercased()] =
                    parts[1].trimmingCharacters(in: .whitespaces)
            }
        }

        if requestLine.hasPrefix("GET / ") {
            sendHTMLResponse(connection: connection)
        } else if requestLine.hasPrefix("GET /latest") {
            if let push = appState.latestPortalPush,
               let jsonData = try? JSONEncoder().encode(push) {
                sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: jsonData)
            } else {
                sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: Data("{}".utf8))
            }
        } else if requestLine.hasPrefix("GET /shelf") {
            let names = appState.shelfFiles.map(\.fileName)
            let jsonData = (try? JSONSerialization.data(withJSONObject: names)) ?? Data("[]".utf8)
            sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: jsonData)
        } else if requestLine.hasPrefix("GET /download") {
            serveShelfFile(requestLine: requestLine, connection: connection)
        } else if requestLine.hasPrefix("POST /clipboard") {
            let length = Int(headers["content-length"] ?? "0") ?? initialBody.count
            readRemainingBody(connection: connection, current: initialBody, totalLength: length) { [weak self] body in
                if let text = String(data: body, encoding: .utf8), self?.appState.clipboardSyncEnabled == true {
                    DispatchQueue.main.async {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                }
                self?.sendResponse(connection: connection, status: "200 OK", contentType: "text/plain", body: Data("Copied".utf8))
            }
        } else if requestLine.hasPrefix("POST /upload") {
            let fileName = headers["x-file-name"]?.removingPercentEncoding ?? "SharedFile_\(Int(Date().timeIntervalSince1970))"
            let deviceName = headers["x-device-name"]?.removingPercentEncoding ?? "Android"
            let contentLength = Int(headers["content-length"] ?? "0") ?? 0
            handleUpload(connection: connection, fileName: fileName, deviceName: deviceName, contentLength: contentLength, initialBody: initialBody)
        } else {
            sendResponse(connection: connection, status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8))
        }
    }

    private func handleUpload(connection: NWConnection, fileName: String, deviceName: String, contentLength: Int, initialBody: Data) {
        let sizeText = ByteCountFormatter.string(fromByteCount: Int64(contentLength), countStyle: .file)

        DispatchQueue.main.async {
            self.appState.pendingDecision = { [weak self] accepted in
                guard let self else { return }
                if !accepted {
                    self.sendResponse(connection: connection, status: "403 Forbidden", contentType: "text/plain", body: Data("Declined".utf8))
                    return
                }
                self.streamToDownloads(
                    connection: connection,
                    fileName: fileName,
                    deviceName: deviceName,
                    totalLength: contentLength,
                    initialBody: initialBody
                )
            }
            self.appState.notchMode = .incomingRequest(deviceName: deviceName, fileName: fileName, fileSize: sizeText)
        }
    }

    private func streamToDownloads(connection: NWConnection, fileName: String, deviceName: String, totalLength: Int, initialBody: Data) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destination = uniqueURL(in: downloads, fileName: fileName)

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: destination) else {
            sendResponse(connection: connection, status: "500 Internal Server Error", contentType: "text/plain", body: Data("Write failed".utf8))
            return
        }

        let startTime = Date()
        var received = initialBody.count
        handle.write(initialBody)
        updateProgress(fileName: fileName, received: received, total: totalLength, startTime: startTime)

        func receiveNext() {
            if received >= totalLength {
                try? handle.close()
                DispatchQueue.main.async {
                    self.appState.recentTransfers.insert(
                        TransferItem(id: UUID(), fileName: fileName, deviceName: deviceName, direction: "received", date: Date(), localURL: destination),
                        at: 0
                    )
                    self.appState.notchMode = .idle
                }
                self.sendResponse(connection: connection, status: "200 OK", contentType: "text/plain", body: Data("Saved".utf8))
                return
            }

            connection.receive(minimumIncompleteLength: 1, maximumLength: 131072) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    handle.write(data)
                    received += data.count
                    self.updateProgress(fileName: fileName, received: received, total: totalLength, startTime: startTime)
                }
                if error != nil || (isComplete && received < totalLength) {
                    try? handle.close()
                    DispatchQueue.main.async { self.appState.notchMode = .idle }
                    connection.cancel()
                    return
                }
                receiveNext()
            }
        }

        receiveNext()
    }

    private func updateProgress(fileName: String, received: Int, total: Int, startTime: Date) {
        let progress = total > 0 ? min(1.0, Double(received) / Double(total)) : 0
        let elapsed = max(0.05, Date().timeIntervalSince(startTime))
        let speedMBps = (Double(received) / 1_048_576.0) / elapsed
        DispatchQueue.main.async {
            self.appState.notchMode = .transferring(fileName: fileName, progress: progress, speedMBps: speedMBps)
        }
    }

    private func serveShelfFile(requestLine: String, connection: NWConnection) {
        guard let urlPart = requestLine.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: String(urlPart)),
              let name = components.queryItems?.first(where: { $0.name == "name" })?.value,
              let file = appState.shelfFiles.first(where: { $0.fileName == name }),
              let data = try? Data(contentsOf: file.url) else {
            sendResponse(connection: connection, status: "404 Not Found", contentType: "text/plain", body: Data("File not found".utf8))
            return
        }
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=\"\(file.fileName)\"\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func readRemainingBody(connection: NWConnection, current: Data, totalLength: Int, completion: @escaping (Data) -> Void) {
        if current.count >= totalLength {
            completion(current.prefix(totalLength))
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
            let next = current + (data ?? Data())
            if next.count >= totalLength || isComplete {
                completion(next)
            } else {
                self?.readRemainingBody(connection: connection, current: next, totalLength: totalLength, completion: completion)
            }
        }
    }

    private func uniqueURL(in directory: URL, fileName: String) -> URL {
        var candidate = directory.appendingPathComponent(fileName)
        var counter = 1
        let stem = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(stem)_\(counter)" : "\(stem)_\(counter).\(ext)"
            candidate = directory.appendingPathComponent(nextName)
            counter += 1
        }
        return candidate
    }

    private func sendHTMLResponse(connection: NWConnection) {
        let html = """
        <!doctype html>
        <html>
        <head><meta name="viewport" content="width=device-width,initial-scale=1"><title>NotchAir</title></head>
        <body style="font-family:system-ui;padding:24px;background:#111;color:#fff;max-width:480px;margin:auto;">
          <h2>NotchAir</h2>
          <input type="file" id="f" style="margin-bottom:12px;" /><br/>
          <button onclick="upload()">Send File to Mac</button>
          <p id="status" style="color:#7dd3fc;"></p>
          <hr style="border-color:#333;margin:20px 0;"/>
          <textarea id="clip" placeholder="Paste text or link for Mac clipboard..." style="width:100%;height:70px;"></textarea><br/><br/>
          <button onclick="sendClip()">Send Clipboard</button>
          <h3>Mac Notch Shelf</h3>
          <ul id="shelf"></ul>
          <script>
            async function upload() {
              const file = document.getElementById('f').files[0];
              if (!file) return;
              document.getElementById('status').innerText = 'Waiting for Mac Accept...';
              const res = await fetch('/upload', {
                method: 'POST',
                headers: { 'X-File-Name': encodeURIComponent(file.name), 'X-Device-Name': 'Android' },
                body: file
              });
              document.getElementById('status').innerText = res.ok ? 'Sent!' : 'Declined';
            }
            async function sendClip() {
              await fetch('/clipboard', { method: 'POST', body: document.getElementById('clip').value });
              document.getElementById('status').innerText = 'Clipboard synced!';
            }
            fetch('/shelf').then(r => r.json()).then(files => {
              const ul = document.getElementById('shelf');
              files.forEach(n => {
                const li = document.createElement('li');
                li.innerHTML = `<a style="color:#60a5fa" href="/download?name=${encodeURIComponent(n)}">${n}</a>`;
                ul.appendChild(li);
              });
            });
          </script>
        </body>
        </html>
        """
        sendResponse(connection: connection, status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(html.utf8))
    }

    private func sendResponse(connection: NWConnection, status: String, contentType: String, body: Data) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func localWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }
}
