//
//  PushNotificationsVideoDemoView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 21/08/25.
//

import SwiftUI
import UserNotifications
@preconcurrency import AVFoundation

/// A practical demo view for testing Push Notifications with Video functionality.
/// Allows users to schedule test notifications and see the rich media notifications in action.
struct PushNotificationsVideoDemoView: View {
    @StateObject private var viewModel = PushNotificationsDemoViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
            
            Title("Push Notifications Video Demo")
            
            // Permission Status Section
            VStack(alignment: .leading, spacing: 12) {
                Subtitle("Permission Status")
                
                HStack {
                    Image(systemName: viewModel.permissionStatusIcon)
                        .foregroundColor(viewModel.permissionStatusColor)
                    Text(viewModel.permissionStatusText)
                        .foregroundColor(.textPrimary)
                }
                .padding()
                .background(Color.cardBackground)
                .cornerRadius(12)
                
                if viewModel.permissionStatus != .authorized {
                    Button("Request Notification Permission") {
                        Task {
                            await viewModel.requestPermission()
                        }
                    }
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .accessibilityLabel("Request notification permission")
                }
            }
            
            DividerLine()
            
            // Demo Actions Section
            VStack(alignment: .leading, spacing: 16) {
                Subtitle("Test Notifications")
                
                BodyText("Try these different notification types to see rich media in action:")
                
                VStack(spacing: 12) {
                    // Simple Video Notification
                    DemoButton(
                        title: "📹 Schedule Video Notification",
                        subtitle: "Remote video download simulation",
                        isEnabled: viewModel.canScheduleNotifications && !viewModel.isScheduling
                    ) {
                        Task {
                            await viewModel.scheduleVideoNotification()
                        }
                    }
                    
                    // Rich Media Notification
                    DemoButton(
                        title: "🖼️ Rich Media Notification",
                        subtitle: "With image attachment",
                        isEnabled: viewModel.canScheduleNotifications && !viewModel.isScheduling
                    ) {
                        Task {
                            await viewModel.scheduleLocalVideoNotification()
                        }
                    }
                    
                    // Interactive Rich Media Notification  
                    DemoButton(
                        title: "🎨 Interactive Rich Media",
                        subtitle: "Custom image with action buttons",
                        isEnabled: viewModel.canScheduleNotifications && !viewModel.isScheduling
                    ) {
                        Task {
                            await viewModel.scheduleInteractiveRichMediaNotification()
                        }
                    }
                }
            }
            
            DividerLine()
            
            // Status Messages
            if !viewModel.statusMessage.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Subtitle("Status")
                    Text(viewModel.statusMessage)
                        .foregroundColor(.textSecondary)
                        .padding()
                        .background(Color.backgroundSurface)
                        .cornerRadius(8)
                }
            }
            
            Spacer()
            
            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Subtitle("Instructions")
                BulletList([
                    "Make sure notifications are enabled for this app",
                    "After scheduling, exit the app or lock your device",
                    "The notification will appear in 5 seconds",
                    "Tap to open or use the action buttons",
                    "Video notifications work best on physical devices"
                ])
            }
            }
            .padding(20)
        }
        .navigationTitle("Video Notifications Demo")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.checkPermissionStatus()
            viewModel.setupNotificationActions()
        }
    }
}

