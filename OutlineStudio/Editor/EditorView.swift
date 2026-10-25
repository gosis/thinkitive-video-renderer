//
//  EditorView.swift
//  OutlineStudio
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @State private var model = EditorModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showNewComposition = false
    @State private var pickedImage: PickedImage?
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .system
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var isKeyboardVisible = false
    @State private var layoutHeight: CGFloat = 0
    @State private var editorScroll = ScrollPosition(edge: .top)

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if model.hasVideo {
                editor
            } else if model.store.projects.isEmpty {
                EmptyStateView(isLoading: model.isLoading,
                               choosePhoto: { showPhotoPicker = true },
                               browseFiles: { showFileImporter = true },
                               useSample: { Task { await model.loadSampleClip() } },
                               newBlank: { showNewComposition = true })
            } else {
                LibraryView(store: model.store,
                            isLoading: model.isLoading,
                            open: { project in Task { await model.openProject(project) } },
                            choosePhoto: { showPhotoPicker = true },
                            browseFiles: { showFileImporter = true },
                            useSample: { Task { await model.loadSampleClip() } },
                            newBlank: { showNewComposition = true })
            }
        }
        .background {
            // Glass needs colour behind it: the brand glow runs edge to edge, softer
            // and without the pen loops once a video is open
            ZStack {
                Theme.background
                AmbientGlow(intensity: model.hasVideo ? 0.7 : 1, showsLoops: !model.hasVideo)
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItem, matching: .any(of: [.videos, .images]))
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.movie, .image]) { result in
            importFile(result)
        }
        .task {
            // Lets UI tests start in the editor without going through the picker
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-useSampleClip") {
                await model.loadSampleClip()
            } else if let flag = arguments.firstIndex(of: "-openVideo"), arguments.indices.contains(flag + 1) {
                await model.loadVideo(from: URL(fileURLWithPath: arguments[flag + 1]))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onChange(of: showPhotoPicker) { _, shown in
            Log.app.notice("Photo picker \(shown ? "shown" : "dismissed", privacy: .public)")
        }
        .onChange(of: pickerItem) { _, item in
            Log.app.notice("Photo picked: \(item != nil, privacy: .public)")
            guard let item else { return }
            Task {
                await importPhoto(item)
                pickerItem = nil
            }
        }
        .overlay {
            if model.exportState != .idle {
                ExportStatusView(state: model.exportState) { model.exportState = .idle }
                    .transition(.opacity)
            } else if model.isCaptioning {
                captioningStatus
                    .transition(.opacity)
            } else if model.isLoading {
                // Informational only: it must not swallow taps while it fades out
                loadingStatus
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.exportState)
        .animation(.easeOut(duration: 0.2), value: model.isCaptioning)
        .animation(.easeOut(duration: 0.2), value: model.isLoading)
        // Every edit is saved shortly after it's made, and at once when leaving the app
        .onChange(of: model.overlays) { model.scheduleSave() }
        .onChange(of: model.captionLayer) { model.scheduleSave() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.saveProject() }
        }
        .sheet(isPresented: $showNewComposition) {
            NewCompositionSheet { duration, shape in
                Task { await model.newComposition(duration: duration, size: shape.size) }
            }
        }
        .sheet(item: $pickedImage) { picked in
            NewCompositionSheet(image: picked.image) { duration, _ in
                Task { await model.newComposition(fromImage: picked.image, duration: duration) }
            }
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    // MARK: Layout

    private var topBar: some View {
        HStack(spacing: 10) {
            // Home screens show the name large, so the bar only carries it in the editor
            if model.hasVideo {
                Button {
                    model.closeProject()
                } label: {
                    toolbarIcon("chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Library")

                Text(model.project?.name ?? "Inkcap")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { option in
                        Label(option.title, systemImage: option.symbol).tag(option)
                    }
                }
            } label: {
                toolbarIcon(appearance.symbol)
            }
            .accessibilityLabel("Appearance")

            if model.hasVideo {
                Menu {
                    Button("Choose from Photos", systemImage: "photo.on.rectangle") { showPhotoPicker = true }
                    Button("Browse Files", systemImage: "folder") { showFileImporter = true }
                    Button("Sample clip", systemImage: "sparkles.tv") { Task { await model.loadSampleClip() } }
                    Button("New blank video", systemImage: "rectangle.badge.plus") { showNewComposition = true }
                } label: {
                    toolbarIcon("film.stack")
                }
                .accessibilityLabel("New video")

                Button {
                    Task { await model.export() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 4)
                        .frame(height: 24)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
            }
        }
        .glassGroup(spacing: 10)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func toolbarIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 40, height: 40)
            .glassEffect(.regular.interactive(), in: Circle())
    }

    @ViewBuilder
    private var editor: some View {
        if sizeClass == .regular {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 12) {
                    stage
                    transport
                    timeline
                }
                sidebar
            }
            .padding(16)
            .animation(Self.modeAnimation, value: isEditing)
        } else {
            // Scrolls only while the keyboard is up, so the preview keeps its size
            // and a downward swipe dismisses the keyboard
            GeometryReader { proxy in
                ScrollView {
                    // The column fills the screen and the video takes the height the controls
                    // leave, so opening the inspector resizes everything in one animation
                    VStack(spacing: 12) {
                        stage
                            .frame(minHeight: 220, maxHeight: .infinity)
                        transport
                        timeline
                        inspector
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .frame(minHeight: fullHeight(of: proxy))
                    .animation(Self.modeAnimation, value: isEditing)
                }
                .scrollPosition($editorScroll)
                .scrollDismissesKeyboard(.immediately)
                .scrollDisabled(!isKeyboardVisible)
                .onChange(of: isKeyboardVisible) { _, visible in
                    guard !visible else { return }
                    layoutHeight = proxy.size.height
                    withAnimation(.easeOut(duration: 0.25)) { editorScroll.scrollTo(edge: .top) }
                }
                .onAppear { layoutHeight = proxy.size.height }
            }
        }
    }

    /// Height available to the editor with the keyboard hidden.
    private func fullHeight(of proxy: GeometryProxy) -> CGFloat {
        isKeyboardVisible ? max(layoutHeight, proxy.size.height) : proxy.size.height
    }

    private var stage: some View {
        ZStack {
            // Taps anywhere on the stage that miss the text, including the letterbox
            // around the video, leave editing
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.clearSelection() }
                .accessibilityIdentifier("stage")

            PreviewCanvas(model: model, allowsDragging: !isKeyboardVisible)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("videoPreview")
                .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassPanel(cornerRadius: 28)
    }

    private var timeline: some View {
        TimelineStrip(model: model)
            .padding(10)
            .glassPanel(cornerRadius: 20)
    }

    private var transport: some View {
        HStack(spacing: 8) {
            IconButton(symbol: model.isPlaying ? "pause.fill" : "play.fill",
                       label: model.isPlaying ? "Pause" : "Play",
                       prominent: true) {
                model.togglePlayback()
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(model.currentTime.timecode)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                Text(model.duration.timecode)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .combine)

            Spacer()

            IconButton(symbol: "captions.bubble", label: "Auto captions") {
                Task { await model.generateCaptions() }
            }
            .disabled(model.isCaptioning)
            IconButton(symbol: "plus", label: "Add text") { model.addOverlay() }
            IconButton(symbol: "plus.square.on.square", label: "Duplicate text") { model.duplicateSelected() }
                .disabled(model.selectedIndex == nil)
            IconButton(symbol: "trash", label: model.selectedCaptionIndex == nil ? "Delete text" : "Delete caption") {
                model.deleteSelected()
            }
            .disabled(model.selectedIndex == nil && model.selectedCaptionIndex == nil)
        }
        .glassGroup(spacing: 8)
    }

    /// iPad: the inspector lives in a full-height glass sidebar beside the video.
    private var sidebar: some View {
        ScrollView {
            if let id = model.selectedID, model.selectedIndex != nil {
                InspectorPanel(overlay: model.overlayBinding(for: id), duration: model.duration,
                               layout: .sidebar)
                    .id(id)
                    .transition(.opacity)
            } else if let id = model.selectedCaptionID, model.selectedCaptionIndex != nil {
                InspectorPanel(overlay: model.captionBinding(for: id), duration: model.duration,
                               isCaption: true, layout: .sidebar)
                    .id(id)
                    .transition(.opacity)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .frame(width: 380)
        .frame(maxHeight: .infinity)
        .overlay {
            if !isEditing {
                VStack(spacing: 14) {
                    InkcapMark()
                        .frame(width: 56, height: 56)
                    Text("Nothing selected")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Tap a text on the video or timeline to edit it, tap + to add one, or tap the speech bubble for auto captions.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .transition(.opacity)
            }
        }
        .glassPanel(cornerRadius: 28)
    }

    @ViewBuilder
    private var inspector: some View {
        if let id = model.selectedID, model.selectedIndex != nil {
            InspectorPanel(overlay: model.overlayBinding(for: id), duration: model.duration)
                .id(id)
                .transition(Self.inspectorTransition)
        } else if let id = model.selectedCaptionID, model.selectedCaptionIndex != nil {
            InspectorPanel(overlay: model.captionBinding(for: id), duration: model.duration, isCaption: true)
                .id(id)
                .transition(Self.inspectorTransition)
        } else {
            Text("Select a text on the video or timeline to edit it, tap + to add one, or tap the speech bubble for auto captions.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 80)
                .padding(16)
                .glassPanel()
                .transition(.opacity)
        }
    }

    // MARK: Watching ↔ editing

    /// Whether a layer is selected and the inspector is open.
    private var isEditing: Bool {
        model.selectedIndex != nil || model.selectedCaptionIndex != nil
    }

    /// Used when the inspector opens or closes; switching between layers stays instant.
    private static let modeAnimation = Animation.snappy(duration: 0.32)

    /// The inspector rises from below as editing starts and fades as it ends.
    private static let inspectorTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity),
        removal: .opacity)

    private var loadingStatus: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Opening video…")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(28)
            .glassPanel(cornerRadius: 28)
        }
    }

    private var captioningStatus: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Listening for speech…")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Captions are made on this device.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(24)
            .frame(width: 280)
            .glassPanel(cornerRadius: 28)
        }
    }

    // MARK: Import

    private func importPhoto(_ item: PhotosPickerItem) async {
        // Copying a video out of Photos can take a while; show the loader meanwhile
        model.isLoading = true
        defer { model.isLoading = false }
        Log.app.notice("Importing from Photos: \(item.supportedContentTypes.map(\.identifier), privacy: .public)")
        do {
            // A photo becomes a still video, so ask how long it should last first
            if !item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    model.alertMessage = "That photo couldn't be opened from Photos."
                    return
                }
                pickedImage = PickedImage(image: image)
                return
            }
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                Log.app.error("Photos returned no movie for the picked item")
                model.alertMessage = "That video couldn't be opened from Photos."
                return
            }
            Log.app.notice("Copied from Photos to \(movie.url.lastPathComponent, privacy: .public)")
            await model.importVideo(from: movie.url)
            try? FileManager.default.removeItem(at: movie.url)
        } catch {
            Log.app.error("Photos import failed: \(error.localizedDescription, privacy: .public)")
            model.alertMessage = error.localizedDescription
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let source = try result.get()
            let accessing = source.startAccessingSecurityScopedResource()
            defer { if accessing { source.stopAccessingSecurityScopedResource() } }

            if UTType(filenameExtension: source.pathExtension)?.conforms(to: .image) == true {
                guard let image = UIImage(contentsOfFile: source.path) else {
                    model.alertMessage = "That image couldn't be opened."
                    return
                }
                pickedImage = PickedImage(image: image)
                return
            }

            let destination = PickedMovie.temporaryURL(extension: source.pathExtension)
            try FileManager.default.copyItem(at: source, to: destination)
            Task {
                await model.importVideo(from: destination)
                try? FileManager.default.removeItem(at: destination)
            }
        } catch {
            model.alertMessage = error.localizedDescription
        }
    }
}

/// A picked photo waiting for the user to choose how long its video should be.
struct PickedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// A movie copied out of the photo library into the app's temporary directory.
struct PickedMovie: Transferable {
    let url: URL

    static func temporaryURL(extension pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "Source-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension.isEmpty ? "mov" : pathExtension)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = temporaryURL(extension: received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}

#Preview {
    EditorView()
}
