import { Button } from "@/components/ui/button"
import { Download } from "lucide-react"

const links = [
  { href: "#features", label: "Features" },
  { href: "#how-it-works", label: "How it works" },
  { href: "#download", label: "Download" },
]

export default function Nav() {
  return (
    <header className="fixed inset-x-0 top-0 z-50 border-b border-white/10 bg-ink/80 backdrop-blur-md">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-6">
        <a href="#top" className="flex items-center gap-2.5">
          <img
            src="/logo-512.png"
            alt="FileLore logo"
            className="h-8 w-8 rounded-[9px] shadow-sm"
          />
          <span className="text-[17px] font-semibold tracking-tight text-white">
            FileLore
          </span>
        </a>
        <nav className="hidden items-center gap-8 md:flex">
          {links.map((l) => (
            <a
              key={l.href}
              href={l.href}
              className="text-sm text-white/70 transition-colors hover:text-white"
            >
              {l.label}
            </a>
          ))}
        </nav>
        <Button
          asChild
          size="sm"
          className="bg-fl-500 font-semibold text-ink hover:bg-fl-400"
        >
          <a href="#download">
            <Download className="mr-1.5 h-4 w-4" />
            Download
          </a>
        </Button>
      </div>
    </header>
  )
}
