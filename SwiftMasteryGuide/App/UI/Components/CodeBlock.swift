//
//  CodeBlock.swift
//  SwiftMasteryGuide
//
//  Created by Jonatan Ortiz on 11/08/25.
//

import SwiftUI

struct CodeBlock: View {
    let code: String
    init(_ code: String) { self.code = code }

    @State private var copied = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.codeTextColor)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.codeBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.codeBorder, lineWidth: 1)
                    )
                    .textSelection(.enabled)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button {
                UIPasteboard.general.string = code
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "Copied" : "Copy")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.cardBackground.opacity(0.95))
                .foregroundColor(.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.codeBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(8)
            .accessibilityLabel("Copy code")
        }
    }
}
