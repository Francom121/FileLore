import ScreenshotFrame from "@/components/ScreenshotFrame"

export default function DemoVideo() {
  return (
    <section id="demo" className="border-t border-ink/5 bg-white">
      <div className="mx-auto max-w-5xl px-6 py-24 md:py-28">
        <div className="mx-auto max-w-2xl text-center">
          <p className="text-[13px] font-semibold uppercase tracking-[0.14em] text-fl-700">
            See it in action
          </p>
          <h2 className="mt-3 text-3xl font-semibold tracking-tight text-ink md:text-4xl">
            From Finder to filed, in seconds.
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-ink/65">
            A real, unedited capture: select a file, hit the shortcut, write
            the note, tag it, save — and it&rsquo;s still there when you come
            back.
          </p>
        </div>
        <div className="relative mx-auto mt-12 max-w-4xl">
          <div
            aria-hidden
            className="absolute -inset-6 rounded-[28px] bg-fl-500/10 blur-2xl"
          />
          <ScreenshotFrame className="relative">
            <video
              controls
              playsInline
              preload="metadata"
              poster="/screenshots/hero-editor.png"
              className="block w-full"
            >
              <source src="/filelore-demo.mp4" type="video/mp4" />
              Your browser doesn&rsquo;t support the video tag.
            </video>
          </ScreenshotFrame>
        </div>
      </div>
    </section>
  )
}
