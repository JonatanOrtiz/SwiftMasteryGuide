//
//  NotificationService.swift
//  NotificationServiceExtension
//
//  Push Notifications with Video - Service Extension
//  Downloads video content and attaches it to notifications
//

import UserNotifications
import Foundation
import SwiftUI

class NotificationService: UNNotificationServiceExtension {
    
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?
    
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        
        print("🎬 [NotificationService] didReceive called")
        print("🎬 [NotificationService] Request identifier: \(request.identifier)")
        print("🎬 [NotificationService] Content: \(request.content.userInfo)")
        
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        guard let bestAttemptContent = bestAttemptContent else {
            print("🎬 [NotificationService] ❌ Failed to create mutable content")
            contentHandler(request.content)
            return
        }
        
        // Extract video URL from notification payload
        guard let videoURLString = bestAttemptContent.userInfo["video_url"] as? String,
              let videoURL = URL(string: videoURLString) else {
            print("🎬 [NotificationService] ❌ No video_url found in payload")
            // Still show notification without video
            bestAttemptContent.body = "📱 Notification received (no video URL)"
            contentHandler(bestAttemptContent)
            return
        }
        
        print("🎬 [NotificationService] ✅ Video URL found: \(videoURL)")
        
        // Download video asynchronously with timeout
        Task {
            await downloadAndAttachVideo(from: videoURL, to: bestAttemptContent)
            contentHandler(bestAttemptContent)
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called when extension is about to be terminated (30 second limit)
        print("🎬 [NotificationService] ⏰ Service extension time will expire!")
        
        if let contentHandler = contentHandler,
           let bestAttemptContent = bestAttemptContent {
            
            // Provide fallback content if download didn't complete
            bestAttemptContent.body = "📱 Video notification (download timed out)"
            bestAttemptContent.userInfo["download_status"] = "timeout"
            
            contentHandler(bestAttemptContent)
        }
    }
    
    private func downloadAndAttachVideo(from url: URL, to content: UNMutableNotificationContent) async {
        print("🎬 [NotificationService] 📥 Starting video download from: \(url)")
        
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
            print("🎬 [NotificationService] ✅ Download completed in \(String(format: "%.2f", downloadTime))s")
            print("🎬 [NotificationService] 📊 Data size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .binary))")
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NotificationServiceError.invalidResponse
            }
            
            print("🎬 [NotificationService] 📡 HTTP Status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                throw NotificationServiceError.httpError(httpResponse.statusCode)
            }
            
            // Validate content type
            let contentType = httpResponse.mimeType ?? "unknown"
            print("🎬 [NotificationService] 📄 Content-Type: \(contentType)")
            
            guard contentType.hasPrefix("video/") else {
                print("🎬 [NotificationService] ⚠️ Warning: Content-Type is not video/*, proceeding anyway")
                return
            }
            
            // Create temporary file with proper extension
            let tempDirectory = FileManager.default.temporaryDirectory
            let fileExtension = determineFileExtension(from: url, contentType: contentType)
            let videoFileName = "notification_video_\(UUID().uuidString).\(fileExtension)"
            let tempVideoURL = tempDirectory.appendingPathComponent(videoFileName)
            
            print("🎬 [NotificationService] 💾 Writing to: \(tempVideoURL.lastPathComponent)")
            
            // Write data to temporary file
            try data.write(to: tempVideoURL)
            
            // Verify file was written
            let attributes = try FileManager.default.attributesOfItem(atPath: tempVideoURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            print("🎬 [NotificationService] ✅ File written: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .binary))")
            
            // Create notification attachment
            let attachmentOptions: [String: Any] = [
                UNNotificationAttachmentOptionsTypeHintKey: determineTypeHint(from: contentType)
            ]
            
            let attachment = try UNNotificationAttachment(
                identifier: "video_attachment",
                url: tempVideoURL,
                options: attachmentOptions
            )
            
            print("🎬 [NotificationService] 🎥 Video attachment created successfully")
            
            // Update notification content
            content.attachments = [attachment]
            content.body = "📹 Video notification with \(fileExtension.uppercased()) content"
            content.userInfo["download_status"] = "success"
            content.userInfo["file_size"] = fileSize
            content.userInfo["download_time"] = downloadTime
            
        } catch {
            print("🎬 [NotificationService] ❌ Download failed: \(error)")
            
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
        print("🎬 [NotificationService] 🖼️ Adding fallback image...")
        
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
            print("🎬 [NotificationService] ✅ Fallback image added")
            
        } catch {
            print("🎬 [NotificationService] ❌ Failed to create fallback image: \(error)")
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
            let text = "⚠️ Video Download\nFailed"
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
            return "HTTP error: \(code)"
        case .unsupportedContentType(let type):
            return "Unsupported content type: \(type)"
        case .fileTooLarge(let size):
            return "File too large: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .binary))"
        }
    }
}
