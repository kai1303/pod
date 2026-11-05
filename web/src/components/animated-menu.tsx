import { useState, type ReactElement, type ReactNode } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

export function AnimatedMenu({
  trigger,
  children,
  align = "start",
  label,
  className,
}: {
  trigger: ReactElement;
  children: ReactNode;
  align?: "start" | "center" | "end";
  label: string;
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const reduced = useReducedMotion();
  return (
    <DropdownMenu open={open} onOpenChange={setOpen} modal={false}>
      <DropdownMenuTrigger asChild>{trigger}</DropdownMenuTrigger>
      <AnimatePresence>
        {open && (
          <DropdownMenuContent
            forceMount
            asChild
            align={align}
            sideOffset={8}
            className={className}
            aria-label={label}
          >
            <motion.div
              initial={{
                opacity: 0,
                y: reduced ? 0 : -4,
                scale: reduced ? 1 : 0.97,
              }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{
                opacity: 0,
                y: reduced ? 0 : -3,
                scale: reduced ? 1 : 0.98,
              }}
              transition={{
                duration: reduced ? 0.06 : 0.14,
                ease: [0.2, 0.8, 0.2, 1],
              }}
              style={{
                transformOrigin:
                  "var(--radix-dropdown-menu-content-transform-origin)",
              }}
            >
              {children}
            </motion.div>
          </DropdownMenuContent>
        )}
      </AnimatePresence>
    </DropdownMenu>
  );
}
