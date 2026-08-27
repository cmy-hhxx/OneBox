# OneBox 品牌资产

`onebox-mark-light.png` 是当前 AppIcon 的 master，也是 ASCII 工坊的默认素材。应用和 ASCII 测试直接打包该实体文件；`onebox-mark-dark.png` 由生成脚本同时校验，但当前产品不使用深色 AppIcon。

更新 master 后，从仓库根目录生成十个 AppIcon 槽位：

```sh
swift scripts/generate-brand-assets.swift
```

侧栏 24pt 标识不缩放 PNG，而由 `OneBox/Host/OneBoxBrandMark.swift` 使用 SwiftUI `Canvas` 绘制透明底 optical mark。颜色来自 DesignSystem 的 `brandMarkHost` 和 `brandMarkCore`；侧栏几何只在该文件中维护。

仓库只保留两个稳定 master 文件名和生成后的 AppIcon，不保留候选图或版本副本。
