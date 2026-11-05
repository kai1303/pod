import { ArrowUpRight, Layers, X, type LucideIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from "@/components/ui/sidebar";

type NavigationItem = { id: string; title: string; Icon: LucideIcon };
export function CatalogSidebar({
  items,
  active,
  onNavigate,
}: {
  items: NavigationItem[];
  active: string;
  onNavigate: (id: string) => void;
}) {
  const { isMobile, setOpenMobile } = useSidebar();
  function navigate(id: string) {
    onNavigate(id);
    if (isMobile) setOpenMobile(false);
  }
  return (
    <Sidebar className="catalog-sidebar">
      <SidebarHeader className="catalog-sidebar-header">
        <div className="catalog-brand-row">
          <a
            className="brand"
            href="#overview"
            onClick={() => navigate("overview")}
          >
            <img src={`${import.meta.env.BASE_URL}pod.png`} alt="" />
            <span>
              Pod<span className="brand-note">Design system</span>
            </span>
          </a>
          {isMobile && (
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label="Close navigation"
              onClick={() => setOpenMobile(false)}
            >
              <X />
            </Button>
          )}
        </div>
      </SidebarHeader>
      <SidebarContent className="catalog-sidebar-content">
        <span className="nav-label">COMPONENTS</span>
        <nav aria-label="Components">
          <SidebarMenu>
            {items.map(({ id, title, Icon }) => (
              <SidebarMenuItem key={id}>
                <SidebarMenuButton
                  asChild
                  isActive={active === id}
                  className={active === id ? "nav-item active" : "nav-item"}
                >
                  <a
                    href={`#${id}`}
                    onClick={() => navigate(id)}
                    aria-current={active === id ? "location" : undefined}
                  >
                    <Icon className="size-4" />
                    <span>{title}</span>
                    {id === "overview" && (
                      <span className="nav-count">
                        {String(items.length - 1).padStart(2, "0")}
                      </span>
                    )}
                  </a>
                </SidebarMenuButton>
              </SidebarMenuItem>
            ))}
          </SidebarMenu>
        </nav>
      </SidebarContent>
      <SidebarFooter className="catalog-sidebar-footer">
        <div className="sidebar-note">
          <span className="sidebar-note-icon">
            <Layers className="size-4" />
          </span>
          <strong>One system. Every layer.</strong>
          <span>PDF workspace components.</span>
        </div>
        <a
          href="https://ui.shadcn.com/docs"
          target="_blank"
          rel="noreferrer"
          className="docs-link"
        >
          Component documentation
          <ArrowUpRight className="size-3.5" />
        </a>
      </SidebarFooter>
    </Sidebar>
  );
}
