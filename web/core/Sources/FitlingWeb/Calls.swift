import Foundation

/// One request from the web app, answered with JSON.
public func handle(_ request: Data) -> Data {
    Data("{}".utf8)
}
