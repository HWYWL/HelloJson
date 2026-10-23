import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'hello_json_config';
/** 主题默认值修订号：从 2 开始默认浅色，老版本升级时重置一次 */
const THEME_REV: number = 2;
/** 布局方向默认值修订号：默认方向改为「从上往下」，老配置升级时重置一次 */
const DIRECTION_REV: number = 1;

/**
 * 只持久化外观与编辑设置。
 * 标签与正文不再落盘：重启一律从空白标签开始，避免大文件恢复拖慢启动、撑爆内存。
 */
export class AppConfig {
  darkMode: boolean = false;
  direction: string = 'DOWN';
  viewMode: string = 'graph';
  /** 格式化缩进宽度（2 / 4 空格） */
  indentWidth: number = 2;
  /** 编辑器字号 */
  fontSize: number = 12;
  /** 编辑器自动换行 */
  wordWrap: boolean = true;
}

/** 最近打开的文件（只存 uri 与显示名，不存正文） */
export class RecentFile {
  uri: string = '';
  name: string = '';
}

export class ConfigStore {
  private store: preferences.Preferences | null = null;

  init(context: common.UIAbilityContext): void {
    try {
      this.store = preferences.getPreferencesSync(context, { name: STORE_NAME });
    } catch (e) {
      this.store = null;
    }
  }

  load(): AppConfig {
    const cfg = new AppConfig();
    if (this.store === null) {
      return cfg;
    }
    try {
      cfg.darkMode = this.store.getSync('darkMode', false) as boolean;
      cfg.direction = this.store.getSync('direction', 'DOWN') as string;
      cfg.viewMode = this.store.getSync('viewMode', 'graph') as string;
      cfg.indentWidth = this.store.getSync('indentWidth', 2) as number;
      cfg.fontSize = this.store.getSync('fontSize', 12) as number;
      cfg.wordWrap = this.store.getSync('wordWrap', true) as boolean;
      // 老配置没有 themeRev（或版本更低），统一回到默认浅色主题
      const rev = this.store.getSync('themeRev', 0) as number;
      if (rev < THEME_REV) {
        cfg.darkMode = false;
        this.store.putSync('themeRev', THEME_REV);
        this.store.flush();
      }
      // 老配置的布局方向默认值是从左往右，升级后统一改为从上往下
      const dirRev = this.store.getSync('dirRev', 0) as number;
      if (dirRev < DIRECTION_REV) {
        cfg.direction = 'DOWN';
        this.store.putSync('dirRev', DIRECTION_REV);
        this.store.flush();
      }
    } catch (e) {
      return cfg;
    }
    return cfg;
  }

  save(cfg: AppConfig): void {
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync('darkMode', cfg.darkMode);
      this.store.putSync('themeRev', THEME_REV);
      this.store.putSync('dirRev', DIRECTION_REV);
      this.store.putSync('direction', cfg.direction);
      this.store.putSync('viewMode', cfg.viewMode);
      this.store.putSync('indentWidth', cfg.indentWidth);
      this.store.putSync('fontSize', cfg.fontSize);
      this.store.putSync('wordWrap', cfg.wordWrap);
      this.store.flush();
    } catch (e) {
      return;
    }
  }

  /** 读取最近打开列表（最近的在最前） */
  loadRecent(): RecentFile[] {
    const out: RecentFile[] = [];
    if (this.store === null) {
      return out;
    }
    try {
      const raw = this.store.getSync('recentFiles', '') as string;
      if (raw.length === 0) {
        return out;
      }
      const parsed = JSON.parse(raw) as RecentFile[];
      for (let i = 0; i < parsed.length; i++) {
        const item = new RecentFile();
        item.uri = parsed[i].uri;
        item.name = parsed[i].name;
        if (item.uri.length > 0) {
          out.push(item);
        }
      }
    } catch (e) {
      return out;
    }
    return out;
  }

  /** 保存最近打开列表 */
  saveRecent(list: RecentFile[]): void {
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync('recentFiles', JSON.stringify(list));
      this.store.flush();
    } catch (e) {
      return;
    }
  }

  /**
   * 清空历史版本残留的标签 / 正文数据。
   * 启动时调用：不恢复任何已打开文件，顺手把旧版本写下的大文本删掉，回收存储空间。
   */
  clearTabs(): void {
    if (this.store === null) {
      return;
    }
    try {
      const ids = this.store.getSync('tabIds', []) as string[];
      for (let i = 0; i < ids.length; i++) {
        const id = ids[i];
        this.store.deleteSync('tab.' + id + '.title');
        this.store.deleteSync('tab.' + id + '.text');
        this.store.deleteSync('tab.' + id + '.savedText');
        this.store.deleteSync('tab.' + id + '.collapsed');
        this.store.deleteSync('tab.' + id + '.treeCollapsed');
        this.store.deleteSync('tab.' + id + '.selectedPath');
      }
      this.store.putSync('tabIds', []);
      this.store.deleteSync('activeTabId');
      this.store.deleteSync('jsonText');
      this.store.flush();
    } catch (e) {
      return;
    }
  }
}

export const configStore: ConfigStore = new ConfigStore();
