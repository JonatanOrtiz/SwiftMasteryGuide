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

                class NotificationService: UNNotificationServiceExtension {
                    var contentHandler: ((UNNotificationContent) -> Void)?
                    var bestAttemptContent: UNMutableNotificationContent?
                    
                    override func didReceive(_ request: UNNotificationRequest, 
                                           withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
                        self.contentHandler = contentHandler
                        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
                        
                        guard let bestAttemptContent = bestAttemptContent else {
                            contentHandler(request.content)
                            return
                        }
                        
                        // Extract video URL from notification payload
                        guard let videoURLString = bestAttemptContent.userInfo["video_url"] as? String,
                              let videoURL = URL(string: videoURLString) else {
                            contentHandler(bestAttemptContent)
                            return
                        }
                        
                        // Download video asynchronously
                        Task {
                            await downloadAndAttachVideo(from: videoURL, to: bestAttemptContent)
                            contentHandler(bestAttemptContent)
                        }
                    }
                    
                    override func serviceExtensionTimeWillExpire() {
                        // Called when extension is about to be terminated
                        // Deliver the best attempt content
                        if let contentHandler = contentHandler, 
                           let bestAttemptContent = bestAttemptContent {
                            contentHandler(bestAttemptContent)
                        }
                    }
                    
                    private func downloadAndAttachVideo(from url: URL, 
                                                      to content: UNMutableNotificationContent) async {
                        do {
                            // Create URLSession with timeout configuration
                            let config = URLSessionConfiguration.default
                            config.timeoutIntervalForRequest = 25.0 // Leave 5 seconds buffer
                            let session = URLSession(configuration: config)
                            
                            // Download video data
                            let (data, response) = try await session.data(from: url)
                            
                            // Validate response
                            guard let httpResponse = response as? HTTPURLResponse,
                                  httpResponse.statusCode == 200 else {
                                throw NSError(domain: "DownloadError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                            }
                            
                            // Create temporary file
                            let tempDirectory = FileManager.default.temporaryDirectory
                            let videoFileName = "notification_video_\\(UUID().uuidString).mp4"
                            let tempVideoURL = tempDirectory.appendingPathComponent(videoFileName)
                            
                            // Write data to temporary file
                            try data.write(to: tempVideoURL)
                            
                            // Create notification attachment
                            let attachment = try UNNotificationAttachment(
                                identifier: "video_attachment",
                                url: tempVideoURL,
                                options: [
                                    UNNotificationAttachmentOptionsTypeHintKey: "public.mpeg-4"
                                ]
                            )
                            
                            // Attach to notification content
                            content.attachments = [attachment]
                            content.body = "📹 Video notification received"
                            
                        } catch {
                            print("Failed to download video: \\(error)")
                            // Fallback: Show notification without video
                            content.body = "Video notification (download failed)"
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

                Subtitle("5) Custom Notification Actions")
                BodyText("Define custom notification actions for enhanced user interaction:")
                CodeBlock("""
                class NotificationActionsManager {
                    static let shared = NotificationActionsManager()
                    
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
                }
                """)

                Subtitle("6) Testing with Local Notifications")
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
                    "Add Notification Content Extension target with custom UI.",
                    "Configure App Groups for data sharing between extensions.",
                    "Setup push notification certificates in Apple Developer Portal.",
                    "Test on physical device using Apple Push Notification Console.",
                    "Implement proper error handling for network failures and timeouts."
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