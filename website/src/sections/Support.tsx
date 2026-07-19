import { Button } from "@/components/ui/button"
import { DONATE_URL } from "@/config"
import { Coffee, Heart } from "lucide-react"

export default function Support() {
  return (
    <section id="support" className="bg-fl-50">
      <div className="mx-auto max-w-3xl px-6 py-20 text-center md:py-24">
        <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-fl-500/15 text-fl-600">
          <Coffee className="h-7 w-7" />
        </div>
        <h2 className="mt-6 text-3xl font-semibold tracking-tight text-ink">
          Support FileLore
        </h2>
        <p className="mx-auto mt-4 max-w-md text-lg leading-relaxed text-ink/65">
          FileLore is free. If it saves you time, consider buying me a coffee —
          donations fund more free tools.
        </p>
        <div className="mt-8">
          <Button
            asChild
            size="lg"
            className="h-12 bg-fl-500 px-8 text-base font-semibold text-ink hover:bg-fl-400"
          >
            <a href={DONATE_URL} target="_blank" rel="noopener noreferrer">
              <Coffee className="mr-2 h-5 w-5" />
              Buy me a coffee
            </a>
          </Button>
          <p className="mt-4 inline-flex items-center gap-1.5 text-[13px] text-ink/45">
            <Heart className="h-3.5 w-3.5" />
            Every coffee keeps the next tool free.
          </p>
        </div>
      </div>
    </section>
  )
}
