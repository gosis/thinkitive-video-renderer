//
//  ProjectStore.swift
//  OutlineStudio
//

import AVFoundation
import Observation
import UIKit

/// Keeps projects on disk, one folder each under Application Support/Projects:
/// the video, `project.json` and a thumbnail.
@MainActor
@Observable
final class ProjectStore {
    /// Most recently edited first.
    private(set) var projects: [Project] = []

    private let root: URL
    private static let projectFile = "project.json"
    private static let thumbnailFile = "thumbnail.jpg"

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appending(path: "Projects", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    // MARK: Files

    func videoURL(for project: Project) -> URL {
        folder(for: project.id).appending(path: project.videoFileName)
    }

    func thumbnailURL(for project: Project) -> URL {
        folder(for: project.id).appending(path: Self.thumbnailFile)
    }

    private func folder(for id: UUID) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    // MARK: Changes

    /// Copies the video into a new project folder and saves the project.
    func create(videoAt source: URL, name: String) async throws -> Project {
        let id = UUID()
        let folder = folder(for: id)
        let fileName = "video." + (source.pathExtension.isEmpty ? "mov" : source.pathExtension)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: fileName)
        // Videos can be large; copy off the main thread
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.copyItem(at: source, to: destination)
        }.value

        let project = Project(id: id, name: name, videoFileName: fileName)
        try write(project)
        await makeThumbnail(for: project)
        reload()
        return project
    }

    func save(_ project: Project) {
        var saved = project
        saved.modified = .now
        try? write(saved)
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = saved
        } else {
            projects.append(saved)
        }
        projects.sort { $0.modified > $1.modified }
    }

    func rename(_ project: Project, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var renamed = project
        renamed.name = trimmed
        save(renamed)
    }

    func duplicate(_ project: Project) async throws {
        var copy = project
        copy.id = UUID()
        copy.name = project.name + " copy"
        copy.created = .now
        let source = folder(for: project.id), destination = folder(for: copy.id)
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.copyItem(at: source, to: destination)
        }.value
        save(copy)
    }

    func delete(_ project: Project) {
        try? FileManager.default.removeItem(at: folder(for: project.id))
        projects.removeAll { $0.id == project.id }
    }

    // MARK: Private

    private func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        projects = folders
            .compactMap { folder in
                guard let data = try? Data(contentsOf: folder.appending(path: Self.projectFile)) else { return nil }
                return try? decoder.decode(Project.self, from: data)
            }
            .sorted { $0.modified > $1.modified }
    }

    private func write(_ project: Project) throws {
        let data = try encoder.encode(project)
        try data.write(to: folder(for: project.id).appending(path: Self.projectFile), options: .atomic)
    }

    /// A still from just into the video, for the library grid.
    private func makeThumbnail(for project: Project) async {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL(for: project)))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        guard let (image, _) = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)),
              let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else { return }
        try? data.write(to: thumbnailURL(for: project))
    }
}
