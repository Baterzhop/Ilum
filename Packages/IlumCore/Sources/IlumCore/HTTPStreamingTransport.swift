import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HTTPStreamEvent: Sendable {
    case response(statusCode: Int)
    case data(Data)
}

public struct HTTPEventStream: Sendable {
    public let events: AsyncThrowingStream<HTTPStreamEvent, Error>
    public let cancel: @Sendable () -> Void
    public init(events: AsyncThrowingStream<HTTPStreamEvent, Error>, cancel: @escaping @Sendable () -> Void) {
        self.events = events; self.cancel = cancel
    }
}

public protocol HTTPStreamingTransport: Sendable {
    func open(_ request: URLRequest) -> HTTPEventStream
}

/// Uses data delegates on both macOS and Linux; data(for:) would buffer the whole answer.
public struct URLSessionStreamingTransport: HTTPStreamingTransport {
    public init() {}
    public func open(_ request: URLRequest) -> HTTPEventStream {
        let delegate = StreamingDelegate()
        let events = AsyncThrowingStream<HTTPStreamEvent, Error> { continuation in
            continuation.onTermination = { @Sendable [weak delegate] _ in delegate?.cancel() }
            delegate.start(request, continuation: continuation)
        }
        return HTTPEventStream(events: events, cancel: { delegate.cancel() })
    }
}

// URLSession callbacks and consumer cancellation may arrive on different threads.
// All mutable state is protected by lock; continuations are finished outside it.
private final class StreamingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<HTTPStreamEvent, Error>.Continuation?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var receivedBytes = 0
    private let byteLimit = 8 * 1_024 * 1_024

    func start(_ request: URLRequest, continuation: AsyncThrowingStream<HTTPStreamEvent, Error>.Continuation) {
        lock.lock()
        self.continuation = continuation
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 120
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        lock.unlock()
        task.resume()
    }

    func cancel() { finish(CancellationError()) }

    private func finish(_ error: Error?) {
        lock.lock()
        let continuation = self.continuation
        let session = self.session
        self.continuation = nil
        self.session = nil
        task = nil
        lock.unlock()
        if let error { continuation?.finish(throwing: error) }
        else { continuation?.finish() }
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(ModelProviderError.invalidResponse)
            return
        }
        lock.lock()
        let continuation = self.continuation
        lock.unlock()
        continuation?.yield(.response(statusCode: http.statusCode))
        completionHandler(continuation == nil ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        receivedBytes += data.count
        let exceeded = receivedBytes > byteLimit
        let continuation = self.continuation
        lock.unlock()
        if exceeded { finish(ModelProviderError.responseTooLarge) }
        else { continuation?.yield(.data(data)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error)
    }
}
