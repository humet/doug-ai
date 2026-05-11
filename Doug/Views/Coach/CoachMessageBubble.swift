import SwiftUI

struct CoachMessageBubble: View {
    let role: CoachMessageRole
    let content: String

    private var isUser: Bool {
        role == .user
    }

    private var markdownContent: AttributedString {
        (try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(content)
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }

            Text(markdownContent)
                .padding(12)
                .background(isUser ? DougTheme.sourdoughBrown : DougTheme.warmParchment)
                .foregroundStyle(isUser ? DougTheme.flourWhite : .primary)
                .clipShape(.rect(cornerRadius: 16))

            if !isUser { Spacer(minLength: 48) }
        }
    }
}
