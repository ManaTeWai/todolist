export interface MenuItem {
  id: number;
  title: string;
  url: string;
  parent_id: number | null;
  order: number;
  is_active: boolean;
  type: string;
  icon?: string;
  target?: string;
}
