//
//  Title.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 11/08/25.
//

import SwiftUI

struct Title: View {
    let text: String
    init(_ t: String) { self.text = t }
    var body: some View {
        Text(text)
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundColor(.titleColor)
    }
}
