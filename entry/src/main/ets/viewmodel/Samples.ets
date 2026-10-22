/** 内置示例数据 */
export const SAMPLE: string = `{
  "name": "HelloJson",
  "version": "1.0.0",
  "description": "原生鸿蒙 JSON 可视化工具",
  "features": [
    "图形可视化",
    "树形视图",
    "jq 查询",
    "JSONPath 查询"
  ],
  "author": {
    "name": "一叶秋枫",
    "homepage": "https://github.com/HWYWL/HelloJson"
  },
  "stats": {
    "stars": 128,
    "active": true,
    "tags": ["harmonyos", "arkts", "json"]
  }
}`;

export const SAMPLE_YAML: string = `app:
  name: HelloJson
  version: 1.0.0
  description: 原生鸿蒙 JSON 可视化工具
  features:
    - 图形可视化
    - 树形视图
    - jq 查询
  author:
    name: 一叶秋枫
    homepage: https://github.com/HWYWL/HelloJson
  stats:
    stars: 128
    active: true
`;

export const SAMPLE_CSV: string = `name,version,stars,active,lang
HelloJson,1.0.0,128,true,ArkTS
QuickTerm,2.1.0,356,true,Rust
JsonViewer,0.9.3,87,false,TypeScript
`;

export const SAMPLE_XML: string = `<?xml version="1.0" encoding="UTF-8"?>
<app>
  <name>HelloJson</name>
  <version>1.0.0</version>
  <description>原生鸿蒙 JSON 可视化工具</description>
  <features>
    <feature>图形可视化</feature>
    <feature>树形视图</feature>
    <feature>JSONPath 查询</feature>
  </features>
  <author>
    <name>一叶秋枫</name>
    <homepage>https://github.com/HWYWL/HelloJson</homepage>
  </author>
</app>`;
