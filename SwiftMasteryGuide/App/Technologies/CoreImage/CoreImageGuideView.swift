//
//  CoreImageGuideView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 09/09/25.
//

import SwiftUI

/// A comprehensive guide that explains step-by-step how to build
/// a complete Core Image photo filter app with real-time rendering,
/// before/after comparison, memory optimization, and export functionality.
struct CoreImageGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                NavigationLink(destination: CoreImagePhotoFiltersDemoView()) {
                    Text("Open Core Image Filters Demo")
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .accessibilityLabel("Open Core Image filters demo")

                Title("Core Image Photo Filters -- Complete Guide")

                Subtitle("What you'll build")
                BodyText("""
A production-ready photo filter app with real-time Core Image rendering, \
interactive before/after comparison, memory-optimized processing pipeline, \
and full export/save functionality with proper image handling and error management.
""")

                Subtitle("Requirements")
                BulletList([
                    "iOS 14+ (for PhotosUI and improved Core Image performance).",
                    "Add NSPhotoLibraryAddUsageDescription to Info.plist for saving.",
                    "Frameworks: SwiftUI, CoreImage, Photos, PhotosUI, MetalKit.",
                    "Test on real device for optimal Metal performance."
                ])

                DividerLine()

                Subtitle("Architecture Overview")
                BodyText("""
• PhotoFilterViewModel → Manages image processing, filter application, and memory optimization.
• FilterKind enum → Defines available Core Image filters with intensity support.
• Memory Management → Automatic image resizing and resource cleanup for stability.
• Before/After UI → Interactive split view with real-time draggable divider.
• Export System → High-quality image export with proper format handling.
""")

                DividerLine()

                // MARK: - Step 1: Filter Types

                Subtitle("Step 1) Filter Types and Configuration")
                BodyText("""
Define the available Core Image filters with their properties. Each filter \
specifies whether it supports intensity adjustment and provides a user-friendly name \
for the UI. This enum-based approach ensures type safety and easy extensibility.
""")
                CodeBlock("""
// Inside PhotoFilterViewModel
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
""")

                // MARK: - Step 2: Core Image Processing

                Subtitle("Step 2) Core Image Filter Application")
                BodyText("""
The filter application system uses Core Image's built-in filters with proper \
parameter handling. Each filter is configured with appropriate intensity scaling \
and parameter ranges to ensure optimal visual results across different image types.
""")
                CodeBlock("""
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
""")

                // MARK: - Step 3: Memory Optimization

                Subtitle("Step 3) Memory Management and Optimization")
                BodyText("""
Critical for preventing memory crashes when processing large images. The system \
automatically resizes input images, limits render dimensions, and uses Metal \
acceleration when available. This ensures stable performance across all devices.
""")
                CodeBlock("""
// Automatic image resizing to prevent memory issues
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

// Metal-optimized Core Image context
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

// Render size limiting
private func limitRenderSize(_ rect: CGRect) -> CGRect {
    let maxDimension: CGFloat = 4096
    let scale = min(maxDimension / rect.width, maxDimension / rect.height, 1.0)
    
    if scale < 1.0 {
        let scaledWidth = rect.width * scale
        let scaledHeight = rect.height * scale
        return CGRect(x: rect.minX, y: rect.minY, width: scaledWidth, height: scaledHeight)
    }
    return rect
}
""")

                // MARK: - Step 4: Before/After Feature

                Subtitle("Step 4) Interactive Before/After Comparison")
                BodyText("""
The before/after feature uses Core Image compositing to create a split view where \
the left side shows the original image and the right side shows the filtered version. \
The divider line is draggable for real-time comparison.
""")
                CodeBlock("""
// Split view compositing
private func compositeSplit(original: CIImage, filtered: CIImage, progress: CGFloat) -> CIImage {
    let p = max(0, min(1, progress))
    let extent = original.extent
    let width = extent.width
    let height = extent.height
    let splitX = width * p

    let leftRect = CGRect(x: extent.minX, y: extent.minY, width: splitX, height: height)
    let rightRect = CGRect(x: extent.minX + splitX, y: extent.minY, width: width - splitX, height: height)

    // Left side shows original (before), right side shows filtered (after)
    let leftCropped = original.cropped(to: leftRect)
    let rightCropped = filtered.cropped(to: rightRect)
    
    // Composite them together maintaining original extent
    let result = leftCropped.composited(over: rightCropped)
    return result.cropped(to: extent)
}

// Interactive draggable overlay
private struct SplitMaskOverlay: View {
    @Binding var progress: CGFloat
    
    var body: some View {
        GeometryReader { geo in
            let x = max(0, min(geo.size.width, geo.size.width * progress))
            
            ZStack {
                // Full-area drag gesture
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let newProgress = max(0, min(1, value.location.x / geo.size.width))
                                progress = newProgress
                            }
                    )
                
                // Visual split line with handle
                Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
                .stroke(Color.white.opacity(0.9), lineWidth: 3)
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
                
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .position(x: x, y: geo.size.height / 2)
            }
        }
    }
}
""")

                // MARK: - Step 5: Real-time Rendering

