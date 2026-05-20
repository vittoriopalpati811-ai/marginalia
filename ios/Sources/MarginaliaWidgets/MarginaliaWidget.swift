// MarginaliaWidget.swift
// WidgetKit extension for Marginalia — iOS 17+
//
// Reads highlight data written by the Flutter app via home_widget package
// (UserDefaults with App Group "group.marginalia.widget") and renders it
// in three sizes: small, medium, large.
//
// SETUP (one-time, in Xcode):
//  1. Add a new "Widget Extension" target named "MarginaliaWidgets"
//  2. Copy this file into the new target
//  3. In Runner + MarginaliaWidgets → Signing & Capabilities → add App Groups
//     and tick "group.marginalia.widget"
//  4. In Runner's AppDelegate.swift add:
//       HomeWidget.setAppGroupId("group.marginalia.widget")
//  5. Codemagic will pick up the new target automatically if your
//     codemagic.yaml includes the --target flag for the extension.

import WidgetKit
import SwiftUI

// ─── Data model ──────────────────────────────────────────────────────────────

private struct HighlightEntry: TimelineEntry {
    let date: Date
    let text: String
    let bookTitle: String
    let author: String
    let greeting: String
    let weatherMood: String

    static let placeholder = HighlightEntry(
        date: Date(),
        text: "Non si leggono i libri per finirli, ma per abitarli — per trovare in essi un'altra casa.",
        bookTitle: "Come un romanzo",
        author: "Daniel Pennac",
        greeting: "Buongiorno",
        weatherMood: "clear"
    )
}

// ─── Provider ────────────────────────────────────────────────────────────────

private struct HighlightProvider: TimelineProvider {
    private let groupId = "group.marginalia.widget"

    func placeholder(in context: Context) -> HighlightEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (HighlightEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HighlightEntry>) -> Void) {
        let current = entry()
        // Refresh every 4 hours — Flutter app writes new data when opened
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 4, to: Date())!
        let timeline = Timeline(entries: [current], policy: .after(nextRefresh))
        completion(timeline)
    }

    private func entry() -> HighlightEntry {
        let defaults = UserDefaults(suiteName: groupId)
        return HighlightEntry(
            date: Date(),
            text: defaults?.string(forKey: "w_text") ?? HighlightEntry.placeholder.text,
            bookTitle: defaults?.string(forKey: "w_book") ?? HighlightEntry.placeholder.bookTitle,
            author: defaults?.string(forKey: "w_author") ?? HighlightEntry.placeholder.author,
            greeting: defaults?.string(forKey: "w_greeting") ?? greetingForNow(),
            weatherMood: defaults?.string(forKey: "w_weather") ?? "clear"
        )
    }

    private func greetingForNow() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Buongiorno"
        case 12..<17: return "Buon pomeriggio"
        case 17..<21: return "Buona sera"
        default:      return "Buona notte"
        }
    }
}

// ─── Color tokens ────────────────────────────────────────────────────────────

private extension Color {
    static let wBackground  = Color(red: 0.059, green: 0.137, blue: 0.094)  // #0F2318
    static let wSurface     = Color(red: 0.082, green: 0.184, blue: 0.122)  // #152F1F
    static let wText        = Color(red: 0.961, green: 0.949, blue: 0.925)  // #F5F2EC
    static let wAccent      = Color(red: 0.290, green: 0.478, blue: 0.204)  // #4A7A35
    static let wMuted       = Color(red: 0.620, green: 0.733, blue: 0.541)  // #9EBB8A
}

// ─── Weather icon ─────────────────────────────────────────────────────────────

private func weatherSystemImage(_ mood: String) -> String {
    switch mood {
    case "sunny":  return "sun.max"
    case "rain":   return "cloud.rain"
    case "cloudy": return "cloud"
    case "snow":   return "snowflake"
    default:       return "moon.stars"
    }
}

// ─── Small widget (2×2) ───────────────────────────────────────────────────────

private struct SmallWidgetView: View {
    let entry: HighlightEntry

    var body: some View {
        ZStack {
            Color.wBackground
            VStack(alignment: .leading, spacing: 0) {
                BrandRow(greeting: entry.greeting, compact: true)
                Spacer()
                Text(firstSentence(entry.text, max: 90))
                    .font(.custom("EBGaramond-Italic", size: 12.5))
                    .foregroundColor(.wText)
                    .lineSpacing(3)
                    .lineLimit(5)
                Spacer(minLength: 6)
                Text(entry.bookTitle.uppercased())
                    .font(.system(size: 8, weight: .semibold, design: .default))
                    .foregroundColor(.wMuted)
                    .lineLimit(1)
            }
            .padding(13)
        }
    }
}

