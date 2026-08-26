# OneBox 品牌资产

正式来源只有两张并列的 PNG master：

- `onebox-mark-light.png`：浅色外观；瓷白背景、钴蓝外盒、暖燕麦内核。
- `onebox-mark-dark.png`：深色外观；墨蓝黑背景、雾霭蓝外盒、柔沙色内核。

两张 master 必须保持相同的“套盒”轮廓、构图、裁切与表情，只允许针对外观调整配色。它们是完整尺寸图形与品牌配色的唯一来源真相，不直接缩放为侧栏 24pt 小标识。仓库不保留候选图或带版本号的品牌图片；调整后直接更新这两个稳定文件名，并重新生成应用资源。

从仓库根目录重新生成应用资源：

```sh
swift scripts/generate-brand-assets.swift
```

该命令会先验证深浅 master 都能被读取，再从浅色 master 生成当前 macOS `AppIcon.appiconset` 的 16、32、128、256 和 512pt，包含 1x 与 2x，共十个槽位。当前 AppIcon 资源是单外观集合，因此以浅色 master 为固定应用图标来源。

侧栏 24pt 标识由 `OneBox/Host/OneBoxBrandMark.swift` 使用 SwiftUI `Canvas` 绘制透明底 optical mark，不从 PNG 缩小。它保留套盒轮廓、双眼、嘴和右下角涌现构图，主动移除在 24pt 下会造成模糊与色块割裂的背景和微妙明暗。浅色与深色分别使用 Design System 的 `brandMarkHost` 和 `brandMarkCore`，取值必须与两张 master 的外盒及内核配色一致；`--ui-dark` 预览通过环境 palette 自动切换。

生成后的 AppIcon 是可复现的派生产物。品牌审查、完整尺寸配色调整和重新生成始终以本目录中的两张 master 为准；24pt 几何调整只允许发生在 `OneBoxBrandMark.swift`，不得重新引入带背景的侧栏位图。
