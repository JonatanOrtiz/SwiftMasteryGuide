//
//  PushNotificationsVideoDemoView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 21/08/25.
//

import SwiftUI
import UserNotifications
import AVFoundation

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
                    
                    // Interactive Video Notification
                    DemoButton(
                        title: "🎮 Interactive Video Notification",
                        subtitle: "With custom actions (Play/Pause/Share)",
                        isEnabled: viewModel.canScheduleNotifications && !viewModel.isScheduling
                    ) {
                        Task {
                            await viewModel.scheduleInteractiveVideoNotification()
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
                    
                    // Fallback Test
                    DemoButton(
                        title: "⚠️ Test Download Failure",
                        subtitle: "Simulates network error fallback",
                        isEnabled: viewModel.canScheduleNotifications && !viewModel.isScheduling
                    ) {
                        Task {
                            await viewModel.scheduleFailureTestNotification()
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
final class PushNotificationsDemoViewModel: ObservableObject {
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
        print("🔍 [checkPermissionStatus] Starting permission check...")
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionStatus = settings.authorizationStatus
        print("🔍 [checkPermissionStatus] Permission status: \(permissionStatus.rawValue) (\(permissionStatusText))")
        print("🔍 [checkPermissionStatus] Alert setting: \(settings.alertSetting.rawValue)")
        print("🔍 [checkPermissionStatus] Sound setting: \(settings.soundSetting.rawValue)")
        print("🔍 [checkPermissionStatus] Badge setting: \(settings.badgeSetting.rawValue)")
        
        // Debug app icon info
        if let appIconName = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
            print("🔍 [checkPermissionStatus] App icon file: \(appIconName)")
        }
        if let iconFiles = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFiles") as? [String] {
            print("🔍 [checkPermissionStatus] App icon files: \(iconFiles)")
        }
        if let iconDict = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any] {
            print("🔍 [checkPermissionStatus] App icon dict: \(iconDict)")
        }
        
        // Check bundle identifier
        print("🔍 [checkPermissionStatus] Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
    }
    
    func requestPermission() async {
        print("🔐 [requestPermission] Starting permission request...")
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [
                .alert, .sound, .badge, .provisional
            ])
            
            print("🔐 [requestPermission] Permission granted: \(granted)")
            
            if granted {
                print("🔐 [requestPermission] Registering for remote notifications...")
                UIApplication.shared.registerForRemoteNotifications()
                statusMessage = "✅ Permission granted successfully!"
            } else {
                print("🔐 [requestPermission] Permission denied by user")
                statusMessage = "❌ Permission denied by user"
            }
            
            await checkPermissionStatus()
        } catch {
            print("🔐 [requestPermission] Error requesting permission: \(error)")
            statusMessage = "❌ Error requesting permission: \(error.localizedDescription)"
        }
    }
    
    func setupNotificationActions() {
        print("🎬 [setupNotificationActions] Setting up notification actions...")
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
        print("🎬 [setupNotificationActions] Notification actions set up successfully")
    }
    
    func scheduleVideoNotification() async {
        print("📹 [scheduleVideoNotification] Starting video notification scheduling...")
        print("📹 [scheduleVideoNotification] Can schedule notifications: \(canScheduleNotifications)")
        print("📹 [scheduleVideoNotification] Permission status: \(permissionStatus)")
        
        guard canScheduleNotifications else { 
            print("📹 [scheduleVideoNotification] Cannot schedule - insufficient permissions")
            return 
        }
        
        isScheduling = true
        statusMessage = "📹 Scheduling video notification..."
        print("📹 [scheduleVideoNotification] Creating notification content...")
        
        let content = UNMutableNotificationContent()
        content.title = "Video Message Received"
        content.body = "📹 Tap to view your video message"
        content.sound = .default
        content.categoryIdentifier = "VIDEO_CATEGORY"
        
        // Configure notification for proper icon display
        configureNotificationContent(content)
        
        // This simulates what would happen with a remote push notification
        // The Service Extension would handle the video download automatically
        print("📹 [scheduleVideoNotification] This simulates a remote push notification...")
        content.body = "📹 Use Push Notification Console to send real video notifications"
        
        // Add metadata for tracking
        content.userInfo.merge([
            "demo_type": "remote_push_simulation",
            "message_id": "demo_local_\(Date().timeIntervalSince1970)",
            "notification_type": "local_demo"
        ]) { (_, new) in new }
        
        print("📹 [scheduleVideoNotification] Content created:")
        print("   Title: \(content.title)")
        print("   Body: \(content.body)")
        print("   Category: \(content.categoryIdentifier)")
        print("   UserInfo: \(content.userInfo)")
        
        await scheduleNotification(content: content, identifier: "video_notification")
        
        isScheduling = false
        statusMessage = "✅ Video notification scheduled! Exit the app to see it."
        print("📹 [scheduleVideoNotification] Video notification scheduling completed")
    }
    
    func scheduleLocalVideoNotification() async {
        print("🎬 [scheduleLocalVideoNotification] Starting local video notification scheduling...")
        print("🎬 [scheduleLocalVideoNotification] Can schedule notifications: \(canScheduleNotifications)")
        
        guard canScheduleNotifications else { 
            print("🎬 [scheduleLocalVideoNotification] Cannot schedule - insufficient permissions")
            return 
        }
        
        isScheduling = true
        statusMessage = "🎬 Scheduling local video notification..."
        print("🎬 [scheduleLocalVideoNotification] Creating notification content...")
        
        // Create notification content with actual image attachment (since videos require Service Extension)
        let content = UNMutableNotificationContent()
        content.title = "Rich Media Demo"
        content.body = "📱 Notification with media attachment"
        content.sound = .default
        content.categoryIdentifier = "VIDEO_CATEGORY"
        
        // Configure notification for proper icon display
        configureNotificationContent(content)
        
        // Try to add an image attachment as a simpler demo
        do {
            // Create a simple programmatic image
            let imageData = createDemoImage()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("demo_image.png")
            try imageData.write(to: tempURL)
            
            let attachment = try UNNotificationAttachment(
                identifier: "demo_image",
                url: tempURL,
                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]
            )
            content.attachments = [attachment]
            print("🎬 [scheduleLocalVideoNotification] Image attachment created successfully")
        } catch {
            print("🎬 [scheduleLocalVideoNotification] Failed to create image attachment: \(error)")
        }
        
        content.userInfo.merge([
            "media_type": "image",
            "demo": true
        ]) { (_, new) in new }
        
        print("🎬 [scheduleLocalVideoNotification] Content created:")
        print("   Title: \(content.title)")
        print("   Body: \(content.body)")
        print("   Category: \(content.categoryIdentifier)")
        print("   Attachments: \(content.attachments.count)")
        print("   UserInfo: \(content.userInfo)")
        
        await scheduleNotification(content: content, identifier: "local_image_notification")
        
        isScheduling = false
        statusMessage = "✅ Rich media notification scheduled!"
        print("🎬 [scheduleLocalVideoNotification] Rich media notification scheduling completed")
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
        // Set bundle identifier to help with icon display
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            content.threadIdentifier = bundleIdentifier
        }
        
        // Force the app icon by setting the app identifier
        content.userInfo["app_id"] = Bundle.main.bundleIdentifier
        
        print("🔧 [configureNotificationContent] Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        print("🔧 [configureNotificationContent] Thread ID: \(content.threadIdentifier)")
    }
    
    func scheduleInteractiveVideoNotification() async {
        print("🎮 [scheduleInteractiveVideoNotification] Starting interactive video notification scheduling...")
        print("🎮 [scheduleInteractiveVideoNotification] Can schedule notifications: \(canScheduleNotifications)")
        
        guard canScheduleNotifications else { 
            print("🎮 [scheduleInteractiveVideoNotification] Cannot schedule - insufficient permissions")
            return 
        }
        
        isScheduling = true
        statusMessage = "🎮 Scheduling interactive notification..."
        print("🎮 [scheduleInteractiveVideoNotification] Creating notification content...")
        
        let content = UNMutableNotificationContent()
        content.title = "Interactive Video"
        content.body = "🎮 Try the action buttons below!"
        content.sound = .default
        content.categoryIdentifier = "VIDEO_CATEGORY"
        
        // This simulates what would happen with a remote push notification
        // The Service Extension would handle the video download automatically
        print("🎮 [scheduleInteractiveVideoNotification] This simulates a remote push notification...")
        content.body = "🎮 Use Push Notification Console to send interactive video notifications"

        content.userInfo = [
            "demo_type": "remote_push_simulation",
            "interactive": true,
            "notification_type": "local_demo"
        ]
        
        print("🎮 [scheduleInteractiveVideoNotification] Content created:")
        print("   Title: \(content.title)")
        print("   Body: \(content.body)")
        print("   Category: \(content.categoryIdentifier)")
        print("   UserInfo: \(content.userInfo)")
        
        await scheduleNotification(content: content, identifier: "interactive_video_notification")
        
        isScheduling = false
        statusMessage = "✅ Interactive video notification scheduled! Try the action buttons."
        print("🎮 [scheduleInteractiveVideoNotification] Interactive video notification scheduling completed")
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
        print("🎨 [scheduleInteractiveRichMediaNotification] Starting interactive rich media notification scheduling...")
        print("🎨 [scheduleInteractiveRichMediaNotification] Can schedule notifications: \(canScheduleNotifications)")
        
        guard canScheduleNotifications else { 
            print("🎨 [scheduleInteractiveRichMediaNotification] Cannot schedule - insufficient permissions")
            return 
        }
        
        isScheduling = true
        statusMessage = "🎨 Creating interactive rich media notification..."
        print("🎨 [scheduleInteractiveRichMediaNotification] Creating notification content...")
        
        let content = UNMutableNotificationContent()
        content.title = "🎨 Rich Media Interactive"
        content.body = "Beautiful custom content with actions!"
        content.sound = .default
        content.categoryIdentifier = "VIDEO_CATEGORY"
        
        // Configure notification for proper icon display
        configureNotificationContent(content)
        
        // Create actual video file for rich media content
        print("🎨 [scheduleInteractiveRichMediaNotification] Creating actual video file...")
        await createActualVideoFile(content: content)
        
        content.userInfo = [
            "demo_type": "interactive_rich_media",
            "interactive": true,
            "notification_type": "rich_media"
        ]
        
        print("🎨 [scheduleInteractiveRichMediaNotification] Content created:")
        print("   Title: \(content.title)")
        print("   Body: \(content.body)")
        print("   Category: \(content.categoryIdentifier)")
        print("   UserInfo: \(content.userInfo)")
        
        await scheduleNotification(content: content, identifier: "interactive_rich_media_notification")
        
        isScheduling = false
        statusMessage = "✅ Interactive rich media notification scheduled! Try the action buttons."
        print("🎨 [scheduleInteractiveRichMediaNotification] Interactive rich media notification scheduling completed")
    }
    
    func scheduleFailureTestNotification() async {
        print("⚠️ [scheduleFailureTestNotification] Starting failure test notification scheduling...")
        print("⚠️ [scheduleFailureTestNotification] Can schedule notifications: \(canScheduleNotifications)")
        
        guard canScheduleNotifications else { 
            print("⚠️ [scheduleFailureTestNotification] Cannot schedule - insufficient permissions")
            return 
        }
        
        isScheduling = true
        statusMessage = "⚠️ Scheduling failure test notification..."
        print("⚠️ [scheduleFailureTestNotification] Creating notification content...")
        
        let content = UNMutableNotificationContent()
        content.title = "Network Error Test"
        content.body = "Testing fallback behavior"
        content.sound = .default
        content.categoryIdentifier = "VIDEO_CATEGORY"
        
        // This simulates what would happen with a remote push notification
        // that has mutable-content flag and gets processed by Service Extension
        content.userInfo = [
            "video_url": "https://test.com.zzz",
            "mutable-content": 1,
            "notification_type": "remote_push_simulation"
        ]
        
        print("⚠️ [scheduleFailureTestNotification] Content created:")
        print("   Title: \(content.title)")
        print("   Body: \(content.body)")
        print("   Category: \(content.categoryIdentifier)")
        print("   UserInfo: \(content.userInfo)")
        
        await scheduleNotification(content: content, identifier: "failure_test_notification")
        
        isScheduling = false
        statusMessage = "✅ Failure test scheduled! Should show fallback content."
        print("⚠️ [scheduleFailureTestNotification] Failure test notification scheduling completed")
    }
    
    private func attachVideoToNotification(content: UNMutableNotificationContent, videoURLString: String) async {
        guard let videoURL = URL(string: videoURLString) else {
            print("📹 [attachVideoToNotification] ❌ Invalid video URL: \(videoURLString)")
            return
        }
        
        do {
            print("📹 [attachVideoToNotification] 📥 Starting video download from: \(videoURL)")
            
            // Create URLSession with longer timeout for demo
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60.0
            config.timeoutIntervalForResource = 60.0
            let session = URLSession(configuration: config)
            
            let startTime = Date()
            
            // Download video data
            let (data, response) = try await session.data(from: videoURL)
            
            let downloadTime = Date().timeIntervalSince(startTime)
            print("📹 [attachVideoToNotification] ✅ Download completed in \(String(format: "%.2f", downloadTime))s")
            print("📹 [attachVideoToNotification] 📊 Data size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .binary))")
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("📹 [attachVideoToNotification] ❌ HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            
            // Create temporary file
            let tempDirectory = FileManager.default.temporaryDirectory
            let fileExtension = videoURL.pathExtension.isEmpty ? "mp4" : videoURL.pathExtension
            let videoFileName = "local_video_\(UUID().uuidString).\(fileExtension)"
            let tempVideoURL = tempDirectory.appendingPathComponent(videoFileName)
            
            print("📹 [attachVideoToNotification] 💾 Writing to: \(tempVideoURL.lastPathComponent)")
            
            // Write data to temporary file
            try data.write(to: tempVideoURL)
            
            // Create notification attachment
            let attachment = try UNNotificationAttachment(
                identifier: "video_attachment",
                url: tempVideoURL,
                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.movie"]
            )
            
            print("📹 [attachVideoToNotification] 🎥 Video attachment created successfully")
            
            // Update notification content
            content.attachments = [attachment]
            content.body = "📹 Video notification with \(fileExtension.uppercased()) content"
            
        } catch {
            print("📹 [attachVideoToNotification] ❌ Download failed: \(error)")
            print("📹 [attachVideoToNotification] ❌ Error details: \(error.localizedDescription)")
            if let urlError = error as? URLError {
                print("📹 [attachVideoToNotification] ❌ URLError code: \(urlError.code.rawValue)")
                print("📹 [attachVideoToNotification] ❌ URLError description: \(urlError.localizedDescription)")
            }
            content.body = "📱 Video notification (download failed: \(error.localizedDescription))"
        }
    }
    
    private func scheduleNotification(content: UNMutableNotificationContent, identifier: String) async {
        print("⏰ [scheduleNotification] Starting notification scheduling...")
        print("⏰ [scheduleNotification] Identifier: \(identifier)")
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let finalIdentifier = "\(identifier)_\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(
            identifier: finalIdentifier,
            content: content,
            trigger: trigger
        )
        
        print("⏰ [scheduleNotification] Request details:")
        print("   Final identifier: \(finalIdentifier)")
        print("   Trigger interval: 5 seconds")
        print("   Repeats: false")
        
        do {
            print("⏰ [scheduleNotification] Adding notification request to UNUserNotificationCenter...")
            try await UNUserNotificationCenter.current().add(request)
            print("⏰ [scheduleNotification] ✅ Notification successfully scheduled!")
            
            // Check pending notifications
            let pendingRequests = await UNUserNotificationCenter.current().pendingNotificationRequests()
            print("⏰ [scheduleNotification] Total pending notifications: \(pendingRequests.count)")
            for pendingRequest in pendingRequests {
                print("   - \(pendingRequest.identifier): \(pendingRequest.content.title)")
            }
            
            // Check delivered notifications
            let deliveredNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
            print("⏰ [scheduleNotification] Total delivered notifications: \(deliveredNotifications.count)")
            for deliveredNotification in deliveredNotifications {
                print("   - \(deliveredNotification.request.identifier): \(deliveredNotification.request.content.title)")
            }
        } catch {
            print("⏰ [scheduleNotification] ❌ Failed to schedule notification: \(error)")
            statusMessage = "❌ Failed to schedule notification: \(error.localizedDescription)"
        }
    }
    
    private func createActualVideoFile(content: UNMutableNotificationContent) async {
        print("📹 [createActualVideoFile] Creating real MP4 video file...")
        
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
                
                print("📹 [createActualVideoFile] ✅ Real video attachment created successfully")
                
                // Update notification content
                content.attachments = [attachment]
                content.body = "📹 Video notification with MP4 content"
            } else {
                print("📹 [createActualVideoFile] ❌ Failed to generate MP4 video")
                content.body = "📱 Video notification (video generation failed)"
            }
            
        } catch {
            print("📹 [createActualVideoFile] ❌ Failed to create video attachment: \(error)")
            content.body = "📱 Video notification (attachment creation failed)"
        }
    }
    
    private func generateMP4Video(at url: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            
            // Create a video writer
            guard let videoWriter = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
                print("📹 [generateMP4Video] ❌ Could not create AVAssetWriter")
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
                print("📹 [generateMP4Video] ❌ Could not start writing")
                continuation.resume(returning: false)
                return
            }
            
            videoWriter.startSession(atSourceTime: .zero)
            
            // Create a simple 2-second video
            let frameDuration = CMTime(value: 1, timescale: 30) // 30 FPS
            let totalFrames = 60 // 2 seconds at 30 FPS
            
            DispatchQueue.global(qos: .background).async {
                for frameIndex in 0..<totalFrames {
                    let frameTime = CMTime(value: Int64(frameIndex), timescale: 30)
                    
                    while !videoInput.isReadyForMoreMediaData {
                        usleep(10000) // Wait 10ms
                    }
                    
                    if let pixelBuffer = self.createPixelBuffer(frameIndex: frameIndex, totalFrames: totalFrames) {
                        pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: frameTime)
                    }
                }
                
                videoInput.markAsFinished()
                
                videoWriter.finishWriting {
                    let success = videoWriter.status == .completed
                    print("📹 [generateMP4Video] Video generation completed. Success: \(success)")
                    if !success, let error = videoWriter.error {
                        print("📹 [generateMP4Video] ❌ Video writer error: \(error)")
                    }
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    private func createPixelBuffer(frameIndex: Int, totalFrames: Int) -> CVPixelBuffer? {
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
