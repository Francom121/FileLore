import { FileText, Paperclip, Search } from "lucide-react"

const points = [
  {
    icon: FileText,
    title: "Prompt & model, kept",
    body: "The exact words, the model, the settings — written once, kept with the clip they made.",
  },
  {
    icon: Paperclip,
    title: "References ride along",
    body: "Source frames, mood shots, and links attach to the file as first-class citizens.",
  },
  {
    icon: Search,
    title: "Found again in seconds",
    body: "Search the prompt, get the file. Even months later, even after a rename.",
  },
]

export default function AICreators() {
  return (
    <section className="bg-fl-50">
      <div className="mx-auto max-w-6xl px-6 py-20 md:py-28">
        <div className="max-w-2xl">
          <p className="text-[13px] font-semibold uppercase tracking-[0.14em] text-fl-700">
            Made for AI creators
          </p>
          <h2 className="mt-3 text-3xl font-semibold tracking-tight text-ink md:text-4xl">
            Which prompt made this clip? The file knows.
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-ink/65">
            Generating ten takes to keep one? Keep the prompt, the model, and
            the reference links attached to every generated clip and image —
            and never lose which prompt made which video again.
          </p>
        </div>

        <div className="mt-12 grid gap-5 md:grid-cols-3">
          {points.map((p) => (
            <div
              key={p.title}
              className="rounded-2xl border border-fl-200/70 bg-white/70 p-6"
            >
              <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-fl-500/15 text-fl-700">
                <p.icon className="h-5 w-5" />
              </div>
              <h3 className="mt-4 font-semibold text-ink">{p.title}</h3>
              <p className="mt-1.5 text-[15px] leading-relaxed text-ink/60">
                {p.body}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
