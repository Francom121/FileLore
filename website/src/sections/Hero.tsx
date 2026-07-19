import { Button } from "@/components/ui/button"
import ScreenshotFrame from "@/components/ScreenshotFrame"
import { DOWNLOAD_SIZE, DOWNLOAD_URL } from "@/config"
import { Download } from "lucide-react"

export default function Hero() {
  return (
    <section id="top" className="relative overflow-hidden bg-ink text-white">
      {/* warm glows */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-40 left-1/2 h-[480px] w-[720px] -translate-x-1/2 rounded-full bg-fl-500/20 blur-[140px]"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -bottom-56 -left-40 h-[420px] w-[420px] rounded-full bg-fl-600/10 blur-[120px]"
      />

      <div className="relative mx-auto max-w-6xl px-6 pb-20 pt-36 md:pb-28 md:pt-44">
        <div className="mx-auto max-w-3xl text-center">
          <span className="inline-flex items-center rounded-full border border-fl-500/40 bg-fl-500/10 px-3.5 py-1 text-[13px] font-medium text-fl-300">
            Sticky notes that live on your files
          </span>

          <h1 className="mt-6 text-5xl font-semibold leading-[1.05] tracking-tight md:text-7xl">
            Your files{" "}
            <span className="bg-gradient-to-br from-fl-300 to-fl-500 bg-clip-text text-transparent">
              remember.
            </span>
          </h1>

          <p className="mx-auto mt-6 max-w-xl text-lg leading-relaxed text-white/70">
            Attach notes, prompts, and reference files to any file. They travel
            with it — no database, no cloud, no lock-in.
          </p>

          <div className="mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row">
            <Button
              asChild
              size="lg"
              className="h-12 bg-fl-500 px-7 text-base font-semibold text-ink hover:bg-fl-400"
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
              className="h-12 border-white/20 bg-transparent px-7 text-base text-white/85 hover:bg-white/10 hover:text-white"
            >
              <a href="#how-it-works">See how it works</a>
            </Button>
          </div>
          <p className="mt-4 text-[13px] text-white/45">
            Free · {DOWNLOAD_SIZE} · macOS 26 or later
          </p>
        </div>

        {/* hero screenshot */}
        <div className="relative mx-auto mt-16 max-w-4xl md:mt-20">
          <div
            aria-hidden
            className="absolute -inset-8 rounded-[32px] bg-fl-500/15 blur-3xl"
          />
          <ScreenshotFrame className="relative shadow-2xl ring-white/15">
            <img
              src="/screenshots/hero-editor.png"
              alt="FileLore note editor with media peek: a promo video plays on the left, its note with prompt, model, and links on the right"
              className="block w-full"
            />
          </ScreenshotFrame>
        </div>
      </div>
    </section>
  )
}
