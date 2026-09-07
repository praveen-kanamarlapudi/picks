import PicksCore
import SwiftUI

struct EventHomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                    .zIndex(1)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(model.ceremonyCards) { card in
                        cardView(card)
                    }
                }
            }
            .padding(.top, 42)
            .padding(.horizontal, 22)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.visible)
        .background(Theme.bg)
        .background(AlwaysShowScrollers())
        .onAppear { model.refreshHome() }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.eventName)
                    .font(.system(size: 22, weight: .medium))
                    .tracking(-0.4)
                Text("\(model.scanStats.stills) stills · \(model.totalShortlisted) shortlisted · last at \(model.current?.photoID ?? "—")")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Export shortlist") { model.showingExport = true }
                .buttonStyle(.bordered)
                .contentShape(Rectangle())
            Button("Change dump") { model.backToOpen() }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .foregroundStyle(Theme.muted)
        }
    }

    private func cardView(_ card: CeremonyStats) -> some View {
        Button {
            model.openPile(ceremony: card.ceremony, style: card.style)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    cover(card)
                        .frame(height: 110)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    if card.shortlisted == 0 && card.stills > 0 {
                        Text("0 shortlisted")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(Theme.gold)
                            .padding(8)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.ceremony)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                    if !card.style.isEmpty, card.style != "Other" {
                        Text(card.style)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.gold)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line)
                            Capsule().fill(Theme.gold)
                                .frame(width: geo.size.width * card.progress)
                        }
                    }
                    .frame(height: 3)
                    Text("\(card.stills.formatted()) stills · Shortlisted \(card.shortlisted) · Left \(card.left.formatted())")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                }
                .padding(12)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func cover(_ card: CeremonyStats) -> some View {
        Group {
            if let rel = card.coverPath, let root = model.rootURL {
                ThumbView(
                    url: PhotoRecord.canonicalURL(root: root, relative: rel),
                    cacheKey: rel,
                    cacheDir: model.thumbCacheDir
                )
            } else {
                Color.white.opacity(0.06)
            }
        }
    }
}
