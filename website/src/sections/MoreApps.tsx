import { ArrowUpRight, Sparkles } from "lucide-react"

export default function MoreApps() {
  return (
    <section id="more-apps" className="bg-fl-50">
      <div className="mx-auto max-w-xl px-6 py-20 md:py-24">
        <div className="text-center">
          <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-fl-500/15 text-fl-600">
            <Sparkles className="h-7 w-7" />
          </div>
          <h2 className="mt-6 text-3xl font-semibold tracking-tight text-ink">
            More from this creator
          </h2>
          <p className="mx-auto mt-4 max-w-md text-lg leading-relaxed text-ink/65">
            FileLore is one of several free tools made by the same one-person
            studio.
          </p>
        </div>

        <a
          href="https://tagpanda.io"
          target="_blank"
          rel="noopener noreferrer"
          className="group mt-10 flex items-center gap-5 rounded-2xl border border-ink/10 bg-white p-6 shadow-sm transition hover:border-fl-500/40 hover:shadow-md"
        >
          <img
            src="/tagpanda-icon.png"
            alt="TagPanda app icon"
            className="h-16 w-16 shrink-0 rounded-2xl"
          />
          <div className="min-w-0 flex-1">
            <p className="text-lg font-semibold text-ink">
              TagPanda{" "}
              <span className="font-normal text-ink/50">
                — Save Everything. Ask Anything.
              </span>
            </p>
            <p className="mt-1 text-[15px] leading-relaxed text-ink/60">
              Chat with your bookmarks. TagPanda watches saved videos, reads
              articles, and organizes your library with AI.
            </p>
          </div>
          <ArrowUpRight className="h-6 w-6 shrink-0 text-ink/30 transition group-hover:text-fl-600" />
        </a>
      </div>
    </section>
  )
}
