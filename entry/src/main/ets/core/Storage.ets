import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const STORE_NAME: string = 'hello_json_config';
/** 主题默认值修订号：从 2 开始默认浅色，老版本升级时重置一次 */
const THEME_REV: number = 2;
/** 布局方向默认值修订号：默认方向改为「从上往下」，老配置升级时重置一次 */
const DIRECTION_REV: number = 1;

export class AppConfig {
  darkMode: boolean = false;
  direction: string = 'DOWN';
  viewMode: string = 'graph';
  /** 仅作为旧版本兼容字段，写入当前激活标签的文本 */
  jsonText: string = '';
  activeTabId: string = '';
}

/** 单个标签的持久化记录 */
export class TabRecord {
  id: string = '';
  title: string = '';
  text: string = '';
  savedText: string = '';
  collapsed: string[] = [];
  treeCollapsed: string[] = [];
  selectedPath: string = '';
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
      cfg.jsonText = this.store.getSync('jsonText', '') as string;
      cfg.activeTabId = this.store.getSync('activeTabId', '') as string;
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
      this.store.putSync('jsonText', cfg.jsonText);
      this.store.putSync('activeTabId', cfg.activeTabId);
      this.store.flush();
    } catch (e) {
      return;
    }
  }

  /** 读取全部标签记录（顺序即标签条顺序） */
  loadTabs(): TabRecord[] {
    const out: TabRecord[] = [];
    if (this.store === null) {
      return out;
    }
    try {
      const ids = this.store.getSync('tabIds', []) as string[];
      for (let i = 0; i < ids.length; i++) {
        const id = ids[i];
        const rec = new TabRecord();
        rec.id = id;
        rec.title = this.store.getSync('tab.' + id + '.title', '') as string;
        rec.text = this.store.getSync('tab.' + id + '.text', '') as string;
        rec.savedText = this.store.getSync('tab.' + id + '.savedText', '') as string;
        rec.collapsed = this.store.getSync('tab.' + id + '.collapsed', []) as string[];
        rec.treeCollapsed = this.store.getSync('tab.' + id + '.treeCollapsed', []) as string[];
        rec.selectedPath = this.store.getSync('tab.' + id + '.selectedPath', '') as string;
        out.push(rec);
      }
    } catch (e) {
      hilog.error(0x0000, 'HelloJson', 'loadTabs failed');
      return out;
    }
    hilog.info(0x0000, 'HelloJson', 'loadTabs count=' + out.length);
    return out;
  }

  /** 保存全部标签与当前激活标签 */
  saveTabs(tabs: TabRecord[], activeId: string): void {
    if (this.store === null) {
      return;
    }
    try {
      const ids: string[] = [];
      for (let i = 0; i < tabs.length; i++) {
        const t = tabs[i];
        ids.push(t.id);
        this.store.putSync('tab.' + t.id + '.title', t.title);
        this.store.putSync('tab.' + t.id + '.text', t.text);
        this.store.putSync('tab.' + t.id + '.savedText', t.savedText);
        this.store.putSync('tab.' + t.id + '.collapsed', t.collapsed);
        this.store.putSync('tab.' + t.id + '.treeCollapsed', t.treeCollapsed);
        this.store.putSync('tab.' + t.id + '.selectedPath', t.selectedPath);
      }
      this.store.putSync('tabIds', ids);
      this.store.putSync('activeTabId', activeId);
      this.store.flush();
      hilog.info(0x0000, 'HelloJson', 'saveTabs count=' + ids.length + ' active=' + activeId);
    } catch (e) {
      hilog.error(0x0000, 'HelloJson', 'saveTabs failed');
      return;
    }
  }

  /** 只保存单个标签（编辑正文时高频调用，避免重写全部标签） */
  saveTab(rec: TabRecord): void {
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync('tab.' + rec.id + '.title', rec.title);
      this.store.putSync('tab.' + rec.id + '.text', rec.text);
      this.store.putSync('tab.' + rec.id + '.savedText', rec.savedText);
      this.store.putSync('tab.' + rec.id + '.collapsed', rec.collapsed);
      this.store.putSync('tab.' + rec.id + '.treeCollapsed', rec.treeCollapsed);
      this.store.putSync('tab.' + rec.id + '.selectedPath', rec.selectedPath);
      this.store.flush();
    } catch (e) {
      hilog.error(0x0000, 'HelloJson', 'saveTab failed');
      return;
    }
  }

  /** 关闭标签后清理它的持久化数据 */
  deleteTab(id: string): void {
    if (this.store === null) {
      return;
    }
    try {
      this.store.deleteSync('tab.' + id + '.title');
      this.store.deleteSync('tab.' + id + '.text');
      this.store.deleteSync('tab.' + id + '.savedText');
      this.store.deleteSync('tab.' + id + '.collapsed');
      this.store.deleteSync('tab.' + id + '.treeCollapsed');
      this.store.deleteSync('tab.' + id + '.selectedPath');
    } catch (e) {
      return;
    }
  }
}

export const configStore: ConfigStore = new ConfigStore();
