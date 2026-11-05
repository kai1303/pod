import { lazy, Suspense } from "react";
import Editor from "./editor/Editor";
const DesignSystem = lazy(() => import("./DesignSystem"));
export default function App() {
  const catalog =
    location.pathname.startsWith("/design-system") ||
    new URLSearchParams(location.search).get("view") === "design-system";
  return catalog ? (
    <Suspense fallback={<p>Loading design system…</p>}>
      <DesignSystem />
    </Suspense>
  ) : (
    <Editor />
  );
}
