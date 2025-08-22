//
//  PushNotificationsVideoGuideView.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 21/08/25.
//

import SwiftUI
import UserNotifications

/// A comprehensive guide explaining how to implement Push Notifications with Video (Rich Media Notifications) in iOS.
/// Covers the complete implementation from requesting permissions to displaying custom notification content.
struct PushNotificationsVideoGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                NavigationLink(destination: PushNotificationsVideoDemoView()) {
                    Text("Schedule Rich Notification with Video")
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .accessibilityLabel("Open push notifications video demo")
                }

                Title("Push Notifications with Video (Rich Media Notifications)")

                Subtitle("What you'll build")
                BodyText("""
                A complete push notification system that supports rich media content including videos. You'll learn to implement Notification Service Extensions for downloading video content, Notification Content Extensions for custom UI, and proper fallback handling for failed downloads.
                """)

                Subtitle("Requirements")
                BulletList([
                    "iOS 10+ (UNUserNotificationCenter and Rich Notifications).",
                    "Physical device required for push notifications testing.",
                    "Apple Developer account for push notification certificates.",
                    "Frameworks: UserNotifications, UserNotificationsUI."
                ])

                DividerLine()

                Subtitle("1) Requesting Notification Permissions")
                BodyText("Start by requesting user permission for notifications with appropriate authorization options:")
                CodeBlock("""
                import UserNotifications

                class NotificationPermissionManager {
                    static let shared = NotificationPermissionManager()
                    
                    func requestPermission() async -> Bool {
                        let center = UNUserNotificationCenter.current()
                        
                        do {
                            let granted = try await center.requestAuthorization(options: [
                                .alert,
                                .sound,
                                .badge,
                                .provisional
                            ])
                            
                            if granted {
                                await registerForRemoteNotifications()
                            }
                            
                            return granted
                        } catch {
                            print("Failed to request notification permission: \\(error)")
                            return false
                        }
                    }
                    
                    @MainActor
                    private func registerForRemoteNotifications() {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                    
                    func checkPermissionStatus() async -> UNAuthorizationStatus {
                        let settings = await UNUserNotificationCenter.current().notificationSettings()
                        return settings.authorizationStatus
                    }
                }
                """)

                Subtitle("2) App Delegate Setup")
                BodyText("Configure your app delegate to handle device token registration and notification responses:")
                CodeBlock("""
                import UIKit
                import UserNotifications

                class AppDelegate: NSObject, UIApplicationDelegate {
                    func application(_ application: UIApplication, 
                                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
                        
                        UNUserNotificationCenter.current().delegate = self
                        return true
                    }
                    
                    func application(_ application: UIApplication, 
                                   didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
                        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
                        print("Device Token: \\(tokenString)")
                        
                        // Send this token to your server
                        Task {
                            await sendTokenToServer(tokenString)
                        }
                    }
                    
                    func application(_ application: UIApplication, 
                                   didFailToRegisterForRemoteNotificationsWithError error: Error) {
                        print("Failed to register for remote notifications: \\(error)")
                    }
                    
                    private func sendTokenToServer(_ token: String) async {
                        // Implement your server communication logic here
                        print("Sending token to server: \\(token)")
                    }
                }

                extension AppDelegate: UNUserNotificationCenterDelegate {
                    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                                              willPresent notification: UNNotification, 
                                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
                        // Show notification even when app is in foreground
                        completionHandler([.banner, .sound, .badge])
                    }
                    
                    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                                              didReceive response: UNNotificationResponse, 
                                              withCompletionHandler completionHandler: @escaping () -> Void) {
                        // Handle notification tap
                        let userInfo = response.notification.request.content.userInfo
                        handleNotificationTap(userInfo: userInfo)
                        completionHandler()
                    }
                    
                    private func handleNotificationTap(userInfo: [AnyHashable: Any]) {
                        print("Notification tapped with userInfo: \\(userInfo)")
                        // Navigate to specific screen based on notification data
                    }
                }
                """)

                Subtitle("3) Notification Service Extension")
                BodyText("Create a Notification Service Extension to download and attach video content. This runs in the background and modifies notification content before display:")
                CodeBlock("""
                import UserNotifications
                import Foundation
                import SwiftUI

                class NotificationService: UNNotificationServiceExtension {
                    
                    var contentHandler: ((UNNotificationContent) -> Void)?
                    var bestAttemptContent: UNMutableNotificationContent?
                    
                    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
                        self.contentHandler = contentHandler
                        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
                        
                        guard let bestAttemptContent = bestAttemptContent else {
                            contentHandler(request.content)
                            return
                        }
                        
                        // Extract video URL from notification payload
                        guard let videoURLString = bestAttemptContent.userInfo["video_url"] as? String,
                              let videoURL = URL(string: videoURLString) else {
                            // Still show notification without video
                            bestAttemptContent.body = "📱 Notification received (no video URL)"
                            contentHandler(bestAttemptContent)
                            return
                        }
                        
                        // Download video asynchronously with timeout
                        Task {
                            await downloadAndAttachVideo(from: videoURL, to: bestAttemptContent)
                            contentHandler(bestAttemptContent)
                        }
                    }
                    
                    override func serviceExtensionTimeWillExpire() {
                        // Called when extension is about to be terminated (30 second limit)
                        if let contentHandler = contentHandler,
                           let bestAttemptContent = bestAttemptContent {
                            
                            // Provide fallback content if download didn't complete
                            bestAttemptContent.body = "📱 Video notification (download timed out)"
                            bestAttemptContent.userInfo["download_status"] = "timeout"
                            
                            contentHandler(bestAttemptContent)
                        }
                    }
                    
                    private func downloadAndAttachVideo(from url: URL, to content: UNMutableNotificationContent) async {
                        do {
                            // Create URLSession with timeout configuration (25 seconds to leave buffer)
                            let config = URLSessionConfiguration.default
                            config.timeoutIntervalForRequest = 25.0
                            config.timeoutIntervalForResource = 25.0
                            config.urlCache = nil // Don't cache to save memory
                            let session = URLSession(configuration: config)
                            
                            let startTime = Date()
                            
                            // Download video data
                            let (data, response) = try await session.data(from: url)
                            
                            let downloadTime = Date().timeIntervalSince(startTime)

                            // Validate response
                            guard let httpResponse = response as? HTTPURLResponse else {
                                throw NotificationServiceError.invalidResponse
                            }
                            
                            guard httpResponse.statusCode == 200 else {
                                throw NotificationServiceError.httpError(httpResponse.statusCode)
                            }
                            
                            // Validate content type
                            let contentType = httpResponse.mimeType ?? "unknown"

                            guard contentType.hasPrefix("video/") else {
                                return
                            }
                            
                            // Create temporary file with proper extension
                            let tempDirectory = FileManager.default.temporaryDirectory
                            let fileExtension = determineFileExtension(from: url, contentType: contentType)
                            let videoFileName = "notification_video_\\(UUID().uuidString).\\(fileExtension)"
                            let tempVideoURL = tempDirectory.appendingPathComponent(videoFileName)
                            
                            // Write data to temporary file
                            try data.write(to: tempVideoURL)
                            
                            // Verify file was written
                            let attributes = try FileManager.default.attributesOfItem(atPath: tempVideoURL.path)
                            let fileSize = attributes[.size] as? Int64 ?? 0

                            // Create notification attachment
                            let attachmentOptions: [String: Any] = [
                                UNNotificationAttachmentOptionsTypeHintKey: determineTypeHint(from: contentType)
                            ]
                            
                            let attachment = try UNNotificationAttachment(
                                identifier: "video_attachment",
                                url: tempVideoURL,
                                options: attachmentOptions
                            )

                            // Update notification content
                            content.attachments = [attachment]
                            content.body = "📹 Video notification with \\(fileExtension.uppercased()) content"
                            content.userInfo["download_status"] = "success"
                            content.userInfo["file_size"] = fileSize
                            content.userInfo["download_time"] = downloadTime
                            
                        } catch {
                            // Provide fallback content
                            content.body = "📱 Video notification (download failed)"
                            content.userInfo["download_status"] = "failed"
                            content.userInfo["error"] = error.localizedDescription
                            
                            // Try to provide a fallback image instead
                            await addFallbackImage(to: content)
                        }
                    }
                    
                    private func determineFileExtension(from url: URL, contentType: String) -> String {
                        // Try to get extension from URL first
                        let urlExtension = url.pathExtension.lowercased()
                        if !urlExtension.isEmpty && ["mp4", "mov", "m4v", "avi", "mkv"].contains(urlExtension) {
                            return urlExtension
                        }
                        
                        // Fall back to content type
                        switch contentType.lowercased() {
                        case "video/mp4":
                            return "mp4"
                        case "video/quicktime":
                            return "mov"
                        case "video/x-msvideo":
                            return "avi"
                        case "video/x-matroska":
                            return "mkv"
                        default:
                            return "mp4" // Default fallback
                        }
                    }
                    
                    private func determineTypeHint(from contentType: String) -> String {
                        switch contentType.lowercased() {
                        case "video/mp4":
                            return "public.mpeg-4"
                        case "video/quicktime":
                            return "com.apple.quicktime-movie"
                        case "video/x-msvideo":
                            return "public.avi"
                        default:
                            return "public.movie"
                        }
                    }
                    
                    private func addFallbackImage(to content: UNMutableNotificationContent) async {
                        do {
                            // Create a simple fallback image programmatically
                            let imageData = createFallbackImage()
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("fallback_image.png")
                            try imageData.write(to: tempURL)
                            
                            let attachment = try UNNotificationAttachment(
                                identifier: "fallback_image",
                                url: tempURL,
                                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]
                            )
                            
                            content.attachments = [attachment]
                            content.body = "📱 Notification with fallback content"
                            
                        } catch {
                            // Silent fail if fallback image creation fails
                        }
                    }
                    
                    private func createFallbackImage() -> Data {
                        let size = CGSize(width: 300, height: 200)
                        let renderer = UIGraphicsImageRenderer(size: size)
                        
                        let image = renderer.image { context in
                            // Create a red gradient background to indicate error
                            let colors = [UIColor.systemRed.cgColor, UIColor.systemOrange.cgColor]
                            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
                            
                            context.cgContext.drawLinearGradient(
                                gradient,
                                start: CGPoint.zero,
                                end: CGPoint(x: size.width, y: size.height),
                                options: []
                            )
                            
                            // Add text
                            let text = "⚠️ Video Download\\nFailed"
                            let attributes: [NSAttributedString.Key: Any] = [
                                .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                                .foregroundColor: UIColor.white,
                                .paragraphStyle: {
                                    let style = NSMutableParagraphStyle()
                                    style.alignment = .center
                                    return style
                                }()
                            ]
                            
                            let textRect = CGRect(x: 20, y: 70, width: size.width - 40, height: 60)
                            text.draw(in: textRect, withAttributes: attributes)
                        }
                        
                        return image.pngData() ?? Data()
                    }
                }

                // MARK: - Custom Errors

                enum NotificationServiceError: Error, LocalizedError {
                    case invalidResponse
                    case httpError(Int)
                    case unsupportedContentType(String)
                    case fileTooLarge(Int64)
                    
                    var errorDescription: String? {
                        switch self {
                        case .invalidResponse:
                            return "Invalid HTTP response"
                        case .httpError(let code):
                            return "HTTP error: \\(code)"
                        case .unsupportedContentType(let type):
                            return "Unsupported content type: \\(type)"
                        case .fileTooLarge(let size):
                            return "File too large: \\(ByteCountFormatter.string(fromByteCount: size, countStyle: .binary))"
                        }
                    }
                }
                """)

                Subtitle("4) Notification Content Extension")
                BodyText("Create a Notification Content Extension for custom UI with video playback controls:")
                CodeBlock("""
                import UIKit
                import UserNotifications
                import UserNotificationsUI
                import AVKit

                class NotificationViewController: UIViewController, UNNotificationContentExtension {
                    @IBOutlet weak var containerView: UIView!
                    @IBOutlet weak var titleLabel: UILabel!
                    @IBOutlet weak var bodyLabel: UILabel!
                    
                    private var playerViewController: AVPlayerViewController?
                    private var player: AVPlayer?
                    
                    override func viewDidLoad() {
                        super.viewDidLoad()
                        setupUI()
                    }
                    
                    private func setupUI() {
                        view.backgroundColor = .systemBackground
                        containerView.layer.cornerRadius = 12
                        containerView.clipsToBounds = true
                    }
                    
                    func didReceive(_ notification: UNNotification) {
                        // Update labels
                        titleLabel.text = notification.request.content.title
                        bodyLabel.text = notification.request.content.body
                        
                        // Setup video player if attachment exists
                        setupVideoPlayer(with: notification.request.content.attachments)
                    }
                    
                    private func setupVideoPlayer(with attachments: [UNNotificationAttachment]) {
                        guard let videoAttachment = attachments.first(where: { $0.identifier == "video_attachment" }) else {
                            return
                        }
                        
                        // Create AVPlayer with attachment URL
                        player = AVPlayer(url: videoAttachment.url)
                        
                        // Setup AVPlayerViewController
                        playerViewController = AVPlayerViewController()
                        playerViewController?.player = player
                        playerViewController?.showsPlaybackControls = true
                        playerViewController?.allowsPictureInPicturePlayback = false
                        
                        guard let playerViewController = playerViewController else { return }
                        
                        // Add as child view controller
                        addChild(playerViewController)
                        containerView.addSubview(playerViewController.view)
                        
                        // Setup constraints
                        playerViewController.view.translatesAutoresizingMaskIntoConstraints = false
                        NSLayoutConstraint.activate([
                            playerViewController.view.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 12),
                            playerViewController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                            playerViewController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                            playerViewController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                            playerViewController.view.heightAnchor.constraint(equalToConstant: 200)
                        ])
                        
                        playerViewController.didMove(toParent: self)
                    }
                    
                    func didReceive(_ response: UNNotificationResponse, 
                                   completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
                        // Handle user interactions
                        switch response.actionIdentifier {
                        case "PLAY_ACTION":
                            player?.play()
                            completion(.doNotDismiss)
                        case "PAUSE_ACTION":
                            player?.pause()
                            completion(.doNotDismiss)
                        default:
                            completion(.dismiss)
                        }
                    }
                    
                    deinit {
                        player?.pause()
                        player = nil
                    }
                }
                """)

                Subtitle("5) Notification Categories Setup")
                BodyText("Set up notification categories for your video notifications. This creates a clean notification without action buttons:")
                CodeBlock("""
                class NotificationActionsManager {
                    static let shared = NotificationActionsManager()
                    
                    func setupNotificationActions() {
                        // Simple category without action buttons for clean notifications
                        let videoCategory = UNNotificationCategory(
                            identifier: "VIDEO_CATEGORY",
                            actions: [],
                            intentIdentifiers: [],
                            options: []
                        )
                        
                        UNUserNotificationCenter.current().setNotificationCategories([videoCategory])
                    }
                }
                """)

                Subtitle("6) Demo View Implementation")
                BodyText("Create a comprehensive demo view to test push notification functionality with proper permission handling and video generation:")
                CodeBlock("""
                import SwiftUI
                import UserNotifications
                @preconcurrency import AVFoundation

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
                                    }
                                    
                                    if viewModel.permissionStatus != .authorized {
                                        Button("Request Notification Permission") {
                                            Task { await viewModel.requestPermission() }
                                        }
                                        .padding()
                                        .background(Color.accentColor)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                }
                                
                                // Demo Actions Section
                                VStack(spacing: 12) {
                                    DemoButton(
                                        title: "🖼️ Rich Media Notification",
                                        subtitle: "With image attachment",
                                        isEnabled: viewModel.canScheduleNotifications
                                    ) {
                                        Task { await viewModel.scheduleLocalVideoNotification() }
                                    }
                                    
                                    DemoButton(
                                        title: "🎨 Interactive Rich Media",
                                        subtitle: "Custom video with MP4 content",
                                        isEnabled: viewModel.canScheduleNotifications
                                    ) {
                                        Task { await viewModel.scheduleInteractiveRichMediaNotification() }
                                    }
                                }
                            }
                        }
                        .task {
                            await viewModel.checkPermissionStatus()
                            viewModel.setupNotificationActions()
                        }
                    }
                }

                @MainActor
                final class PushNotificationsDemoViewModel: ObservableObject, @unchecked Sendable {
                    @Published var permissionStatus: UNAuthorizationStatus = .notDetermined
                    @Published var statusMessage: String = ""
                    @Published var isScheduling: Bool = false
                    
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
                            }
                            
                            await checkPermissionStatus()
                        } catch {
                            statusMessage = "❌ Error requesting permission: \\(error.localizedDescription)"
                        }
                    }
                    
                    func setupNotificationActions() {
                        // Simple category without action buttons
                        let videoCategory = UNNotificationCategory(
                            identifier: "VIDEO_CATEGORY",
                            actions: [],
                            intentIdentifiers: [],
                            options: []
                        )
                        
                        UNUserNotificationCenter.current().setNotificationCategories([videoCategory])
                    }
                }
                """)

                Subtitle("7) App Entitlements Configuration")
                BodyText("Configure the required entitlements for your main app and notification service extension:")
                
                Subtitle("Main App Entitlements (SwiftMasteryGuide.entitlements)")
                CodeBlock("""
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>aps-environment</key>
                    <string>development</string>
                    <key>com.apple.security.application-groups</key>
                    <array>
                        <string>group.com.jonatanortiz.SwiftMasteryGuide</string>
                    </array>
                </dict>
                </plist>
                """)
                
                Subtitle("Notification Service Extension Entitlements")
                CodeBlock("""
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>com.apple.security.application-groups</key>
                    <array>
                        <string>com.jonatanortiz.SwiftMasteryGuide.NotificationServiceExtension</string>
                    </array>
                </dict>
                </plist>
                """)

                Subtitle("8) Testing with Local Notifications")
                BodyText("For testing purposes, create local notifications that simulate video push notifications:")
                CodeBlock("""
                class LocalVideoNotificationManager {
                    static let shared = LocalVideoNotificationManager()
                    
                    func scheduleTestVideoNotification() async {
                        let content = UNMutableNotificationContent()
                        content.title = "Video Notification Test"
                        content.body = "Testing rich media notification with video"
                        content.sound = .default
                        content.categoryIdentifier = "VIDEO_CATEGORY"
                        
                        // Add video URL to userInfo (simulating server payload)
                        content.userInfo = [
                            "video_url": "https://sample-videos.com/zip/10/mp4/SampleVideo_1280x720_1mb.mp4"
                        ]
                        
                        // Create trigger (5 seconds from now)
                        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                        
                        // Create request
                        let request = UNNotificationRequest(
                            identifier: "test_video_notification_\\(Date().timeIntervalSince1970)",
                            content: content,
                            trigger: trigger
                        )
                        
                        // Schedule notification
                        do {
                            try await UNUserNotificationCenter.current().add(request)
                            print("Test video notification scheduled successfully")
                        } catch {
                            print("Failed to schedule test notification: \\(error)")
                        }
                    }
                    
                    func scheduleLocalVideoNotification(with localVideoURL: URL) async {
                        let content = UNMutableNotificationContent()
                        content.title = "Local Video Notification"
                        content.body = "📹 Local video notification"
                        content.sound = .default
                        content.categoryIdentifier = "VIDEO_CATEGORY"
                        
                        do {
                            // Create attachment from local video
                            let attachment = try UNNotificationAttachment(
                                identifier: "local_video",
                                url: localVideoURL,
                                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.mpeg-4"]
                            )
                            content.attachments = [attachment]
                            
                            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
                            let request = UNNotificationRequest(
                                identifier: "local_video_\\(Date().timeIntervalSince1970)",
                                content: content,
                                trigger: trigger
                            )
                            
                            try await UNUserNotificationCenter.current().add(request)
                            print("Local video notification scheduled")
                        } catch {
                            print("Failed to create local video notification: \\(error)")
                        }
                    }
                }
                """)

                DividerLine()

                Subtitle("Push Notification Payload Example")
                BodyText("Structure your server-side push notification payload to include video URL and proper category:")
                CodeBlock("""
                {
                  "aps": {
                    "alert": {
                      "title": "New Video Message",
                      "body": "You have received a video message"
                    },
                    "sound": "default",
                    "badge": 1,
                    "category": "VIDEO_CATEGORY",
                    "mutable-content": 1
                  },
                  "video_url": "https://your-server.com/videos/notification_video.mp4",
                  "custom_data": {
                    "user_id": "12345",
                    "message_id": "msg_67890"
                  }
                }
                """)

                DividerLine()

                Subtitle("Setup Instructions")
                BulletList([
                    "Add Notification Service Extension target to your project.",
                    "Configure App Groups for data sharing between main app and extension.",
                    "Setup push notification certificates in Apple Developer Portal.",
                    "Configure entitlements files for both main app and extension.",
                    "Test on physical device using Apple Push Notification Console.",
                    "Implement proper error handling for network failures and timeouts.",
                    "Use Push Notification Console for sending real video notifications.",
                    "Local notifications are for demo purposes only."
                ])

                Subtitle("Security Considerations")
                BulletList([
                    "Validate video URLs before downloading to prevent malicious content.",
                    "Implement file size limits to prevent excessive downloads.",
                    "Use HTTPS URLs only for video content.",
                    "Sanitize and validate all notification payload data.",
                    "Implement timeout mechanisms for download operations."
                ])

                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .navigationTitle("How to Use")
        .navigationBarTitleDisplayMode(.inline)
    }
}