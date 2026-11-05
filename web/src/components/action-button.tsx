import { motion } from "motion/react";
import { Button } from "@/components/ui/button";

// Compose with the shadcn button so every variant retains its focus and disabled states.
export const ActionButton = motion.create(Button);
