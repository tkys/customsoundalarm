import Testing
import Foundation
import UniformTypeIdentifiers
@testable import CustomSoundAlarm

/// `VideoFileImporter` の純粋関数（temp URL 生成・型判定）を検証する。
/// `copyToTemp`（I/O）は単体テスト範囲外とし、実機/シミュレータで確認する。
struct VideoFileImporterTests {

    // MARK: - generateTempURL

    @Test
    func generateTempURL_normalExtension() {
        let url = VideoFileImporter.generateTempURL(filename: "abc", extension: "mp4")
        #expect(url.lastPathComponent == "abc.mp4")
        #expect(url.deletingPathExtension().lastPathComponent == "abc")
        #expect(url.pathExtension == "mp4")
    }

    @Test
    func generateTempURL_emptyExtension_defaultsToMov() {
        let url = VideoFileImporter.generateTempURL(filename: "xyz", extension: "")
        #expect(url.pathExtension == "mov")
        #expect(url.lastPathComponent == "xyz.mov")
    }

    @Test
    func generateTempURL_isInTemporaryDirectory() {
        let url = VideoFileImporter.generateTempURL(filename: "test", extension: "mov")
        #expect(url.deletingLastPathComponent().path == FileManager.default.temporaryDirectory.path)
    }

    @Test
    func generateTempURL_uniqueFilenames() {
        let url1 = VideoFileImporter.generateTempURL(filename: UUID().uuidString, extension: "mov")
        let url2 = VideoFileImporter.generateTempURL(filename: UUID().uuidString, extension: "mov")
        #expect(url1.path != url2.path)
    }

    @Test
    func generateTempURL_preservesMovExtension() {
        let url = VideoFileImporter.generateTempURL(filename: "video", extension: "mov")
        #expect(url.pathExtension == "mov")
    }

    @Test
    func generateTempURL_preservesM4vExtension() {
        let url = VideoFileImporter.generateTempURL(filename: "clip", extension: "m4v")
        #expect(url.pathExtension == "m4v")
    }

    // MARK: - isSupportedVideoURL

    @Test
    func isSupportedVideoURL_mov() {
        let url = URL(fileURLWithPath: "/tmp/video.mov")
        #expect(VideoFileImporter.isSupportedVideoURL(url))
    }

    @Test
    func isSupportedVideoURL_mp4() {
        let url = URL(fileURLWithPath: "/tmp/video.mp4")
        #expect(VideoFileImporter.isSupportedVideoURL(url))
    }

    @Test
    func isSupportedVideoURL_m4v() {
        let url = URL(fileURLWithPath: "/tmp/clip.m4v")
        #expect(VideoFileImporter.isSupportedVideoURL(url))
    }

    @Test
    func isSupportedVideoURL_avi() {
        let url = URL(fileURLWithPath: "/tmp/old.avi")
        #expect(VideoFileImporter.isSupportedVideoURL(url))
    }

    @Test
    func isSupportedVideoURL_mpeg() {
        let url = URL(fileURLWithPath: "/tmp/movie.mpeg")
        #expect(VideoFileImporter.isSupportedVideoURL(url))
    }

    @Test
    func isSupportedVideoURL_rejectsAudio() {
        let url = URL(fileURLWithPath: "/tmp/song.mp3")
        #expect(!VideoFileImporter.isSupportedVideoURL(url))
    }

    @Test
    func isSupportedVideoURL_rejectsImage() {
        let url = URL(fileURLWithPath: "/tmp/photo.jpg")
        #expect(!VideoFileImporter.isSupportedVideoURL(url))
    }

    @Test
    func isSupportedVideoURL_rejectsText() {
        let url = URL(fileURLWithPath: "/tmp/notes.txt")
        #expect(!VideoFileImporter.isSupportedVideoURL(url))
    }

    @Test
    func isSupportedVideoURL_rejectsUnknownExtension() {
        let url = URL(fileURLWithPath: "/tmp/file.xyz123")
        #expect(!VideoFileImporter.isSupportedVideoURL(url))
    }

    @Test
    func isSupportedVideoURL_rejectsNoExtension() {
        let url = URL(fileURLWithPath: "/tmp/filewithoutextension")
        #expect(!VideoFileImporter.isSupportedVideoURL(url))
    }

    // MARK: - supportedVideoTypes

    @Test
    func supportedVideoTypes_includesMovie() {
        #expect(VideoFileImporter.supportedVideoTypes.contains(.movie))
    }

    @Test
    func supportedVideoTypes_includesMpeg4Movie() {
        #expect(VideoFileImporter.supportedVideoTypes.contains(.mpeg4Movie))
    }

    @Test
    func supportedVideoTypes_includesQuickTimeMovie() {
        #expect(VideoFileImporter.supportedVideoTypes.contains(.quickTimeMovie))
    }

    // MARK: - defaultSoundName

    @Test
    func defaultSoundName_normalFilename() {
        let url = URL(fileURLWithPath: "/Documents/concert.mp4")
        let name = VideoFileImporter.defaultSoundName(from: url)
        #expect(name == "concert")
    }

    @Test
    func defaultSoundName_stripsExtension() {
        let url = URL(fileURLWithPath: "/Movies/vacation.mov")
        let name = VideoFileImporter.defaultSoundName(from: url)
        #expect(name == "vacation")
        #expect(!name.contains("."))
        #expect(!name.contains(".mov"))
    }

    @Test
    func defaultSoundName_uuid_returnsEmpty() {
        let uuid = UUID().uuidString
        let url = URL(fileURLWithPath: "/tmp/\(uuid).mov")
        let name = VideoFileImporter.defaultSoundName(from: url)
        #expect(name.isEmpty)
    }

    @Test
    func defaultSoundName_uuidDoesNotLeak() {
        let uuid = UUID().uuidString
        let url = URL(fileURLWithPath: "/tmp/\(uuid).mp4")
        let name = VideoFileImporter.defaultSoundName(from: url)
        #expect(!name.contains(uuid))
        #expect(!name.hasSuffix(".mp4"))
        #expect(!name.hasSuffix(".mov"))
    }

    @Test
    func defaultSoundName_photoLibraryFormat() {
        // 写真ライブラリの標準的な命名（IMG_1234）
        let url = URL(fileURLWithPath: "/Photo/IMG_1234.MOV")
        let name = VideoFileImporter.defaultSoundName(from: url)
        #expect(name == "IMG_1234")
    }

    @Test
    func defaultSoundName_japaneseFilename() {
        let url = URL(fileURLWithPath: "/Videos/演奏録画.m4v")
        let name = VideoFileImporter.defaultSoundName(from: url)
        #expect(name == "演奏録画")
    }

    @Test
    func defaultSoundName_noExtension() {
        let url = URL(fileURLWithPath: "/tmp/filewithoutextension")
        let name = VideoFileImporter.defaultSoundName(from: url)
        #expect(name == "filewithoutextension")
    }

    @Test
    func defaultSoundName_lowercaseUuid_returnsEmpty() {
        // UUID() は大文字小文字両方を受理する
        let url = URL(fileURLWithPath: "/tmp/550e8400-e29b-41d4-a716-446655440000.mov")
        let name = VideoFileImporter.defaultSoundName(from: url)
        #expect(name.isEmpty)
    }
}
