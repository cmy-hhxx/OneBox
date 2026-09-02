enum AsciiToolError: Error, Equatable, Sendable {
    case unsupportedFormat
    case fileTooLarge
    case imageDimensionsTooLarge
    case decodeFailed
    case importTimedOut
    case metalUnavailable
    case exportFailed

    var actionMessage: String {
        switch self {
        case .unsupportedFormat:
            "请选择 PNG、JPEG 或 SVG 文件。"
        case .fileTooLarge:
            "文件超过 50 MB，请选择更小的素材。"
        case .imageDimensionsTooLarge:
            "图片声明的像素尺寸过大，请先缩小素材。"
        case .decodeFailed:
            "无法读取该素材，请检查文件是否损坏。"
        case .importTimedOut:
            "读取素材超时，请缩小图片后重试。"
        case .metalUnavailable:
            "当前设备无法启动 Metal 渲染。"
        case .exportFailed:
            "导出失败，请重试或选择其他位置。"
        }
    }
}
