//
//  BulletList.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 11/08/25.
//

import SwiftUI

struct BulletList: View {
    let items: [String]
    init(_ items: [String]) { self.items = items }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundColor(.bulletColor)
                    Text(line)
                        .foregroundColor(.textPrimary)
                        .font(.system(size: 16))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
