// Aria home-screen widgets for iOS (WidgetKit).
// Setup (one time, needs your Apple team): see README › "iOS widget setup".
// Data is written by lib/features/widgets/home_widgets.dart via home_widget
// into the shared App Group "group.com.aria.pa".
import SwiftUI
import WidgetKit

private let appGroup = "group.com.aria.pa"

struct AriaEntry: TimelineEntry {
  let date: Date
  let nextTitle: String
  let nextTime: String
  let nextLink: URL
  let todayHeader: String
  let todayLines: String
}

struct AriaProvider: TimelineProvider {
  private func read() -> AriaEntry {
    let d = UserDefaults(suiteName: appGroup)
    return AriaEntry(
      date: Date(),
      nextTitle: d?.string(forKey: "next_title") ?? "Nothing coming up",
      nextTime: d?.string(forKey: "next_time") ?? "Tap the mic to add one",
      nextLink: URL(string: d?.string(forKey: "next_link") ?? "aria:///today")!,
      todayHeader: d?.string(forKey: "today_count") ?? "Today",
      todayLines: d?.string(forKey: "today_lines") ?? "A clear day 🌤️"
    )
  }

  func placeholder(in context: Context) -> AriaEntry {
    AriaEntry(date: Date(), nextTitle: "💊 Vitamin D", nextTime: "8:30 PM",
              nextLink: URL(string: "aria:///today")!, todayHeader: "Today · 3",
              todayLines: "8:30 PM  Vitamin D\n9:00 PM  Call Mom")
  }

  func getSnapshot(in context: Context, completion: @escaping (AriaEntry) -> Void) {
    completion(read())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<AriaEntry>) -> Void) {
    // The app calls WidgetCenter.reloadTimelines on every change; refresh
    // every 30 min as a fallback so "next" stays current.
    completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(1800))))
  }
}

private let purple = Color(red: 0.486, green: 0.302, blue: 1.0)

struct NextReminderView: View {
  let entry: AriaEntry
  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("Next").font(.caption).foregroundStyle(.secondary)
        Text(entry.nextTitle).font(.headline).lineLimit(2)
        Text(entry.nextTime).font(.subheadline).foregroundStyle(purple)
      }
      Spacer()
      Link(destination: URL(string: "aria:///talk")!) {
        Image(systemName: "mic.fill").foregroundStyle(.white)
          .frame(width: 44, height: 44).background(Circle().fill(purple))
      }
      .accessibilityLabel("Talk to Aria")
    }
    .widgetURL(entry.nextLink)
    .containerBackground(.background, for: .widget)
  }
}

struct TodayView: View {
  let entry: AriaEntry
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(entry.todayHeader).font(.headline).foregroundStyle(purple)
      Text(entry.todayLines).font(.subheadline)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .widgetURL(URL(string: "aria:///today"))
    .containerBackground(.background, for: .widget)
  }
}

struct MicView: View {
  var body: some View {
    Image(systemName: "mic.fill").font(.largeTitle).foregroundStyle(.white)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .widgetURL(URL(string: "aria:///talk"))
      .containerBackground(purple.gradient, for: .widget)
      .accessibilityLabel("Talk to Aria")
  }
}

struct AriaWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "AriaWidget", provider: AriaProvider()) { NextReminderView(entry: $0) }
      .configurationDisplayName("Next reminder")
      .description("Your next reminder, and a mic to add one.")
      .supportedFamilies([.systemMedium, .accessoryRectangular])
  }
}

struct AriaTodayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "AriaTodayWidget", provider: AriaProvider()) { TodayView(entry: $0) }
      .configurationDisplayName("Today")
      .description("What's left today.")
      .supportedFamilies([.systemMedium, .systemLarge])
  }
}

struct AriaMicWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "AriaMicWidget", provider: AriaProvider()) { _ in MicView() }
      .configurationDisplayName("Talk to Aria")
      .description("One tap to add a reminder by voice.")
      .supportedFamilies([.systemSmall])
  }
}

@main
struct AriaWidgets: WidgetBundle {
  var body: some Widget {
    AriaWidget()
    AriaTodayWidget()
    AriaMicWidget()
  }
}
