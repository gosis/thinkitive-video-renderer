//
//  LibraryView.swift
//  OutlineStudio
//

import SwiftUI

/// Home screen once there are saved projects: start something new or keep editing.
struct LibraryView: View {
    let store: ProjectStore
    let isLoading: Bool
    let open: (Project) -> Void
    let choosePhoto: () -> Void
    let browseFiles: () -> Void
    let useSample: () -> Void
    let newBlank: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var renaming: Project?
    @State private var newName = ""
    @State private var deleting: Project?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                newRow
                Text("Your videos")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                // Wider cards on iPad so names have room
                LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 240 : 150), spacing: 14,
                                             alignment: .top)],
                          spacing: 14) {
                    ForEach(store.projects) { project in
                        ProjectCard(project: project, thumbnail: store.thumbnailURL(for: project)) {
                            open(project)
                        }
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                newName = project.name
                                renaming = project
                            }
                            Button("Duplicate", systemImage: "plus.square.on.square") {
                                Task { try? await store.duplicate(project) }
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                deleting = project
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .disabled(isLoading)
        .alert("Rename video", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renaming { store.rename(renaming, to: newName) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this video?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { project in
            Button("Delete \u{201C}\(project.name)\u{201D}", role: .destructive) { store.delete(project) }
        } message: { _ in
            Text("The project and its copy of the video are removed from this device. Exported videos in Photos aren't affected.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            InkcapMark()
                .frame(width: 34, height: 34)
            Text("Inkcap")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    /// One row at the buttons' natural width when it fits (iPad), otherwise two by two.
    private var newRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                newButtons(fill: false)
            }
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    newButton("From Photos", symbol: "photo.on.rectangle", prominent: true, fill: true, action: choosePhoto)
                    newButton("Blank video", symbol: "rectangle.badge.plus", fill: true, action: newBlank)
                }
                GridRow {
                    newButton("From Files", symbol: "folder", fill: true, action: browseFiles)
                    newButton("Sample clip", symbol: "sparkles.tv", fill: true, action: useSample)
                }
            }
        }
        .glassGroup(spacing: 10)
    }

    @ViewBuilder
    private func newButtons(fill: Bool) -> some View {
        newButton("From Photos", symbol: "photo.on.rectangle", prominent: true, fill: fill, action: choosePhoto)
        newButton("Blank video", symbol: "rectangle.badge.plus", fill: fill, action: newBlank)
        newButton("From Files", symbol: "folder", fill: fill, action: browseFiles)
        newButton("Sample clip", symbol: "sparkles.tv", fill: fill, action: useSample)
    }

    @ViewBuilder
    private func newButton(_ title: String, symbol: String, prominent: Bool = false, fill: Bool,
                           action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .frame(maxWidth: fill ? .infinity : nil, minHeight: 32)
        }
        .controlSize(.large)
        if prominent {
            button.buttonStyle(.glassProminent).tint(Theme.accent)
        } else {
            button.buttonStyle(.glass).foregroundStyle(Theme.textPrimary)
        }
    }
}

private struct ProjectCard: View {
    let project: Project
    let thumbnail: URL
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                // The card decides the size; the image fills and crops inside it, so a
                // wide thumbnail can't stretch the card past its column
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .overlay { thumbnailImage }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Text(project.duration.timecode.dropLast(3))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(project.modified, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 4)
            }
            .padding(8)
            .glassPanel(cornerRadius: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(project.name)")
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let image = UIImage(contentsOfFile: thumbnail.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(.black)
                .overlay(InkcapMark(color: Theme.accent.opacity(0.5)).frame(width: 44, height: 44))
        }
    }
}
