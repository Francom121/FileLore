import { Button } from "@/components/ui/button"
import { DOWNLOAD_SIZE, DOWNLOAD_SIZE_WINDOWS, DOWNLOAD_SIZE_WINDOWS_ARM64, DOWNLOAD_URL, DOWNLOAD_URL_DIAGNOSE, DOWNLOAD_URL_WINDOWS, DOWNLOAD_URL_WINDOWS_ARM64, GITHUB_RELEASES_URL } from "@/config"
import { Download, FolderDown, MousePointerClick, ShieldCheck, PanelTop, Trash2, Github } from "lucide-react"

const macSteps = [
  {
    icon: FolderDown,
    title: "Drag to Applications",
    body: "Unzip the download and drag FileLore into your Applications folder.",
  },
  {
    icon: MousePointerClick,
    title: "Allow it once",
    body: "On first launch macOS will say it can't verify FileLore (it's unsigned). Go to System Settings → Privacy & Security, scroll down, and click \"Open Anyway\" — one time only.",
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

const windowsSteps = [
  {
    icon: FolderDown,
    title: "Run the Setup",
    body: "Double-click FileLore-Windows-Setup-x64.exe — no admin needed. If SmartScreen appears: More info → Run anyway.",
  },
  {
    icon: ShieldCheck,
    title: "Updates are automatic",
    body: "FileLore checks for updates in the background and applies them on restart. Tray menu → Check for Updates… anytime.",
  },
  {
    icon: MousePointerClick,
    title: "Right-click any file",
    body: "Show more options → FileLore Note. Hotkeys: Ctrl+Alt+T new note, Ctrl+Alt+F search.",
  },
  {
    icon: Trash2,
    title: "Uninstall anytime",
    body: "Windows Settings → Apps → FileLore → Uninstall — removes the app and keeps your notes.",
  },
]

function StepList({ steps }: { steps: typeof macSteps }) {
  return (
    <ol className="mt-5 grid gap-4 sm:grid-cols-2">
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
  )
}

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
        <div className="relative mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row">
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
          <Button
            asChild
            size="lg"
            variant="outline"
            className="h-12 border-white/20 bg-transparent px-8 text-base font-semibold text-white/85 hover:bg-white/10 hover:text-white"
          >
            <a href={DOWNLOAD_URL_WINDOWS} download>
              <Download className="mr-2 h-5 w-5" />
              Download for Windows (x64)
            </a>
          </Button>
        </div>
        <p className="relative mt-4 text-[13px] text-white/45">
          Free · Mac {DOWNLOAD_SIZE} zip · macOS 26 or later
          <span className="mx-2 text-white/25">|</span>
          Windows {DOWNLOAD_SIZE_WINDOWS} Setup · Windows 10/11 x64
        </p>
        <p className="relative mt-2 text-[13px] text-white/45">
          Windows on ARM?{" "}
          <a
            href={DOWNLOAD_URL_WINDOWS_ARM64}
            download
            className="font-medium text-fl-300 underline decoration-fl-300/40 underline-offset-2 hover:text-fl-200"
          >
            Get the arm64 Setup
          </a>{" "}
          ({DOWNLOAD_SIZE_WINDOWS_ARM64})
        </p>
        <p className="relative mt-2 inline-flex items-center gap-1.5 text-[13px] text-white/45">
          <Github className="h-3.5 w-3.5" />
          Open source — every version also on{" "}
          <a
            href={GITHUB_RELEASES_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="font-medium text-fl-300 underline decoration-fl-300/40 underline-offset-2 hover:text-fl-200"
          >
            GitHub Releases
          </a>
        </p>

        {/* How to install */}
        <div className="relative mx-auto mt-16 max-w-4xl text-left">
          <h3 className="text-center text-sm font-semibold uppercase tracking-[0.14em] text-fl-300">
            How to install
          </h3>
          <p className="mt-8 text-[13px] font-semibold uppercase tracking-[0.12em] text-white/40">
            On macOS
          </p>
          <StepList steps={macSteps} />
          <p className="mt-10 text-[13px] font-semibold uppercase tracking-[0.12em] text-white/40">
            On Windows
          </p>
          <StepList steps={windowsSteps} />
          <p className="mt-4 text-sm text-white/50">
            Troubleshooting?{" "}
            <a
              href={DOWNLOAD_URL_DIAGNOSE}
              download
              className="font-medium text-fl-300 underline decoration-fl-300/40 underline-offset-2 hover:text-fl-200"
            >
              Grab FileLore-Diagnose.cmd
            </a>{" "}
            — it writes a diagnostics report to your Desktop; send it back for help.
          </p>
        </div>
      </div>
    </section>
  )
}
