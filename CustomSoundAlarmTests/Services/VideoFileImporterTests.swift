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
}