/// Custom button component for demo actions
private struct DemoButton: View {
    let title: String
    let subtitle: String
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isEnabled ? .textPrimary : .textTertiary)
                
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(isEnabled ? Color.cardBackground : Color.backgroundSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isEnabled ? Color.accentColor.opacity(0.3) : Color.divider, lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

/// ViewModel managing the demo functionality and notification scheduling
@MainActor
final class PushNotificationsDemoViewModel: ObservableObject, @unchecked Sendable {
    @Published var permissionStatus: UNAuthorizationStatus = .notDetermined
    @Published var statusMessage: String = ""
    @Published var isScheduling: Bool = false
    
    var permissionStatusText: String {
        switch permissionStatus {
        case .notDetermined:
            return "Permission not requested"
        case .denied:
            return "Permission denied"
        case .authorized:
            return "Permission granted"
        case .provisional:
            return "Provisional permission"
        case .ephemeral:
            return "Ephemeral permission"
        @unknown default:
            return "Unknown status"
        }
    }
    
    var permissionStatusIcon: String {
        switch permissionStatus {
        case .authorized, .provisional:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        default:
            return "questionmark.circle.fill"
        }
    }
    
    var permissionStatusColor: Color {
        switch permissionStatus {
        case .authorized, .provisional:
            return .success
        case .denied:
            return .error
        default:
            return .warning
        }
    }
    
    var canScheduleNotifications: Bool {
        return permissionStatus == .authorized || permissionStatus == .provisional
    }
    
    func checkPermissionStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionStatus = settings.authorizationStatus
    }
    
    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [
                .alert, .sound, .badge, .provisional
            ])
            
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
                statusMessage = "✅ Permission granted successfully!"
            } else {
                statusMessage = "❌ Permission denied by user"
            }
            
            await checkPermissionStatus()
        } catch {
            statusMessage = "❌ Error requesting permission: \(error.localizedDescription)"
        }
    }
    
    func setupNotificationActions() {
        let playAction = UNNotificationAction(
            identifier: "PLAY_ACTION",
            title: "▶️ Play",
            options: [.foreground]
        )
        
        let pauseAction = UNNotificationAction(
            identifier: "PAUSE_ACTION",
            title: "⏸️ Pause",
            options: []
        )
        
        let shareAction = UNNotificationAction(
            identifier: "SHARE_ACTION",
            title: "📤 Share",
            options: [.foreground]
        )
        
        let videoCategory = UNNotificationCategory(
            identifier: "VIDEO_CATEGORY",
            actions: [playAction, pauseAction, shareAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([videoCategory])
    }
    
    func scheduleVideoNotification() async {
        guard canScheduleNotifications else { return }
        
        isScheduling = true
        statusMessage = "📹 Scheduling video notification..."
        
        let content = UNMutableNotificationContent()
        content.title = "Video Message Received"
        content.body = "📹 Use Push Notification Console to send real video notifications"
        content.sound = .default
        content.categoryIdentifier = "VIDEO_CATEGORY"
        
        configureNotificationContent(content)
        
        content.userInfo.merge([
            "demo_type": "remote_push_simulation",
            "message_id": "demo_local_\(Date().timeIntervalSince1970)",
            "notification_type": "local_demo"
        ]) { (_, new) in new }
        
        await scheduleNotification(content: content, identifier: "video_notification")
        
        isScheduling = false
        statusMessage = "✅ Video notification scheduled! Exit the app to see it."
    }
    
    func scheduleLocalVideoNotification() async {
        guard canScheduleNotifications else { return }
        
        isScheduling = true
        statusMessage = "🎬 Scheduling local video notification..."
        
        let content = UNMutableNotificationContent()
        content.title = "Rich Media Demo"
        content.body = "📱 Notification with media attachment"
        content.sound = .default
        content.categoryIdentifier = "VIDEO_CATEGORY"
        
        configureNotificationContent(content)
        
        do {
            let imageData = createDemoImage()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("demo_image.png")
            try imageData.write(to: tempURL)
            
            let attachment = try UNNotificationAttachment(
                identifier: "demo_image",
                url: tempURL,
                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]
            )
            content.attachments = [attachment]
        } catch {
            // Silent fail
        }
        
        content.userInfo.merge([
            "media_type": "image",
            "demo": true
        ]) { (_, new) in new }
        
        await scheduleNotification(content: content, identifier: "local_image_notification")
        
        isScheduling = false
        statusMessage = "✅ Rich media notification scheduled!"
    }
    
    private func createDemoImage() -> Data {
        let size = CGSize(width: 300, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            // Create a gradient background
            let colors = [UIColor.systemBlue.cgColor, UIColor.systemPurple.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
            
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint.zero,
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
            
            // Add text
            let text = "📱 Rich Media\nNotification Demo"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    return style
                }()
            ]
            
            let textRect = CGRect(x: 20, y: 60, width: size.width - 40, height: 80)
            text.draw(in: textRect, withAttributes: attributes)
        }
        
        return image.pngData() ?? Data()
    }
    
    private func configureNotificationContent(_ content: UNMutableNotificationContent) {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            content.threadIdentifier = bundleIdentifier
        }
        content.userInfo["app_id"] = Bundle.main.bundleIdentifier
    }
    

    private func createDemoVideoFrame() -> Data {
        let size = CGSize(width: 400, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { context in
            // Create a video-like gradient background
            let colors = [UIColor.systemPurple.cgColor, UIColor.systemBlue.cgColor, UIColor.systemTeal.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.0, 0.5, 1.0])!

            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint.zero,
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            // Add a play button icon
            let playButton = UIBezierPath()
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius: CGFloat = 40

            // Draw circle background
            context.cgContext.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
            context.cgContext.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

            // Draw play triangle
            context.cgContext.setFillColor(UIColor.black.cgColor)
            let triangleSize: CGFloat = 20
            playButton.move(to: CGPoint(x: center.x - triangleSize / 2, y: center.y - triangleSize / 2))
            playButton.addLine(to: CGPoint(x: center.x - triangleSize / 2, y: center.y + triangleSize / 2))
            playButton.addLine(to: CGPoint(x: center.x + triangleSize / 2, y: center.y))
            playButton.close()
            playButton.fill()

            // Add text
            let text = "📹 Demo Video\nClick to Play"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    return style
                }()
            ]

            let textRect = CGRect(x: 20, y: 50, width: size.width - 40, height: 50)
            text.draw(in: textRect, withAttributes: attributes)
        }

        return image.pngData() ?? Data()
    }

    func scheduleInteractiveRichMediaNotification() async {
        guard canScheduleNotifications else { return }
        
        isScheduling = true
        statusMessage = "🎨 Creating interactive rich media notification..."
        
        let content = UNMutableNotificationContent()
        content.title = "🎨 Rich Media Interactive"
        content.body = "Beautiful custom content with actions!"
        content.sound = .default
        content.categoryIdentifier = "VIDEO_CATEGORY"
        
        configureNotificationContent(content)
        
        await createActualVideoFile(content: content)
        
        content.userInfo = [
            "demo_type": "interactive_rich_media",
            "interactive": true,
            "notification_type": "rich_media"
        ]
        
        await scheduleNotification(content: content, identifier: "interactive_rich_media_notification")
        
        isScheduling = false
        statusMessage = "✅ Interactive rich media notification scheduled! Try the action buttons."
    }
    
    
    private func attachVideoToNotification(content: UNMutableNotificationContent, videoURLString: String) async {
        guard let videoURL = URL(string: videoURLString) else {
                return
        }
        
        do {
            
            // Create URLSession with longer timeout for demo
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60.0
            config.timeoutIntervalForResource = 60.0
            let session = URLSession(configuration: config)
            
            let startTime = Date()
            
            // Download video data
            let (data, response) = try await session.data(from: videoURL)
            
            let _ = Date().timeIntervalSince(startTime)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return
            }
            
            // Create temporary file
            let tempDirectory = FileManager.default.temporaryDirectory
            let fileExtension = videoURL.pathExtension.isEmpty ? "mp4" : videoURL.pathExtension
            let videoFileName = "local_video_\(UUID().uuidString).\(fileExtension)"
            let tempVideoURL = tempDirectory.appendingPathComponent(videoFileName)
            
            
            // Write data to temporary file
            try data.write(to: tempVideoURL)
            
            // Create notification attachment
            let attachment = try UNNotificationAttachment(
                identifier: "video_attachment",
                url: tempVideoURL,
                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.movie"]
            )
            
            
            // Update notification content
            content.attachments = [attachment]
            content.body = "📹 Video notification with \(fileExtension.uppercased()) content"
            
        } catch {
            content.body = "📱 Video notification (download failed: \(error.localizedDescription))"
        }
    }
    
    private func scheduleNotification(content: UNMutableNotificationContent, identifier: String) async {
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let finalIdentifier = "\(identifier)_\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(
            identifier: finalIdentifier,
            content: content,
            trigger: trigger
        )
        
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            
        } catch {
            statusMessage = "❌ Failed to schedule notification: \(error.localizedDescription)"
        }
    }
    
    private func createActualVideoFile(content: UNMutableNotificationContent) async {
        
        do {
            let tempDirectory = FileManager.default.temporaryDirectory
            let videoFileName = "demo_video_\(UUID().uuidString).mp4"
            let tempVideoURL = tempDirectory.appendingPathComponent(videoFileName)
            
            // Create an actual MP4 video file using AVFoundation
            let success = await generateMP4Video(at: tempVideoURL)
            
            if success {
                // Create notification attachment
                let attachment = try UNNotificationAttachment(
                    identifier: "video_attachment",
                    url: tempVideoURL,
                    options: [UNNotificationAttachmentOptionsTypeHintKey: "public.mpeg-4"]
                )
                
                
                // Update notification content
                content.attachments = [attachment]
                content.body = "📹 Video notification with MP4 content"
            } else {
                content.body = "📱 Video notification (video generation failed)"
            }
            
        } catch {
            content.body = "📱 Video notification (attachment creation failed)"
        }
    }
    
    private func generateMP4Video(at url: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            Task {
                await self.performVideoGeneration(at: url, continuation: continuation)
            }
        }
    }
    
    private func performVideoGeneration(at url: URL, continuation: CheckedContinuation<Bool, Never>) async {
        // Create a video writer
        guard let videoWriter = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            continuation.resume(returning: false)
            return
        }
        
        // Video settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 480,
            AVVideoHeightKey: 360,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1000000
            ]
        ]
        
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 480,
                kCVPixelBufferHeightKey as String: 360
            ]
        )
        
        videoWriter.add(videoInput)
        
        guard videoWriter.startWriting() else {
            continuation.resume(returning: false)
            return
        }
        
        videoWriter.startSession(atSourceTime: .zero)
        
        // Create a simple 2-second video
        let totalFrames = 60 // 2 seconds at 30 FPS
        
        await Task.detached {
            for frameIndex in 0..<totalFrames {
                let frameTime = CMTime(value: Int64(frameIndex), timescale: 30)
                
                while !videoInput.isReadyForMoreMediaData {
                    try? await Task.sleep(nanoseconds: 10_000_000) // Wait 10ms
                }
                
                if let pixelBuffer = self.createPixelBuffer(frameIndex: frameIndex, totalFrames: totalFrames) {
                    pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: frameTime)
                }
            }
            
            videoInput.markAsFinished()
            
            await withCheckedContinuation { finishContinuation in
                videoWriter.finishWriting {
                    finishContinuation.resume()
                }
            }
            
            let success = videoWriter.status == .completed
            continuation.resume(returning: success)
        }.value
    }
    
    nonisolated private func createPixelBuffer(frameIndex: Int, totalFrames: Int) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 480,
            kCVPixelBufferHeightKey as String: 360
        ] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 480, 360, kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: 480,
            height: 360,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        
        if let context = context {
            // Animate colors based on frame
            let progress = Float(frameIndex) / Float(totalFrames)
            let hue = progress * 360.0
            let color = UIColor(hue: CGFloat(hue/360.0), saturation: 1.0, brightness: 1.0, alpha: 1.0)
            
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 480, height: 360))
            
            // Add text
            let text = "📹 Frame \(frameIndex + 1)/\(totalFrames)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (480 - textSize.width) / 2,
                y: (360 - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            UIGraphicsPushContext(context)
            text.draw(in: textRect, withAttributes: attributes)
            UIGraphicsPopContext()
        }
        
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return buffer
    }
}
