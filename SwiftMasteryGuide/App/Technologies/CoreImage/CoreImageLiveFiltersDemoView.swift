//
//  CoreImageLiveFiltersDemoView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 09/09/25.
//

import SwiftUI
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import MetalKit
import UIKit

// MARK: - Public SwiftUI Entry

struct CoreImagePhotoFiltersDemoView: View {
    @StateObject private var vm = PhotoFilterViewModel()

    @State private var showPicker = false
    @State private var shareItem: UIImage?
    @State private var saveAlert: SaveAlert?

    var body: some View {
        VStack(spacing: 0) {
            // Image preview
            ZStack {
                Color.backgroundScreen

                if let ui = vm.renderedPreview {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Filtered image preview")
                        .overlay(alignment: .topLeading) {
                            if vm.splitModeEnabled {
                                SplitMaskOverlay(progress: vm.splitProgress)
                                    .allowsHitTesting(false)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if vm.originalImage != nil {
                                Text(vm.selectedFilter.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.35))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .padding(8)
                                    .accessibilityHidden(true)
                            }
                        }
                } else {
                    PlaceholderView(
                        title: "Pick a photo to start",
                        subtitle: "Apply Core Image filters and adjust intensity."
                    )
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.background)
            .contentShape(Rectangle())
            .onTapGesture {
                if vm.originalImage == nil {
                    showPicker = true
                }
            }

            // Controls
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Button {
                        showPicker = true
                    } label: {
                        Label(vm.originalImage == nil ? "Pick Photo" : "Change Photo", systemImage: "photo.on.rectangle.angled")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityLabel("Pick photo from library")

                    Spacer()

                    Button {
                        if let img = vm.exportImage() {
                            shareItem = img
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.dividerColor, lineWidth: 1)
                            )
                    }
                    .disabled(vm.renderedPreview == nil)
                    .accessibilityLabel("Share edited image")

                    Button {
                        vm.saveToPhotos { result in
                            switch result {
                                case .success:
                                    saveAlert = SaveAlert(
                                        title: "Saved",
                                        message: "Your edited image was saved to Photos."
                                    )
                                case .failure(let err):
                                    saveAlert = SaveAlert(
                                        title: "Save Failed",
                                        message: err.localizedDescription
                                    )
                            }
                        }
                    } label: {
                        Label("Save", systemImage: "tray.and.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(vm.renderedPreview == nil)
                    .accessibilityLabel("Save edited image to Photos")
                }
                .padding(.horizontal, 16)

                // Filter picker
                FilterPicker(selection: $vm.selectedFilter)

                // Intensity slider
                if vm.selectedFilter.usesIntensity {
                    HStack {
                        Text("Intensity")
                            .foregroundColor(.textPrimary)
                            .font(.system(size: 14, weight: .semibold))
                        Slider(value: $vm.intensity, in: 0...1)
                            .accessibilityLabel("Filter intensity")
                        Text(String(format: "%.2f", vm.intensity))
                            .foregroundColor(.textSecondary)
                            .font(.system(size: 13))
                            .frame(width: 44, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                }

                HStack(spacing: 12) {
                    Toggle(isOn: $vm.splitModeEnabled) {
                        Text("Before / After")
                            .foregroundColor(.textPrimary)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    .accessibilityLabel("Toggle before and after view")

                    if vm.splitModeEnabled {
                        SplitSlider(progress: $vm.splitProgress)
                            .frame(height: 28)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .padding(.top, 12)
            .background(Color.cardBackground)
        }
        .sheet(isPresented: $showPicker) {
            PhotoPickerView { uiImage in
                vm.setOriginalImage(uiImage)
            }
        }
        .sheet(item: Binding(
            get: { shareItem.map(ShareItem.init(uiImage:)) },
            set: { _ in shareItem = nil })
        ) { item in
            ActivityViewController(items: [item.uiImage])
        }
        .alert(item: $saveAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .navigationTitle("Core Image Filters (Photos)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - ViewModel

final class PhotoFilterViewModel: ObservableObject {

    // Public state
    @Published private(set) var renderedPreview: UIImage?
    @Published var splitModeEnabled: Bool = false
    @Published var splitProgress: CGFloat = 0.5
    @Published var selectedFilter: FilterKind = .sepia { didSet { renderAsync() } }
    @Published var intensity: Double = 0.7 { didSet { renderAsync() } }

    // Original image
    private(set) var originalImage: UIImage?

    // Core Image
    private let ciContext: CIContext
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let renderQueue = DispatchQueue(label: "ci.photo.render.queue", qos: .userInitiated)
    
    // Debouncing for performance
    private var renderTask: DispatchWorkItem?

    // Cache last CIImage to avoid recreating from UIImage each time
    private var originalCI: CIImage?

    // MARK: Lifecycle

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false,
                .allowLowPower: true
            ])
        } else {
            ciContext = CIContext(options: [
                .useSoftwareRenderer: false,
                .cacheIntermediates: false
            ])
        }
    }

    // MARK: Public API

    func setOriginalImage(_ image: UIImage?) {
        // Clear previous resources
        originalImage = nil
        originalCI = nil
        renderedPreview = nil
        
        // Resize large images to prevent memory issues
        let resizedImage = image.flatMap { resizeImageIfNeeded($0) }
        originalImage = resizedImage
        originalCI = resizedImage.flatMap { ciImage(from: $0) }
        renderAsync()
    }
    
    private func resizeImageIfNeeded(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 2048
        let size = image.size
        
        guard max(size.width, size.height) > maxDimension else { return image }
        
        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }

    func exportImage() -> UIImage? {
        guard let ci = currentOutputCI() else { return nil }
        guard let cg = ciContext.createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: colorSpace) else { return nil }
        return UIImage(cgImage: cg, scale: UIScreen.main.scale, orientation: .up)
    }

    func saveToPhotos(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let image = exportImage() else {
            completion(.failure(NSError(domain: "Export", code: -1, userInfo: [NSLocalizedDescriptionKey: "No image to save."])))
            return
        }
        // Requires NSPhotoLibraryAddUsageDescription
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                completion(.failure(NSError(domain: "Photos", code: -2, userInfo: [NSLocalizedDescriptionKey: "Photo Library permission not granted."])))
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if success { completion(.success(())) }
                else { completion(.failure(error ?? NSError(domain: "Photos", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unknown error saving image."]))) }
            }
        }
    }

    // MARK: Rendering

    func renderAsync() {
        // Cancel previous render task
        renderTask?.cancel()
        
        let source = originalCI
        let filter = selectedFilter
        let useSplit = splitModeEnabled
        let prog = splitProgress
        let val = intensity

        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let source else {
                DispatchQueue.main.async { self.renderedPreview = nil }
                return
            }

            let outputCI: CIImage
            if useSplit {
                let filtered = self.apply(filter: filter, to: source, amount: Float(val))
                outputCI = self.compositeSplit(original: source, filtered: filtered, progress: prog)
            } else {
                outputCI = self.apply(filter: filter, to: source, amount: Float(val))
            }

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            // Limit render size to prevent memory issues
            let targetRect = self.limitRenderSize(outputCI.extent.integral)
            guard let cg = self.ciContext.createCGImage(outputCI, from: targetRect, format: .RGBA8, colorSpace: self.colorSpace) else { return }
            let ui = UIImage(cgImage: cg, scale: UIScreen.main.scale, orientation: .up)

            DispatchQueue.main.async { [weak self] in
                guard !Task.isCancelled else { return }
                self?.renderedPreview = ui
            }
        }
        
        renderTask = task
        renderQueue.asyncAfter(deadline: .now() + 0.05, execute: task)
    }
    
    private func limitRenderSize(_ rect: CGRect) -> CGRect {
        // Limit to 4K resolution to prevent memory issues
        let maxDimension: CGFloat = 4096
        let scale = min(maxDimension / rect.width, maxDimension / rect.height, 1.0)
        
        if scale < 1.0 {
            let scaledWidth = rect.width * scale
            let scaledHeight = rect.height * scale
            return CGRect(x: rect.minX, y: rect.minY, width: scaledWidth, height: scaledHeight)
        }
        return rect
    }

    private func currentOutputCI() -> CIImage? {
        guard let source = originalCI else { return nil }
        if splitModeEnabled {
            let filtered = apply(filter: selectedFilter, to: source, amount: Float(intensity))
            return compositeSplit(original: source, filtered: filtered, progress: splitProgress)
        } else {
            return apply(filter: selectedFilter, to: source, amount: Float(intensity))
        }
    }

    // MARK: Filters

    enum FilterKind: CaseIterable {
        case none, sepia, monochrome, vibrance, bloom, comic, gaussianBlur, vignette

        var title: String {
            switch self {
                case .none: return "None"
                case .sepia: return "Sepia"
                case .monochrome: return "Monochrome"
                case .vibrance: return "Vibrance"
                case .bloom: return "Bloom"
                case .comic: return "Comic"
                case .gaussianBlur: return "Gaussian Blur"
                case .vignette: return "Vignette"
            }
        }

        var usesIntensity: Bool {
            switch self {
                case .none, .comic: return false
                default: return true
            }
        }
    }

    private func apply(filter: FilterKind, to image: CIImage, amount: Float) -> CIImage {
        switch filter {
            case .none:
                return image

            case .sepia:
                let f = CIFilter.sepiaTone()
                f.inputImage = image
                f.intensity = amount
                return f.outputImage ?? image

            case .monochrome:
                let f = CIFilter.colorMonochrome()
                f.inputImage = image
                f.intensity = amount
                f.color = CIColor(red: 0.92, green: 0.92, blue: 0.92)
                return f.outputImage ?? image

            case .vibrance:
                let f = CIFilter.vibrance()
                f.inputImage = image
                f.amount = amount * 1.5
                return f.outputImage ?? image

            case .bloom:
                let f = CIFilter.bloom()
                f.inputImage = image
                f.intensity = amount
                f.radius = 5 + amount * 30
                return f.outputImage ?? image

            case .comic:
                let f = CIFilter.comicEffect()
                f.inputImage = image
                return f.outputImage ?? image

            case .gaussianBlur:
                let f = CIFilter.gaussianBlur()
                f.inputImage = image
                f.radius = amount * 8 + 0.5
                return (f.outputImage ?? image).clampedToExtent().cropped(to: image.extent)

            case .vignette:
                let f = CIFilter.vignette()
                f.inputImage = image
                f.intensity = amount * 1.2
                f.radius = amount * 2.0 + 1.0
                return f.outputImage ?? image
        }
    }

    // MARK: Split composite

    private func compositeSplit(original: CIImage, filtered: CIImage, progress: CGFloat) -> CIImage {
        let p = max(0, min(1, progress))
        let extent = original.extent
        let width = extent.width
        let height = extent.height
        let splitX = width * p

        let leftRect = CGRect(x: extent.minX, y: extent.minY, width: splitX, height: height)
        let rightRect = CGRect(x: extent.minX + splitX, y: extent.minY, width: width - splitX, height: height)

        // Left side shows filtered image, right side shows original
        let leftCropped = filtered.cropped(to: leftRect)
        let rightCropped = original.cropped(to: rightRect)
        
        // Composite them together without transformation to maintain original extent
        let result = leftCropped.composited(over: rightCropped)
        
        // Ensure the result has the same extent as the original
        return result.cropped(to: extent)
    }

    // MARK: Utilities

    private func ciImage(from ui: UIImage) -> CIImage? {
        if let cg = ui.cgImage {
            // Respect original orientation by applying transform once and then render as .up
            let base = CIImage(cgImage: cg)
            let oriented = base.oriented(forExifOrientation: Int32(ui.imageOrientation.exifOrientation))
            return oriented
        }
        if let ci = ui.ciImage {
            return ci
        }
        return nil
    }
}

// MARK: - UI Pieces

private struct FilterPicker: View {
    @Binding var selection: PhotoFilterViewModel.FilterKind

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PhotoFilterViewModel.FilterKind.allCases, id: \.self) { kind in
                    Button {
                        selection = kind
                    } label: {
                        Text(kind.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(selection == kind ? .white : .textPrimary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(selection == kind ? Color.accentColor : Color.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.dividerColor, lineWidth: selection == kind ? 0 : 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityLabel("Select \(kind.title) filter")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

private struct PlaceholderView: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48, weight: .regular))
                .foregroundColor(.textSecondary)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.dividerColor, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct SplitMaskOverlay: View {
    let progress: CGFloat
    var body: some View {
        GeometryReader { geo in
            let x = max(0, min(geo.size.width, geo.size.width * progress))
            Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: geo.size.height))
            }
            .stroke(Color.white.opacity(0.9), lineWidth: 2)
        }
    }
}

private struct SplitSlider: View {
    @Binding var progress: CGFloat
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.inputBackground)
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: geo.size.width * max(0, min(1, progress)))
                Circle()
                    .fill(Color.cardBackground)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.dividerColor, lineWidth: 1))
                    .offset(x: max(0, min(geo.size.width - 24, geo.size.width * progress - 12)))
                    .shadow(radius: 1.5)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = value.location.x / max(1, geo.size.width)
                        progress = max(0, min(1, p))
                    }
            )
        }
        .accessibilityLabel("Adjust before and after divider")
    }
}

// MARK: - Photo Picker (PHPicker)

private struct PhotoPickerView: UIViewControllerRepresentable {
    let onSelect: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onSelect: (UIImage?) -> Void
        init(onSelect: @escaping (UIImage?) -> Void) { self.onSelect = onSelect }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else {
                onSelect(nil)
                return
            }
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { obj, _ in
                    let img = obj as? UIImage
                    DispatchQueue.main.async { self.onSelect(img) }
                }
            } else {
                onSelect(nil)
            }
        }
    }
}

// MARK: - UIKit share sheet

private struct ShareItem: Identifiable {
    let id = UUID()
    let uiImage: UIImage
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Helpers

private struct SaveAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private extension UIImage.Orientation {
    // Map to EXIF for CI orientation
    var exifOrientation: UInt32 {
        switch self {
            case .up: return 1
            case .down: return 3
            case .left: return 8
            case .right: return 6
            case .upMirrored: return 2
            case .downMirrored: return 4
            case .leftMirrored: return 5
            case .rightMirrored: return 7
            @unknown default: return 1
        }
    }
}
