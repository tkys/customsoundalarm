import Foundation

/// 「やさしく鳴り始める」を選べるか（#312・単体テスト対象）。
///
/// 音が「デフォルト」（iPhone 標準のアラーム音）でプレイリストも無いときは、
/// 標準の音をアプリから加工できないので、やさしく始まらない。
/// 書き出し側（#311・`!input.isPlaylist && fallbackFileName.isEmpty`）と同じ条件。
enum FadeInAvailability {
    static func isAvailable(soundFileName: String, playlistID: UUID?) -> Bool {
        playlistID != nil || !soundFileName.isEmpty
    }
}
