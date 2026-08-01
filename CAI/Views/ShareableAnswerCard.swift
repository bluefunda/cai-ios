import SwiftUI

/// A branded, fixed-size card rendered to an image for one-tap sharing
/// (bluefunda/cai-ios#197) — e.g. to LinkedIn, WhatsApp, or a text message.
/// Only ever rendered offscreen via `ImageRenderer`, never displayed live in
/// the app, so it deliberately uses fixed (not system/dynamic) colors: a
/// shared image is a static artifact viewed outside the app by people who
/// may not use dark mode, and it should look the same and stay on-brand
/// regardless of the sharer's current appearance setting.
///
/// Takes only the question/answer text — no system connection details or
/// credentials are ever in scope here, so none can leak into a shared card.
struct ShareableAnswerCard: View {
    let question: String?
    let answer: String

    private let cardWidth: CGFloat = 600

    var body: some View {
        VStack(alignment: .leading, spacing: BFSpacing._4) {
            BFLogo(variant: .full, size: .compact)

            if let question, !question.isEmpty {
                Text(question)
                    .font(BFFont.body.weight(.semibold))
                    .foregroundStyle(Color(white: 0.15))
            }

            Text(ShareCardFormatter.truncatedAnswer(answer))
                .font(BFFont.body)
                .foregroundStyle(Color(white: 0.25))

            Divider()

            Text("Answered by BlueFunda AI")
                .font(.caption)
                .foregroundStyle(Color(white: 0.5))
        }
        .padding(BFSpacing._6)
        .frame(width: cardWidth, alignment: .leading)
        .background(Color.white)
    }
}