// ─── Medium widget (4×2) ──────────────────────────────────────────────────────

private struct MediumWidgetView: View {
    let entry: HighlightEntry

    var body: some View {
        ZStack {
            Color.wBackground
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    BrandRow(greeting: entry.greeting)
                    Spacer()
                    Text(firstSentence(entry.text, max: 130))
                        .font(.custom("EBGaramond-Italic", size: 13))
                        .foregroundColor(.wText)
                        .lineSpacing(3)
                        .lineLimit(4)
                    Spacer(minLength: 8)
                    Text(entry.bookTitle.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.wMuted)
                        .lineLimit(1)
                }
                VStack(alignment: .trailing) {
                    Text("\u{201C}")  // opening quotation mark
                        .font(.custom("EBGaramond-Bold", size: 46))
                        .foregroundColor(.wAccent.opacity(0.5))
                        .offset(y: -8)
                    Spacer()
                    Image(systemName: weatherSystemImage(entry.weatherMood))
                        .font(.system(size: 16))
                        .foregroundColor(.wMuted.opacity(0.7))
                }
            }
            .padding(14)
        }
    }
}

// ─── Large widget (4×4) ───────────────────────────────────────────────────────

private struct LargeWidgetView: View {
    let entry: HighlightEntry

    var body: some View {
        ZStack {
            Color.wBackground
            VStack(alignment: .leading, spacing: 0) {
                BrandRow(greeting: entry.greeting)
                Spacer(minLength: 14)
                Rectangle()
                    .fill(Color.wMuted.opacity(0.25))
                    .frame(height: 0.5)
                Spacer(minLength: 14)
                Text(firstSentence(entry.text, max: 320))
                    .font(.custom("EBGaramond-Italic", size: 15.5))
                    .foregroundColor(.wText)
                    .lineSpacing(5)
                Spacer()
                // Book + author row
                HStack(alignment: .center, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.wAccent)
                        .frame(width: 3, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.bookTitle)
                            .font(.custom("EBGaramond-SemiBold", size: 13))
                            .foregroundColor(.wText)
                            .lineLimit(1)
                        Text(entry.author)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.wMuted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: weatherSystemImage(entry.weatherMood))
                        .font(.system(size: 18))
                        .foregroundColor(.wMuted.opacity(0.7))
                }
            }
            .padding(16)
        }
    }
}

// ─── Shared subviews ──────────────────────────────────────────────────────────

private struct BrandRow: View {
    let greeting: String
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            // Marginalia "M" badge
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.wAccent)
                    .frame(width: 20, height: 20)
                Text("M")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.wText)
            }
            if !compact {
                Text(greeting)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.wMuted)
            }
        }
    }
}

// ─── Widget entry point ───────────────────────────────────────────────────────

@main
struct MarginaliaWidget: Widget {
    let kind = "MarginaliaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HighlightProvider()) { entry in
            MarginaliaWidgetEntryView(entry: entry)
                .containerBackground(Color.wBackground, for: .widget)
        }
        .configurationDisplayName("Marginalia")
        .description("Il tuo highlight del momento, scelto dall'AI.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct MarginaliaWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: HighlightEntry

    var body: some View {
        switch family {
        case .systemSmall:  SmallWidgetView(entry: entry)
        case .systemMedium: MediumWidgetView(entry: entry)
        case .systemLarge:  LargeWidgetView(entry: entry)
        default:            MediumWidgetView(entry: entry)
        }
    }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

private func firstSentence(_ text: String, max: Int) -> String {
    guard text.count > max else { return text }
    let cut = String(text.prefix(max))
    if let dot = cut.lastIndex(of: "."),
       cut.distance(from: cut.startIndex, to: dot) > max * 6 / 10 {
        return String(text[...dot])
    }
    return cut.trimmingCharacters(in: .whitespaces) + "…"
}

// ─── Xcode previews ───────────────────────────────────────────────────────────

#Preview(as: .systemSmall)  { MarginaliaWidget() } timeline: { HighlightEntry.placeholder }
#Preview(as: .systemMedium) { MarginaliaWidget() } timeline: { HighlightEntry.placeholder }
#Preview(as: .systemLarge)  { MarginaliaWidget() } timeline: { HighlightEntry.placeholder }
