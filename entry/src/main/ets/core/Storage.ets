import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'hello_json_config';
/** 主题默认值修订号：从 2 开始默认浅色，老版本升级时重置一次 */
const THEME_REV: number = 2;
/** 布局方向默认值修订号：默认方向改为「从上往下」，老配置升级时重置一次 */
const DIRECTION_REV: number = 1;

export class AppConfig {
  darkMode: boolean = false;
  direction: string = 'DOWN';
  viewMode: string = 'graph';
  jsonText: string = '';
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
      this.store.flush();
    } catch (e) {
      return;
    }
  }
}

export const configStore: ConfigStore = new ConfigStore();
