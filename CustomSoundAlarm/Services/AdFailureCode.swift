import Foundation

/// `ad_failed` の `code` に使う安定識別子（#147）。
/// エラーの localizedDescription は PII を含みうるため送らない。
enum AdFailureCode: String, Sendable, Equatable {
    case invalidRequest = "invalid_request"
    case noFill = "no_fill"
    case networkError = "network_error"
    case serverError = "server_error"
    case timeout
    case internalError = "internal_error"
    case presentationFailed = "presentation_failed"
    case unknown

    /// Google Mobile Ads SDK の `GADErrorDomain` のコードを安定識別子へ変換する。
    static func from(_ error: Error) -> AdFailureCode {
        let nsError = error as NSError
        // com.google.admob は GADErrorDomain の値。
        guard nsError.domain == "com.google.admob" else { return .unknown }
        switch nsError.code {
        case 0: return .invalidRequest
        case 1: return .noFill
        case 2: return .networkError
        case 3: return .serverError
        case 5: return .timeout
        case 11: return .internalError
        default: return .unknown
        }
    }
}
