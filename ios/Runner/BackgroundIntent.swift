//
//  BackgroundIntent.swift
//  Runner
//
//  Generic home_widget background intent. Lives in the Runner (app) target so
//  iOS runs it in the app process, where the headless Flutter engine can start
//  and execute the Dart `backgroundCallback`. The AI Wellness widget references
//  this intent to toggle a plan action directly from the home screen without
//  opening the app.
//
import AppIntents
import Foundation
import home_widget

@available(iOS 17, *)
public struct BackgroundIntent: AppIntent {
  static public var title: LocalizedStringResource = "HomeWidget Background Intent"

  @Parameter(title: "Widget URI")
  var url: URL?

  @Parameter(title: "AppGroup")
  var appGroup: String?

  public init() {}

  public init(url: URL?, appGroup: String?) {
    self.url = url
    self.appGroup = appGroup
  }

  public func perform() async throws -> some IntentResult {
    await HomeWidgetBackgroundWorker.run(url: url, appGroup: appGroup!)
    return .result()
  }
}

/// Required for the widget to stay interactive even when the app is fully
/// suspended. This launches the app in the background, so the Dart side should
/// check the current lifecycle state before doing heavy work.
@available(iOS 17, *)
@available(iOSApplicationExtension, unavailable)
extension BackgroundIntent: ForegroundContinuableIntent {}
