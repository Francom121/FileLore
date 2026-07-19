import {
  Feather,
  FileDown,
  Keyboard,
  LayoutTemplate,
  Paperclip,
  Pin,
  Play,
  Search,
  StickyNote,
  PanelTop,
} from "lucide-react"
import ScreenshotFrame from "@/components/ScreenshotFrame"

const features = [
  {
    icon: StickyNote,
    title: "Notes on the file itself",
    body: "Stored as an extended attribute on the file — it survives renames and moves on the same drive.",
  },
  {
    icon: Play,
    title: "Media peek",
    body: "Video plays beside your note, right in the editor.",
  },
  {
    icon: Paperclip,
    title: "Linked files",
    body: "Reference photos ride along as bookmarks, with broken-link detection.",
  },
  {
    icon: Pin,
    title: "Tags & pinned tags",
    body: "Tag everything; pin the tags you live in.",
  },
  {
    icon: Search,
    title: "Instant search",
    body: "\u201CWhich file used this prompt?\u201D — answered as you type.",
  },
  {
    icon: Feather,
    title: "Finder badge",
    body: "An amber quill marks noted files right in Finder.",
  },
  {
    icon: FileDown,
    title: "Batch Markdown export",
    body: "Any selection of notes, out to clean Markdown in one move.",
  },
  {
    icon: LayoutTemplate,
    title: "Note templates",
    body: "Start from Blank or AI Generation and fill in the blanks.",
  },
  {
    icon: PanelTop,
    title: "Menu bar quick access",
    body: "Your ten most recent notes, one click away.",
  },
  {
    icon: Keyboard,
    title: "Customizable global hotkeys",
    body: "\u2325T to note, \u21E7\u2318F to search — rebind to whatever fits your hands.",
  },
]

export default function Features() {
  return (
    <section id="features" className="scroll-mt-20 bg-white">
      <div className="mx-auto max-w-6xl px-6 py-20 md:py-28">
        <div className="max-w-2xl">
          <p className="text-[13px] font-semibold uppercase tracking-[0.14em] text-fl-700">
            Features
          </p>
          <h2 className="mt-3 text-3xl font-semibold tracking-tight text-ink md:text-4xl">
            Everything a note should be — and nowhere it shouldn&rsquo;t.
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-ink/65">
            No account, no sync service, no proprietary vault. Just your files,
            carrying their own context.
          </p>
        </div>

        <div className="mt-12 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {features.map((f) => (
            <div
              key={f.title}
              className="group rounded-2xl border border-ink/10 bg-white p-5 transition-colors hover:border-fl-400/60 hover:bg-fl-50/60"
            >
              <div className="flex items-center gap-3">
                <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-fl-500/15 text-fl-700 transition-colors group-hover:bg-fl-500/25">
                  <f.icon className="h-[18px] w-[18px]" />
                </div>
                <h3 className="font-semibold text-ink">{f.title}</h3>
              </div>
              <p className="mt-2.5 text-[15px] leading-relaxed text-ink/60">
                {f.body}
              </p>
            </div>
          ))}
        </div>

        {/* Spotlight: search */}
        <div className="mt-24 grid items-center gap-10 md:grid-cols-2 md:gap-14">
          <div>
            <p className="text-[13px] font-semibold uppercase tracking-[0.14em] text-fl-700">
              Instant search
            </p>
            <h3 className="mt-3 text-2xl font-semibold tracking-tight text-ink md:text-3xl">
              Every note, one keystroke away.
            </h3>
            <p className="mt-4 leading-relaxed text-ink/65">
              A Spotlight-style panel over everything you&rsquo;ve noted —
              ranked results as you type, across names, tags, and body text.
              Pin the tags you live in and they stay at the top, ready to
              filter with one click.
            </p>
            <ul className="mt-5 space-y-2.5 text-[15px] text-ink/70">
              <li className="flex gap-2.5">
                <span className="mt-[9px] h-1.5 w-1.5 shrink-0 rounded-full bg-fl-500" />
                Live, ranked results — name, then tags, then body
              </li>
              <li className="flex gap-2.5">
                <span className="mt-[9px] h-1.5 w-1.5 shrink-0 rounded-full bg-fl-500" />
                Pinned tags sit above everything, one click to filter
              </li>
              <li className="flex gap-2.5">
                <span className="mt-[9px] h-1.5 w-1.5 shrink-0 rounded-full bg-fl-500" />
                Open the note or reveal the file in Finder — your call
              </li>
            </ul>
          </div>
          <div className="relative">
            <div
              aria-hidden
              className="absolute -inset-6 rounded-[28px] bg-fl-500/10 blur-2xl"
            />
            <ScreenshotFrame className="relative">
              <img
                src="/screenshots/search-pinned-tags.png"
                alt="FileLore search window with pinned tag chips — downloads, video, tagpanda — and live results across noted files"
                className="block w-full"
              />
            </ScreenshotFrame>
          </div>
        </div>

        {/* Spotlight: Finder badge */}
        <div className="mt-24 grid items-center gap-10 md:grid-cols-2 md:gap-14">
          <div className="relative order-last md:order-first">
            <div
              aria-hidden
              className="absolute -inset-6 rounded-[28px] bg-fl-500/10 blur-2xl"
            />
            <ScreenshotFrame className="relative">
              <img
                src="/screenshots/finder-badge.png"
                alt="Finder window in icon view showing the amber FileLore quill badge on noted files"
                className="block w-full"
              />
            </ScreenshotFrame>
          </div>
          <div>
            <p className="text-[13px] font-semibold uppercase tracking-[0.14em] text-fl-700">
              Finder badge
            </p>
            <h3 className="mt-3 text-2xl font-semibold tracking-tight text-ink md:text-3xl">
              You can see it in Finder.
            </h3>
            <p className="mt-4 leading-relaxed text-ink/65">
              Noted files carry the amber quill badge in icon and list view.
              No app to open, no panel to check — the marker is just there,
              the moment you save a note. Right-click any file to add or edit
              its note without leaving Finder.
            </p>
          </div>
        </div>
      </div>
    </section>
  )
}
