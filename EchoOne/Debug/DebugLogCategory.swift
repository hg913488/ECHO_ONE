import Foundation

enum DebugLogCategory: String, Codable {
    case hotkey = "Hotkey"
    case ocr = "OCR"
    case cleanup = "Cleanup"
    case model = "Model"
    case performance = "Performance"
}
