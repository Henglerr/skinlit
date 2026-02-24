import Foundation

public struct AppError: Error, LocalizedError {
    public let message: String
    
    public init(_ message: String) {
        self.message = message
    }
    
    public var errorDescription: String? {
        return message
    }
}

public enum ScreenState<Value> {
    case idle
    case loading
    case success(Value)
    case empty
    case error(AppError)
}
