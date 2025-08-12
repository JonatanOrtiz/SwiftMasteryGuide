//
//  Color+Extension.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 11/08/25.
//

import SwiftUI

extension Color {
    // MARK: - Background Colors
    static var background: Color {
        Color(UIColor.systemBackground)
    }

    static var backgroundSurface: Color {
        Color(UIColor.secondarySystemBackground)
    }

    static var cardBackground: Color {
        Color(UIColor.secondarySystemBackground)
    }

    static var backgroundScreen: Color {
        Color(UIColor.systemBackground)
    }

    // MARK: - Input Colors
    static var inputBackground: Color {
        Color(UIColor.secondarySystemFill)
    }

    static var inputTextColor: Color {
        Color(UIColor.label)
    }

    // MARK: - Text Colors
    static var textPrimary: Color {
        Color(UIColor.label)
    }

    static var textSecondary: Color {
        Color(UIColor.secondaryLabel)
    }

    static var textTertiary: Color {
        Color(UIColor.tertiaryLabel)
    }

    static var linkTextColor: Color {
        Color(UIColor.link)
    }

    // MARK: - Surface Colors
    static var divider: Color {
        Color(UIColor.separator)
    }
}

// MARK: - Custom Component Colors
extension Color {
    static var bulletColor: Color {
        Color(UIColor.label)
    }

    static var codeTextColor: Color {
        Color(UIColor.label)
    }

    static var codeBackground: Color {
        Color(UIColor.secondarySystemBackground)
    }

    static var codeBorder: Color {
        Color(UIColor.separator)
    }

    static var dividerColor: Color {
        Color(UIColor.separator)
    }

    static var subtitleColor: Color {
        Color(UIColor.label)
    }

    static var titleColor: Color {
        Color(UIColor.label)
    }
}

// MARK: - Status Colors (same for both themes)
extension Color {
    static let success = Color(red: 0.6, green: 0.8, blue: 0.6)
    static let warning = Color(red: 0.95, green: 0.8, blue: 0.6)
    static let error = Color(red: 0.96, green: 0.55, blue: 0.55)
    static let focus = Color(red: 0.9, green: 0.7, blue: 0.9)
}
