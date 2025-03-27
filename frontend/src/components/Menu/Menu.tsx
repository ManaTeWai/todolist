// components/Menu/Menu.tsx
"use client";

import { Htag, P, Loading } from "../";
import { MenuItem } from "@/interfaces/menu.interface";
import Link from "next/link";
import { useEffect, useState } from "react";
import { supabase } from "@/utils/supabase";
import styles from "./Menu.module.css";
import cn from "classnames";
import type { JSX } from "react";

interface MenuItemNode extends MenuItem {
  children?: MenuItemNode[];
}

export const Menu = (): JSX.Element => {
  const [menuTree, setMenuTree] = useState<MenuItemNode[]>([]);
  const [openItems, setOpenItems] = useState<Record<number, boolean>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchMenu = async () => {
      try {
        const { data, error } = await supabase
          .from("menu_items")
          .select("*")
          .order("oorder", { ascending: true })
          .eq("is_active", true);

        if (error) throw error;

        const tree = buildMenuTree(data || []);
        setMenuTree(tree);
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to load menu");
      } finally {
        setLoading(false);
      }
    };

    fetchMenu();
  }, []);

  const buildMenuTree = (items: MenuItem[]): MenuItemNode[] => {
    const itemMap: Record<number, MenuItemNode> = {};
    const tree: MenuItemNode[] = [];

    items.forEach((item) => {
      itemMap[item.id] = { ...item, children: [] };
    });

    items.forEach((item) => {
      if (item.parent_id && itemMap[item.parent_id]) {
        itemMap[item.parent_id].children?.push(itemMap[item.id]);
      } else {
        tree.push(itemMap[item.id]);
      }
    });

    return tree;
  };

  const toggleSubmenu = (id: number) => {
    setOpenItems((prev) => ({
      ...prev,
      [id]: !prev[id],
    }));
  };

  const renderMenu = (items: MenuItemNode[], level = 0): JSX.Element => (
    <ul className={cn(styles.menuList, level > 0 && styles.submenuList)}>
      {items.map((item) => {
        const hasChildren = item.children && item.children.length > 0;
        const isOpen = openItems[item.id];

        return (
          <li
            key={item.id}
            className={cn(styles.menuItem, hasChildren && styles.hasChildren)}
          >
            <div className={styles.itemWrapper}>
              {item.url ? (
                <Link
                  href={item.url}
                  className={styles.link}
                  onClick={(e) => {
                    if (hasChildren) {
                      e.preventDefault();
                      toggleSubmenu(item.id);
                    }
                  }}
                  target={item.target || "_self"}
                >
                  {level === 0 ? (
                    <Htag tag="h2">{item.title}</Htag>
                  ) : (
                    <P size="small">{item.title}</P>
                  )}
                </Link>
              ) : (
                <div
                  className={styles.header}
                  onClick={() => hasChildren && toggleSubmenu(item.id)}
                >
                  {level === 0 ? (
                    <Htag tag="h2">{item.title}</Htag>
                  ) : (
                    <P size="small">{item.title}</P>
                  )}
                </div>
              )}

              {hasChildren && (
                <button
                  className={cn(styles.arrow, isOpen && styles.arrowOpen)}
                  onClick={() => toggleSubmenu(item.id)}
                  aria-label={isOpen ? "Close submenu" : "Open submenu"}
                >
                  ▼
                </button>
              )}
            </div>

            {hasChildren && (
              <div className={cn(styles.nested, isOpen && styles.nestedOpen)}>
                {renderMenu(item.children || [], level + 1)}
              </div>
            )}
          </li>
        );
      })}
    </ul>
  );

  if (loading) return <Loading />;
  if (error) return <P color="error">{error}</P>;

  return <nav className={styles.menuWrapper}>{renderMenu(menuTree)}</nav>;
};
