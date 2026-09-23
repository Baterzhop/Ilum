import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import IlumCore

final class HTTPStreamingTransportTests: XCTestCase {
    // The server sends its final frame only after the client acknowledges the
    // first delta. A buffered transport produces "buffered" and fails this test.
    func testRealURLSessionDeliversTextBeforeServerCompletes() async throws {
        let fixture = try LoopbackFixture()
        defer { fixture.stop() }
        let endpoint = try await fixture.endpoint()
        let marker = fixture.marker
        let provider = OllamaChatProvider(endpoint: endpoint, model: "fixture")
        let turn = try await provider.respond(to: ModelRequest(messages: []), onProgress: { progress in
            if case .textDelta("early ") = progress { _ = FileManager.default.createFile(atPath: marker.path, contents: Data()) }
        })
        guard case .final(let answer) = turn else { return XCTFail("Expected complete response") }
        XCTAssertEqual(answer, "early released")
    }

    func testRealURLSessionStreamCanBeCancelledWhileServerIsWaiting() async throws {
        let fixture = try LoopbackFixture()
        defer { fixture.stop() }
        var request = URLRequest(url: try await fixture.endpoint())
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        let stream = URLSessionStreamingTransport().open(request)
        defer { stream.cancel() }
        var receivedData = false
        do {
            for try await event in stream.events {
                if case .data = event { receivedData = true; stream.cancel() }
            }
            XCTFail("Explicit cancellation must terminate with an error")
        } catch is CancellationError { }
        XCTAssertTrue(receivedData)
    }
}

private final class LoopbackFixture {
    let root: URL
    let marker: URL
    private let portFile: URL
    private let process: Process

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ilum-stream-\(UUID().uuidString)")
        marker = root.appendingPathComponent("release")
        portFile = root.appendingPathComponent("port")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("server.py")
        try Self.python.write(to: script, atomically: true, encoding: .utf8)
        process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-u", script.path, root.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    func endpoint() async throws -> URL {
        for _ in 0..<250 {
            if let text = try? String(contentsOf: portFile, encoding: .utf8), let port = Int(text),
               let url = URL(string: "http://127.0.0.1:\(port)/api/chat") { return url }
            if !process.isRunning { throw FixtureError.serverFailed }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw FixtureError.serverFailed
    }

    func stop() {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        try? FileManager.default.removeItem(at: root)
    }

    private enum FixtureError: Error { case serverFailed }
    private static let python = #"""
import http.server, json, pathlib, sys, time
root = pathlib.Path(sys.argv[1])
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        self.send_response(200)
        self.send_header('Content-Type', 'application/x-ndjson')
        self.end_headers()
        def frame(content, done):
            self.wfile.write((json.dumps({'message': {'role': 'assistant', 'content': content},
                                         'done': done, 'done_reason': 'stop' if done else None}) + '\n').encode())
            self.wfile.flush()
        try:
            frame('early ', False)
            for _ in range(300):
                if (root / 'release').exists(): break
                time.sleep(0.01)
            frame('released' if (root / 'release').exists() else 'buffered', True)
        except (BrokenPipeError, ConnectionResetError): pass
server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
(root / 'port').write_text(str(server.server_address[1]))
server.handle_request()
"""#
}
