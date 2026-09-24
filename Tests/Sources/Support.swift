import Foundation

enum PlayTools {
    static let playCoverContainer = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlayCoverSourcesTests-\(UUID().uuidString)")
}

enum NetworkVM {
    static func isConnectedToNetwork() -> Bool { true }
}

final class TestConnection {
    var isConnected = true
}

// Deliberately ignores cancellation: a completed network response can race with
// removing or refreshing a source, and StoreVM must reject it independently.
actor SourceRequests {
    struct Pending {
        let request: URLRequest
        let continuation: CheckedContinuation<(Data, URLResponse), Error>
    }

    private var pending: [Pending] = []
    var count: Int { pending.count }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            pending.append(Pending(request: request, continuation: continuation))
        }
    }

    func respond(with data: Data, at index: Int = 0) {
        let item = pending.remove(at: index)
        guard let url = item.request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            preconditionFailure("Invalid test request")
        }
        item.continuation.resume(returning: (data, response))
    }
}
