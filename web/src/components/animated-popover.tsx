import { useState, type ReactElement, type ReactNode } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";

export function AnimatedPopover({
  trigger,
  children,
  label,
  className,
}: {
  trigger: ReactElement;
  children: ReactNode;
  label: string;
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const reduced = useReducedMotion();
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>{trigger}</PopoverTrigger>
      <AnimatePresence>
        {open && (
          <PopoverContent
            forceMount
            asChild
            sideOffset={10}
            align="start"
            className={className}
            aria-label={label}
          >
            <motion.div
              initial={{ opacity: 0, y: reduced ? 0 : 4 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: reduced ? 0 : 3 }}
              transition={{ duration: reduced ? 0.06 : 0.14 }}
            >
              {children}
            </motion.div>
          </PopoverContent>
        )}
      </AnimatePresence>
    </Popover>
  );
}
