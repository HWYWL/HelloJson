import { JKind } from '../core/JValue';

/** 语法高亮的文本片段 */
export class HSpan {
  text: string = '';
  color: string = '';
  /** 查找命中背景色，空串表示无背景 */
  bg: string = '';

  constructor(text: string, color: string, bg: string = '') {
    this.text = text;
    this.color = color;
    this.bg = bg;
  }
}

/** 标签条展示项（每次变化整组重建，避免嵌套属性无法观察） */
export class TabInfo {
  id: string = '';
  title: string = '';
  /** 有未保存修改 */
  dirty: boolean = false;

  constructor(id: string, title: string, dirty: boolean) {
    this.id = id;
    this.title = title;
    this.dirty = dirty;
  }
}

/**
 * 一个打开的文档。
 * 激活标签的实时数据仍保存在 EditorStore 的字段里，
 * 这里只保存切换/关闭时需要还原的快照。
 */
export class DocTab {
  id: string = '';
  title: string = '';
  text: string = '';
  /** 上次保存/导入时的文本，用于判断未保存修改 */
  savedText: string = '';
  collapsed: string[] = [];
  treeCollapsed: string[] = [];
  selectedPath: string = '';
}

/** 树视图中的一行 */
export class TreeItem {
  depth: number = 0;
  label: string = '';
  value: string = '';
  kind: JKind = JKind.Null;
  path: string = '';
  hasChildren: boolean = false;
  collapsed: boolean = false;
  isContainer: boolean = false;
}

/** 树视图懒加载数据源：几千行时避免一次性创建全部 ListItem */
export class TreeDataSource implements IDataSource {
  private items: TreeItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): TreeItem {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  setItems(items: TreeItem[]): void {
    this.items = items;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}
