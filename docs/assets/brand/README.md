# OneBox 品牌资产

`onebox-mark-light.png` 是当前 AppIcon 的 master。ASCII 工坊在自己的 Swift package 中保存一个实体运行副本，并通过 `Bundle.module` 加载；`onebox-mark-dark.png` 由生成脚本同时校验，但当前产品不使用深色 AppIcon。

更新 master 后，从仓库根目录生成十个 AppIcon 槽位并同步 ASCII package 资源：

```sh
swift scripts/generate-brand-assets.swift
```

`./scripts/check.sh` 会比较 master 与 package 副本，防止默认素材静默漂移。

侧栏 24pt 标识不缩放 PNG，而由 `Packages/OneBoxCore/Sources/OneBoxHost/OneBoxBrandMark.swift` 使用 SwiftUI `Canvas` 绘制透明底 optical mark。颜色来自 DesignSystem 的 `brandMarkHost` 和 `brandMarkCore`；侧栏几何只在该文件中维护。

仓库只保留两个稳定 master 文件名、ASCII package 运行副本和生成后的 AppIcon，不保留候选图或版本副本。
