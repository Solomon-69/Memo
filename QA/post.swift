import Foundation
DistributedNotificationCenter.default().postNotificationName(.init("com.solomon.Tenax.test"), object: CommandLine.arguments[1], userInfo: nil, deliverImmediately: true)
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
