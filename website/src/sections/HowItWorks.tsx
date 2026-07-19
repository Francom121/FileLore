const steps = [
  {
    n: "1",
    title: "Drop a file on FileLore",
    body: "Or press \u2325T on any Finder selection. The note editor opens with your file already in it.",
  },
  {
    n: "2",
    title: "Write your note",
    body: "Body, tags, links, reference files. Start from a template if you like.",
  },
  {
    n: "3",
    title: "It\u2019s part of the file forever",
    body: "The note lives on the file itself. Through renames, moves, and everything else.",
  },
]

export default function HowItWorks() {
  return (
    <section id="how-it-works" className="scroll-mt-20 border-t border-ink/5 bg-fl-50/60">
      <div className="mx-auto max-w-6xl px-6 py-20 md:py-28">
        <div className="max-w-2xl">
          <p className="text-[13px] font-semibold uppercase tracking-[0.14em] text-fl-700">
            How it works
          </p>
          <h2 className="mt-3 text-3xl font-semibold tracking-tight text-ink md:text-4xl">
            Three steps. Zero ceremony.
          </h2>
        </div>

        <div className="mt-12 grid gap-10 md:grid-cols-3 md:gap-8">
          {steps.map((s) => (
            <div key={s.n}>
              <div className="flex h-11 w-11 items-center justify-center rounded-full bg-fl-500 text-lg font-semibold text-ink shadow-sm">
                {s.n}
              </div>
              <h3 className="mt-5 text-lg font-semibold text-ink">{s.title}</h3>
              <p className="mt-2 leading-relaxed text-ink/60">{s.body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
