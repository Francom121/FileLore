import type { ReactNode } from "react"
import { cn } from "@/lib/utils"

/**
 * A clean, consistent frame for app screenshots: rounded corners, a subtle
 * ring, and a soft shadow. `overflow-hidden` clips the image to the rounded
 * frame so raw window-edge artifacts can never show through.
 */
export default function ScreenshotFrame({
  children,
  className = "",
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <div
      className={cn(
        "overflow-hidden rounded-xl shadow-xl ring-1 ring-ink/10",
        className
      )}
    >
      {children}
    </div>
  )
}
