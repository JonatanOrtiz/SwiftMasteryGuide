//
//  DividerLine.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 11/08/25.
//

import SwiftUI

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Color.dividerColor)
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}
