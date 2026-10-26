import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Widget Bundle Entry Point

struct CallWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            CallIslandWidgetLiveActivity()
        }
    }
}

// MARK: - LiveActivities App Attributes Bridge

struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable { }

    var id = UUID()
}

extension LiveActivitiesAppAttributes {
    func prefixedKey(_ key: String) -> String {
        return "\(id)_\(key)"
    }
}

private let sharedDefault = UserDefaults(suiteName: "group.com.shis.securecalc")

// MARK: - SwiftUI Dynamic Island Widget

@available(iOS 16.1, *)
struct CallIslandWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            // MARK: - Lock Screen Banner View
            let peerName = sharedDefault?.string(forKey: context.attributes.prefixedKey("peerName")) ?? "Active Call"
            let isVideo = sharedDefault?.bool(forKey: context.attributes.prefixedKey("isVideo")) ?? false
            let startTimeSec = sharedDefault?.double(forKey: context.attributes.prefixedKey("startTime")) ?? Date().timeIntervalSince1970
            let startDate = Date(timeIntervalSince1970: startTimeSec > 0 ? startTimeSec : Date().timeIntervalSince1970)

            HStack(spacing: 12) {
                Image(systemName: isVideo ? "video.fill" : "phone.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(red: 0.20, green: 0.78, blue: 0.35))
                    .frame(width: 38, height: 38)
                    .background(Color(red: 0.20, green: 0.78, blue: 0.35).opacity(0.18))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(peerName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text(startDate, style: .timer)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(red: 0.20, green: 0.78, blue: 0.35))
                }

                Spacer()

                Link(destination: URL(string: "securecalc://hangup")!) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.red)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        } dynamicIsland: { context in
            let peerName = sharedDefault?.string(forKey: context.attributes.prefixedKey("peerName")) ?? "Call"
            let isVideo = sharedDefault?.bool(forKey: context.attributes.prefixedKey("isVideo")) ?? false
            let startTimeSec = sharedDefault?.double(forKey: context.attributes.prefixedKey("startTime")) ?? Date().timeIntervalSince1970
            let startDate = Date(timeIntervalSince1970: startTimeSec > 0 ? startTimeSec : Date().timeIntervalSince1970)

            return DynamicIsland {
                // MARK: - Expanded View (Long Press)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: isVideo ? "video.fill" : "phone.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 0.20, green: 0.78, blue: 0.35))
                        Text(peerName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.leading, 8)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Link(destination: URL(string: "securecalc://hangup")!) {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 8)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.20, green: 0.78, blue: 0.35))
                        Text(startDate, style: .timer)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.20, green: 0.78, blue: 0.35))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
            } compactLeading: {
                // MARK: - Compact Left (Calling Symbol / Phone Icon)
                Image(systemName: isVideo ? "video.fill" : "phone.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.20, green: 0.78, blue: 0.35))
                    .padding(.leading, 4)
            } compactTrailing: {
                // MARK: - Compact Right (Live Timer like Swiggy / Active Call)
                Text(startDate, style: .timer)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.20, green: 0.78, blue: 0.35))
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 40)
                    .padding(.trailing, 4)
            } minimal: {
                // MARK: - Minimal View (Calling Symbol)
                Image(systemName: isVideo ? "video.fill" : "phone.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.20, green: 0.78, blue: 0.35))
            }
        }
    }
}
