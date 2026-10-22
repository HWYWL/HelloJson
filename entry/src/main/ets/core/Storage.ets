import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'hello_json_config';

export class AppConfig {
  darkMode: boolean = true;
  direction: string = 'RIGHT';
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
      cfg.darkMode = this.store.getSync('darkMode', true) as boolean;
      cfg.direction = this.store.getSync('direction', 'RIGHT') as string;
      cfg.viewMode = this.store.getSync('viewMode', 'graph') as string;
      cfg.jsonText = this.store.getSync('jsonText', '') as string;
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
