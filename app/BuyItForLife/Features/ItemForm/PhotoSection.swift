import PhotosUI
import SwiftUI

/// The top of the item form: pick or take a photo, preview it, and choose
/// between the original and the cutout.
struct PhotoSection: View {
    @Binding var photo: DraftPhoto?
    @Binding var isProcessing: Bool
    var name: String
    var category: ItemCategory?

    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 12) {
            if isProcessing {
                placeholderBox {
                    ProgressView().tint(.textSecondary)
                    Text("Preparing photo…")
                        .font(.rowDetail)
                        .foregroundStyle(.textSecondary)
                }
            } else if let photo {
                preview(photo)
            } else {
                placeholderBox {
                    Image(systemName: "camera")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.textSecondary)
                    HStack(spacing: 8) {
                        if CameraPicker.isAvailable {
                            sourceButton("Take photo", filled: true) { showCamera = true }
                        }
                        sourceButton("From library", filled: false) { showLibrary = true }
                    }
                    if failed {
                        Text("That photo couldn't be used. Try another.")
                            .font(.footnote)
                            .foregroundStyle(.warning)
                    }
                }
            }
        }
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            libraryItem = nil
            Task { await loadLibraryItem(item) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image { Task { await process(image) } }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Pieces

    private func placeholderBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 14, content: content)
            .frame(maxWidth: .infinity, minHeight: 190)
            .background(.surface, in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
    }

    private func sourceButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.rowDetail.weight(filled ? .semibold : .medium))
                .foregroundStyle(.textPrimary)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(filled ? AnyShapeStyle(.surfaceRaised) : AnyShapeStyle(.clear), in: .capsule)
                .overlay { Capsule().strokeBorder(.stroke, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func preview(_ photo: DraftPhoto) -> some View {
        VStack(spacing: 12) {
            ItemImageView(
                content: ItemImageContent(
                    imageData: photo.chosen,
                    isCutout: photo.usesCutout,
                    tintHex: photo.chosenTint,
                    name: name,
                    category: category ?? .other
                ),
                cornerRadius: Radius.card,
                iconSize: 48
            )
            .frame(height: 280)
            .overlay(alignment: .topTrailing) { photoMenu.padding(12) }

            if photo.cutout != nil {
                SegmentedControl(
                    options: [(false, "Original"), (true, "Cutout")],
                    selection: Binding(
                        get: { photo.usesCutout },
                        set: { self.photo?.usesCutout = $0 }
                    )
                )
            } else {
                Text("No clear subject found, so the original photo is used.")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var photoMenu: some View {
        Menu {
            if CameraPicker.isAvailable {
                Button("Take new photo", systemImage: "camera") { showCamera = true }
            }
            Button("Choose from library", systemImage: "photo.on.rectangle") { showLibrary = true }
            Button("Remove photo", systemImage: "trash", role: .destructive) { photo = nil }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.textPrimary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel("Photo options")
    }

    // MARK: Loading

    private func loadLibraryItem(_ item: PhotosPickerItem) async {
        isProcessing = true
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else {
            isProcessing = false
            failed = true
            return
        }
        await process(image)
    }

    private func process(_ image: UIImage) async {
        isProcessing = true
        failed = false
        if let processed = await PhotoProcessor.process(image) {
            photo = DraftPhoto(processed)
        } else {
            failed = true
        }
        isProcessing = false
    }
}
