//
//  BodyText.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 11/08/25.
//

import SwiftUI

struct BodyText: View {
    let text: String
    init(_ t: String) { self.text = t }
    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .regular, design: .default))
            .foregroundColor(.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
