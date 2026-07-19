import { Button } from "@/components/ui/button"
import { DOWNLOAD_SIZE, DOWNLOAD_URL } from "@/config"
import { Download, FolderDown, MousePointerClick, ShieldCheck, PanelTop } from "lucide-react"

const steps = [
  {
    icon: FolderDown,
    title: "Drag to Applications",
    body: "Unzip the download and drag FileLore into your Applications folder.",
  },
  {
    icon: MousePointerClick,
    title: "Right-click → Open",
    body: "On first launch only, right-click the app and choose Open — a one-time Gatekeeper bypass (FileLore is ad-hoc signed).",
  },
  {
    icon: ShieldCheck,
    title: "Enable the extensions",
    body: "In System Settings → Privacy & Security → Extensions, turn on FileLore's Finder and Quick Look extensions.",
  },
  {
    icon: PanelTop,
    title: "Find the quill",
    body: "If the menu-bar icon is hidden, click the » chevron and drag the quill out onto your menu bar.",
  },
]

export default function DownloadCTA() {
  return (
    <section id="download" className="scroll-mt-20 bg-ink text-white">
      <div className="relative mx-auto max-w-6xl overflow-hidden px-6 py-24 text-center md:py-32">
        <div
          aria-hidden
          className="pointer-events-none absolute left-1/2 top-1/2 h-[360px] w-[640px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-fl-500/15 blur-[120px]"
        />
        <img
          src="/logo-512.png"
          alt="FileLore logo"
          className="relative mx-auto h-20 w-20 rounded-[22px] shadow-lg ring-1 ring-white/15"
        />
        <h2 className="relative mt-8 text-3xl font-semibold tracking-tight md:text-5xl">
          Start giving your files a memory.
        </h2>
        <p className="relative mx-auto mt-4 max-w-md text-lg text-white/65">
          Notes that stay with your files — through renames, moves, and
          everything else.
        </p>
        <div className="relative mt-9">
          <Button
            asChild
            size="lg"
            className="h-12 bg-fl-500 px-8 text-base font-semibold text-ink hover:bg-fl-400"
          >
            <a href={DOWNLOAD_URL} download>
              <Download className="mr-2 h-5 w-5" />
              Download for Mac
            </a>
          </Button>
          <p className="mt-4 text-[13px] text-white/45">
            Free · {DOWNLOAD_SIZE} zip · macOS 26 or later
          </p>
        </div>

        {/* How to install */}
        <div className="relative mx-auto mt-16 max-w-4xl text-left">
          <h3 className="text-center text-sm font-semibold uppercase tracking-[0.14em] text-fl-300">
            How to install
          </h3>
          <ol className="mt-8 grid gap-4 sm:grid-cols-2">
            {steps.map((step, i) => (
              <li
                key={step.title}
                className="flex gap-4 rounded-2xl border border-white/10 bg-white/[0.04] p-5"
              >
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-fl-500/15 text-fl-300">
                  <step.icon className="h-5 w-5" />
                </div>
                <div>
                  <p className="text-[15px] font-semibold text-white">
                    <span className="mr-1.5 text-white/40">{i + 1}.</span>
                    {step.title}
                  </p>
                  <p className="mt-1 text-sm leading-relaxed text-white/60">
                    {step.body}
                  </p>
                </div>
              </li>
            ))}
          </ol>
        </div>
      </div>
    </section>
  )
}
