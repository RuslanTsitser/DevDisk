import CoreGraphics
import Foundation

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    guard window[kCGWindowOwnerName as String] as? String == "DevDisk",
          let number = window[kCGWindowNumber as String] as? Int,
          (window[kCGWindowLayer as String] as? Int) == 0
    else { continue }
    print(number)
    exit(EXIT_SUCCESS)
}
exit(EXIT_FAILURE)