                Subtitle("Step 5) Optimized Real-time Rendering Pipeline")
                BodyText("""
The rendering system uses background processing with debouncing for smooth performance. \
Split mode updates happen immediately while other changes are debounced to prevent \
excessive processing during rapid slider adjustments.
""")
                CodeBlock("""
// Dual rendering modes for optimal performance
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

        guard !Task.isCancelled else { return }

        let targetRect = self.limitRenderSize(outputCI.extent.integral)
        guard let cg = self.ciContext.createCGImage(outputCI, from: targetRect, format: .RGBA8, colorSpace: self.colorSpace) else { return }
        let ui = UIImage(cgImage: cg, scale: UIScreen.main.scale, orientation: .up)

        DispatchQueue.main.async { [weak self] in
            guard !Task.isCancelled else { return }
            self?.renderedPreview = ui
        }
    }
    
    renderTask = task
    renderQueue.asyncAfter(deadline: .now() + 0.05, execute: task) // Debounced
}

// Immediate rendering for split adjustments
private func renderSplitImmediate() {
    guard splitModeEnabled else {
        renderAsync()
        return
    }
    
    // Same logic but executes immediately without delay
    renderTask?.cancel()
    let task = DispatchWorkItem { /* ... same rendering logic ... */ }
    renderTask = task
    renderQueue.async(execute: task) // No delay for split progress
}
""")

                // MARK: - Step 6: Photo Picker Integration

                Subtitle("Step 6) Modern Photo Picker Integration")
                BodyText("""
Uses PHPickerViewController for modern, privacy-friendly photo selection. \
The integration handles image loading, format conversion, and orientation \
correction automatically while respecting user privacy preferences.
""")
                CodeBlock("""
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
""")

                // MARK: - Step 7: Export and Save

                Subtitle("Step 7) High-Quality Export and Save System")
                BodyText("""
The export system always saves the complete filtered image at full resolution, \
regardless of the current UI state. It handles Photos framework integration \
with proper permission handling and error management.
""")
                CodeBlock("""
// Always export full filtered image (not split view)
func exportImage() -> UIImage? {
    guard let source = originalCI else { return nil }
    // Always export the full filtered image, never the split view
    let filteredCI = apply(filter: selectedFilter, to: source, amount: Float(intensity))
    guard let cg = ciContext.createCGImage(filteredCI, from: filteredCI.extent, format: .RGBA8, colorSpace: colorSpace) else { return nil }
    return UIImage(cgImage: cg, scale: UIScreen.main.scale, orientation: .up)
}

// Photos framework integration with permission handling
func saveToPhotos(completion: @escaping (Result<Void, Error>) -> Void) {
    guard let image = exportImage() else {
        completion(.failure(NSError(domain: "Export", code: -1, userInfo: [NSLocalizedDescriptionKey: "No image to save."])))
        return
    }
    
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
""")

                DividerLine()

                // MARK: - Implementation Tips

                Subtitle("Implementation Tips & Best Practices")
                BulletList([
                    "Always resize large input images to prevent memory crashes.",
                    "Use Metal acceleration when available for better performance.",
                    "Disable intermediate caching to reduce memory pressure.",
                    "Implement proper image orientation handling with EXIF data.",
                    "Debounce render calls to prevent excessive processing.",
                    "Make split view updates immediate for responsive interaction.",
                    "Export full-quality images regardless of UI preview state.",
                    "Handle background/foreground transitions gracefully.",
                    "Test memory usage with large images and multiple filters."
                ])

                DividerLine()

                // MARK: - Info.plist Configuration

                Subtitle("Info.plist Configuration")
                BodyText("Add the following key to your Info.plist to request Photo Library permission:")
                CodeBlock("""
<key>NSPhotoLibraryAddUsageDescription</key>
<string>This app needs access to save your edited photos to the Photo Library.</string>
""")

                DividerLine()

                // MARK: - Performance Optimization

                Subtitle("Performance Optimization Strategies")

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Memory Management")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Automatically resize input images and limit render dimensions. Use Metal when available and disable intermediate caching.")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Render Pipeline")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Use background queues for processing, debounce UI updates, and make split view adjustments immediate for responsiveness.")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("UI Responsiveness")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Cancel previous render tasks when starting new ones, use weak references to prevent retain cycles, and update UI on main queue.")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Filter Selection")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Disable filters until image is loaded, show intensity controls as disabled rather than hidden, and provide clear visual feedback.")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                    }
                }

                DividerLine()

                // MARK: - Advanced Features

                Subtitle("Advanced Features to Consider")
                BulletList([
                    "Custom filter chains with multiple Core Image filters.",
                    "Real-time camera preview with live filter application.",
                    "Batch processing for multiple images simultaneously.",
                    "Custom Core Image kernels for unique effects.",
                    "Gesture-based filter parameter adjustment.",
                    "Filter preset system with user-defined combinations.",
                    "History/undo system for non-destructive editing.",
                    "Integration with Apple's Vision framework for smart cropping.",
                    "Export to different formats (JPEG, PNG, HEIF) with quality options."
                ])

                DividerLine()

                // MARK: - Testing Checklist

                Subtitle("Testing Checklist")
                BulletList([
                    "✓ Test with various image sizes (small thumbnails to large photos).",
                    "✓ Test filter performance on older devices (A12 and below).",
                    "✓ Test memory usage during extended filtering sessions.",
                    "✓ Test before/after interaction with different aspect ratios.",
                    "✓ Test export functionality with different filter combinations.",
                    "✓ Test Photos permission handling and error states.",
                    "✓ Test background/foreground app transitions.",
                    "✓ Test rapid filter switching for potential crashes.",
                    "✓ Test with images in different orientations (portrait/landscape)."
                ])

                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .navigationTitle("Core Image Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}